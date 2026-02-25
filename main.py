import os
import re
import tempfile
import shutil
import subprocess
import uuid
import json
import asyncio
import threading

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, StreamingResponse, FileResponse
from pydantic import BaseModel
from pytubefix import YouTube


app = FastAPI()

# ── Progress Tracking ────────────────────────────────────────────────────────
download_tasks = {}


class DownloadTask:
    def __init__(self):
        self.stage = "starting"
        self.percent = 0
        self.downloaded = 0
        self.total = 0
        self.result = None
        self.error = None
        self.done = False

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DOWNLOAD_DIR = tempfile.mkdtemp(prefix="ytdl_")
FFMPEG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bin", "ffmpeg")


class FetchRequest(BaseModel):
    url: str


class DownloadRequest(BaseModel):
    url: str
    itag: int
    mode: str  # "video" or "audio"


class DownloadToDiskRequest(BaseModel):
    url: str
    itag: int
    mode: str        # "video" or "audio"
    output_dir: str  # absolute path to save the file


def _sanitize_url(url: str) -> str:
    """Validate that the string looks like a YouTube URL."""
    url = url.strip()
    pattern = r"^https?://(www\.)?(youtube\.com|youtu\.be)/.+"
    if not re.match(pattern, url):
        raise ValueError("Invalid YouTube URL")
    return url


def _get_yt(url: str) -> YouTube:
    """Create a YouTube object with error handling."""
    try:
        return YouTube(url)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to fetch video info: {str(e)}")


def _download_and_process(url: str, itag: int, mode: str):
    """
    Shared download logic. Downloads and processes the video/audio.
    Returns (final_path, filename, dl_dir).
    Caller is responsible for cleaning up dl_dir.
    """
    yt = _get_yt(url)
    stream = yt.streams.get_by_itag(itag)
    if not stream:
        raise HTTPException(status_code=400, detail=f"Stream with itag {itag} not found")

    dl_dir = tempfile.mkdtemp(dir=DOWNLOAD_DIR)
    safe_title = re.sub(r'[^\w\s\-.]', '', yt.title)[:100].strip() or "download"

    try:
        if mode == "audio":
            audio_path = stream.download(output_path=dl_dir, filename="audio_raw")
            mp3_path = os.path.join(dl_dir, f"{safe_title}.mp3")
            result = subprocess.run(
                [FFMPEG_PATH, "-y", "-i", audio_path, "-vn",
                 "-acodec", "libmp3lame", "-ab", "192k", mp3_path],
                capture_output=True, timeout=120,
            )
            if result.returncode != 0:
                raise Exception(f"FFmpeg error: {result.stderr.decode()[:200]}")
            final_path = mp3_path
        else:
            video_path = stream.download(output_path=dl_dir, filename="video_raw")
            audio_stream = (
                yt.streams.filter(only_audio=True, mime_type="audio/mp4").order_by('abr').desc().first()
                or yt.streams.filter(only_audio=True).order_by('abr').desc().first()
            )
            if audio_stream:
                audio_path = audio_stream.download(output_path=dl_dir, filename="audio_raw")
                merged_path = os.path.join(dl_dir, f"{safe_title}.mp4")
                result = subprocess.run(
                    [FFMPEG_PATH, "-y",
                     "-i", video_path, "-i", audio_path,
                     "-c:v", "copy", "-c:a", "aac",
                     "-movflags", "+faststart",
                     merged_path],
                    capture_output=True, timeout=300,
                )
                if result.returncode != 0:
                    raise Exception(f"FFmpeg merge error: {result.stderr.decode()[:200]}")
                final_path = merged_path
            else:
                final_path = video_path

    except HTTPException:
        raise
    except Exception as e:
        shutil.rmtree(dl_dir, ignore_errors=True)
        raise HTTPException(status_code=500, detail=str(e))

    if not os.path.exists(final_path) or os.path.getsize(final_path) == 0:
        shutil.rmtree(dl_dir, ignore_errors=True)
        raise HTTPException(status_code=500, detail="Download failed - empty file")

    return final_path, os.path.basename(final_path), dl_dir


@app.get("/", response_class=HTMLResponse)
async def index():
    return FileResponse(
        os.path.join(os.path.dirname(__file__), "static", "index.html"),
        media_type="text/html",
    )


@app.post("/api/formats")
async def fetch_formats(body: FetchRequest):
    """Return deduplicated video resolutions and audio quality options."""
    try:
        url = _sanitize_url(body.url)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid YouTube URL")

    yt = _get_yt(url)

    video_by_height = {}
    for s in yt.streams.filter(only_video=True, mime_type="video/mp4"):
        height = int(s.resolution.replace("p", "")) if s.resolution else 0
        if height < 144:
            continue
        bitrate = s.bitrate or 0
        if height not in video_by_height or bitrate > (video_by_height[height]["bitrate"] or 0):
            video_by_height[height] = {
                "itag": s.itag,
                "resolution": s.resolution,
                "height": height,
                "mime_type": s.mime_type,
                "filesize": s.filesize_approx,
                "bitrate": bitrate,
            }

    video_formats = sorted(video_by_height.values(), key=lambda x: x["height"], reverse=True)

    audio_by_abr = {}
    for s in yt.streams.filter(only_audio=True):
        abr_str = s.abr or "0kbps"
        abr_num = int(abr_str.replace("kbps", "")) if "kbps" in str(abr_str) else 0
        key = f"{abr_num}_{s.mime_type}"
        if key not in audio_by_abr or (s.filesize_approx or 0) > (audio_by_abr[key].get("filesize") or 0):
            audio_by_abr[key] = {
                "itag": s.itag,
                "abr": abr_str,
                "abr_num": abr_num,
                "mime_type": s.mime_type,
                "filesize": s.filesize_approx,
            }

    audio_formats = sorted(audio_by_abr.values(), key=lambda x: x["abr_num"], reverse=True)

    return {
        "title": yt.title,
        "thumbnail": yt.thumbnail_url,
        "duration": yt.length,
        "channel": yt.author,
        "video_formats": video_formats,
        "audio_formats": audio_formats,
    }


@app.post("/api/download")
async def download_file(body: DownloadRequest):
    """Download the selected format and stream it to the client."""
    try:
        url = _sanitize_url(body.url)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid YouTube URL")

    final_path, base_name, dl_dir = _download_and_process(url, body.itag, body.mode)
    file_size = os.path.getsize(final_path)

    async def stream_and_cleanup():
        try:
            with open(final_path, "rb") as f:
                while True:
                    chunk = f.read(1024 * 1024)
                    if not chunk:
                        break
                    yield chunk
        finally:
            shutil.rmtree(dl_dir, ignore_errors=True)

    return StreamingResponse(
        stream_and_cleanup(),
        media_type="application/octet-stream",
        headers={
            "Content-Disposition": f'attachment; filename="{base_name}"',
            "Content-Length": str(file_size),
        },
    )


@app.post("/api/download-to-disk")
async def download_to_disk(body: DownloadToDiskRequest):
    """Download the selected format and save it to a specified directory on disk."""
    try:
        url = _sanitize_url(body.url)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid YouTube URL")

    if not os.path.isdir(body.output_dir):
        raise HTTPException(status_code=400, detail=f"Output directory does not exist: {body.output_dir}")

    final_path, filename, dl_dir = _download_and_process(url, body.itag, body.mode)

    try:
        dest_path = os.path.join(body.output_dir, filename)
        # Handle filename collision
        base, ext = os.path.splitext(filename)
        counter = 1
        while os.path.exists(dest_path):
            dest_path = os.path.join(body.output_dir, f"{base} ({counter}){ext}")
            counter += 1
        shutil.move(final_path, dest_path)
    except Exception as e:
        shutil.rmtree(dl_dir, ignore_errors=True)
        raise HTTPException(status_code=500, detail=f"Failed to save file: {str(e)}")
    finally:
        shutil.rmtree(dl_dir, ignore_errors=True)

    return {"file_path": dest_path, "filename": os.path.basename(dest_path)}


@app.post("/api/download-start")
async def download_start(body: DownloadToDiskRequest):
    """Start a download task in the background and return a task_id for progress tracking."""
    try:
        url = _sanitize_url(body.url)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid YouTube URL")

    if not os.path.isdir(body.output_dir):
        raise HTTPException(status_code=400, detail=f"Output directory does not exist: {body.output_dir}")

    task_id = str(uuid.uuid4())
    task = DownloadTask()
    download_tasks[task_id] = task

    thread = threading.Thread(
        target=_download_with_progress,
        args=(task, url, body.itag, body.mode, body.output_dir),
        daemon=True,
    )
    thread.start()

    return {"task_id": task_id}


def _download_with_progress(task, url, itag, mode, output_dir):
    """Background worker that downloads with progress callbacks."""
    try:
        def on_progress(stream, chunk, bytes_remaining):
            total = stream.filesize or 0
            downloaded = total - bytes_remaining
            task.downloaded = downloaded
            task.total = total
            if total > 0:
                task.percent = min(int(downloaded / total * 100), 100)

        yt = YouTube(url, on_progress_callback=on_progress)
        stream = yt.streams.get_by_itag(itag)
        if not stream:
            task.error = f"Stream with itag {itag} not found"
            task.done = True
            return

        dl_dir = tempfile.mkdtemp(dir=DOWNLOAD_DIR)
        safe_title = re.sub(r'[^\w\s\-.]', '', yt.title)[:100].strip() or "download"

        if mode == "audio":
            task.stage = "downloading"
            task.percent = 0
            audio_path = stream.download(output_path=dl_dir, filename="audio_raw")

            task.stage = "converting"
            task.percent = 0
            mp3_path = os.path.join(dl_dir, f"{safe_title}.mp3")
            result = subprocess.run(
                [FFMPEG_PATH, "-y", "-i", audio_path, "-vn",
                 "-acodec", "libmp3lame", "-ab", "192k", mp3_path],
                capture_output=True, timeout=120,
            )
            if result.returncode != 0:
                raise Exception(f"FFmpeg error: {result.stderr.decode()[:200]}")
            final_path = mp3_path
        else:
            task.stage = "downloading"
            task.percent = 0
            video_path = stream.download(output_path=dl_dir, filename="video_raw")

            audio_stream = (
                yt.streams.filter(only_audio=True, mime_type="audio/mp4").order_by('abr').desc().first()
                or yt.streams.filter(only_audio=True).order_by('abr').desc().first()
            )
            if audio_stream:
                task.stage = "downloading_audio"
                task.percent = 0
                task.downloaded = 0
                task.total = 0
                audio_path = audio_stream.download(output_path=dl_dir, filename="audio_raw")

                task.stage = "merging"
                task.percent = 0
                merged_path = os.path.join(dl_dir, f"{safe_title}.mp4")
                result = subprocess.run(
                    [FFMPEG_PATH, "-y",
                     "-i", video_path, "-i", audio_path,
                     "-c:v", "copy", "-c:a", "aac",
                     "-movflags", "+faststart",
                     merged_path],
                    capture_output=True, timeout=300,
                )
                if result.returncode != 0:
                    raise Exception(f"FFmpeg merge error: {result.stderr.decode()[:200]}")
                final_path = merged_path
            else:
                final_path = video_path

        if not os.path.exists(final_path) or os.path.getsize(final_path) == 0:
            shutil.rmtree(dl_dir, ignore_errors=True)
            task.error = "Download failed - empty file"
            task.done = True
            return

        # Move to output directory
        filename = os.path.basename(final_path)
        dest_path = os.path.join(output_dir, filename)
        base, ext = os.path.splitext(filename)
        counter = 1
        while os.path.exists(dest_path):
            dest_path = os.path.join(output_dir, f"{base} ({counter}){ext}")
            counter += 1
        shutil.move(final_path, dest_path)
        shutil.rmtree(dl_dir, ignore_errors=True)

        task.stage = "complete"
        task.percent = 100
        task.result = {"file_path": dest_path, "filename": os.path.basename(dest_path)}
        task.done = True

    except Exception as e:
        task.error = str(e)
        task.done = True


@app.get("/api/download-progress/{task_id}")
async def download_progress(task_id: str):
    """SSE endpoint that streams download progress for a given task."""
    task = download_tasks.get(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    async def event_stream():
        while True:
            data = {
                "stage": task.stage,
                "percent": task.percent,
                "downloaded": task.downloaded,
                "total": task.total,
            }
            if task.result:
                data["result"] = task.result
            if task.error:
                data["error"] = task.error

            yield f"data: {json.dumps(data)}\n\n"

            if task.done:
                download_tasks.pop(task_id, None)
                break

            await asyncio.sleep(0.3)

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "Connection": "keep-alive"},
    )


@app.on_event("shutdown")
def cleanup():
    shutil.rmtree(DOWNLOAD_DIR, ignore_errors=True)
