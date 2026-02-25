# YT Downloader for Premiere Pro

A YouTube video and audio downloader that runs as a **Premiere Pro extension panel**. Paste a YouTube URL, pick your quality, and download — right from your editing timeline. Optionally import the downloaded file directly into your Premiere Pro project.

Also works as a **standalone web app** in your browser.

Built with FastAPI, pytubefix, and ffmpeg.

![Made with love by JD & Claude](https://img.shields.io/badge/made%20with%20%E2%9D%A4%EF%B8%8F%20by-JD%20%26%20Claude-red)

---

## Features

- **Download YouTube videos** in up to 4K resolution (MP4 with audio)
- **Download audio only** as MP3 at 192 kbps
- **Real-time progress bar** showing download, merge, and conversion stages
- **Premiere Pro panel** — use it without leaving your editor
- **Import to project** — auto-import downloaded files into a Premiere Pro bin
- **Choose download folder** — save files wherever you want
- **Start/Stop server** — control the backend right from the panel
- **Standalone web app** — also works at `localhost:8000` in any browser
- **Supports Premiere Pro 2020+** (CC 2020 through 2025 and beyond)

---

## Quick Install (DMG)

The easiest way to get started:

1. **Download** `YT-Downloader-Installer.dmg` from the [Releases](../../releases) page
2. **Open** the DMG and double-click **Install YT Downloader**
3. Follow the on-screen steps (it installs everything automatically)
4. **Restart Premiere Pro**
5. Go to **Window > Extensions > YT Downloader**

That's it! Click **Start the App** inside the panel and you're ready to go.

### What the installer does

- Copies the app to `~/Library/Application Support/YTDownloader/`
- Installs Python dependencies (`fastapi`, `uvicorn`, `pytubefix`)
- Sets up the Premiere Pro extension
- Enables unsigned extension support (CEP debug mode)

---

## Using in Premiere Pro

1. Open the panel: **Window > Extensions > YT Downloader**
2. Click the **Start the App** button (the dot turns green when the server is running)
3. Paste a YouTube URL and click **Fetch**
4. Pick your video quality or audio format
5. Choose a download folder (defaults to Desktop)
6. Optionally check **Import into Premiere Pro project** and set a bin name
7. Click **Download** — watch the progress bar as it downloads

### Tips

- You can download multiple files at once — each has its own progress bar
- The server keeps running until you click **Stop the App** or close Premiere Pro
- Video downloads automatically merge the best available audio track
- Audio downloads are converted to MP3 at 192 kbps

---

## Using as a Standalone Web App

Don't use Premiere Pro? No problem — it also works in your browser.

1. Start the server:
   ```bash
   cd /path/to/yt-downloader
   python3 -m uvicorn main:app --host 0.0.0.0 --port 8000
   ```
2. Open **http://localhost:8000** in your browser
3. Paste a URL, pick a format, download

Stop the server with `Ctrl + C`.

---

## Prerequisites

- **macOS** (10.15 Catalina or later)
- **Python 3.9+** (comes pre-installed on macOS)
- **Premiere Pro 2020+** (for the extension — the web app works without it)

---

## Manual Setup (for developers)

If you prefer to set things up manually instead of using the DMG:

```bash
# Clone the repo
git clone https://github.com/YOUR_USERNAME/yt-downloader.git
cd yt-downloader

# Install Python dependencies
pip3 install --user -r requirements.txt

# Download ffmpeg (macOS static build)
mkdir -p bin
curl -L https://evermeet.cx/ffmpeg/getrelease -o bin/ffmpeg.zip
cd bin && unzip ffmpeg.zip && rm ffmpeg.zip && chmod +x ffmpeg && cd ..

# Install the Premiere Pro extension
./install-cep.sh

# Restart Premiere Pro, then go to Window > Extensions > YT Downloader
```

### Building the DMG installer

```bash
# Requires: assets/icon.png (1024x1024 app icon)
./build-dmg.sh
# Output: build/YT-Downloader-Installer.dmg
```

---

## Project Structure

```
yt-downloader/
├── main.py                  # FastAPI backend (download, progress, formats API)
├── requirements.txt         # Python dependencies
├── bin/
│   └── ffmpeg               # Bundled ffmpeg binary (not in git — too large)
├── static/
│   └── index.html           # Standalone web app frontend
├── cep/                     # Premiere Pro CEP extension
│   ├── CSXS/
│   │   └── manifest.xml     # Extension manifest (targets PPRO 2020+)
│   ├── client/
│   │   ├── index.html       # Panel HTML
│   │   ├── css/panel.css    # Panel styles (dark theme)
│   │   ├── js/panel.js      # Panel logic (server mgmt, downloads, progress)
│   │   └── js/CSInterface.js # Adobe CEP SDK
│   └── host/
│       └── premiere.jsx     # ExtendScript (import files into Premiere Pro)
├── assets/
│   └── icon.png             # App icon (1024x1024)
├── installer/
│   ├── install.sh           # Installer script
│   ├── uninstall.command    # Uninstaller script
│   └── Info.plist           # macOS .app bundle config
├── build-dmg.sh             # Builds the DMG installer
├── install-cep.sh           # Dev install script (symlinks extension)
└── .gitignore
```

---

## How It Works

```
Premiere Pro Panel                    FastAPI Backend
┌──────────────────┐                 ┌──────────────────┐
│                  │   HTTP/SSE      │                  │
│  Paste URL       │ ──────────────> │  Fetch formats   │
│  Pick quality    │ <────────────── │  (pytubefix)     │
│  Download btn    │ ──────────────> │  Download stream │
│  Progress bar    │ <── SSE ─────── │  Merge with      │
│                  │                 │  ffmpeg           │
│  Import to       │                 │  Save to disk    │
│  Premiere Pro ───┼── ExtendScript ─┼──────────────────┘
│                  │                 │
└──────────────────┘
```

1. **Panel** sends the YouTube URL to the backend
2. **Backend** uses pytubefix to fetch available formats
3. User picks a quality; backend downloads video + audio streams separately
4. **ffmpeg** merges them into a single MP4 (or converts to MP3)
5. **Progress** is streamed back via Server-Sent Events (SSE)
6. Optionally, **ExtendScript** imports the file into the Premiere Pro project

---

## Uninstalling

**If installed via DMG:** Open the DMG again and double-click **Uninstall YT Downloader**

**If installed manually:**
```bash
rm -rf ~/Library/Application\ Support/YTDownloader
rm -f ~/Library/Application\ Support/Adobe/CEP/extensions/com.ytdownloader.panel
```

---

## Credits

Made with love by [JD](https://x.com/DholakiaJaydeep) & Claude
