/* global CSInterface */

// ── Globals ──────────────────────────────────────────────────────────────────
var csInterface = new CSInterface();
var API_BASE = "http://localhost:8000";
var currentUrl = "";
var serverProcess = null;
var serverOnline = false;
var healthPollTimer = null;

// Node.js modules (available inside CEP with --enable-nodejs)
var childProcess, nodePath, nodeOs, nodeFs;
try {
  childProcess = require("child_process");
  nodePath = require("path");
  nodeOs = require("os");
  nodeFs = require("fs");
} catch (e) {
  // Not in CEP / Node.js not available
}

// ── Init ─────────────────────────────────────────────────────────────────────

(function init() {
  // Set default output directory to Desktop
  if (nodeOs && nodePath) {
    document.getElementById("output-dir").value = nodePath.join(nodeOs.homedir(), "Desktop");
  }

  // Check health immediately, then start polling
  checkBackendHealth();
  healthPollTimer = setInterval(checkBackendHealth, 3000);

  // Enter key triggers fetch
  document.getElementById("url-input").addEventListener("keydown", function (e) {
    if (e.key === "Enter") fetchFormats();
  });

  // Browse button
  document.getElementById("browse-btn").addEventListener("click", browseFolder);

  // Import checkbox toggle
  document.getElementById("import-premiere").addEventListener("change", function (e) {
    document.getElementById("bin-option").style.display = e.target.checked ? "block" : "none";
  });

  // Open external links in the system browser (CEP panels don't do this by default)
  document.getElementById("jd-link").addEventListener("click", function (e) {
    e.preventDefault();
    csInterface.openURLInDefaultBrowser("https://x.com/DholakiaJaydeep");
  });
})();


// ── Server Management ────────────────────────────────────────────────────────

function getProjectDir() {
  // The CEP extension is symlinked from the project's cep/ folder.
  // csInterface returns the symlink path, so we must resolve it first,
  // then go up one level to reach the project root.
  try {
    var extPath = csInterface.getSystemPath("extension");
    // Resolve symlink to the real path (e.g. .../1-ytdownloader/cep)
    var realPath = nodeFs.realpathSync(extPath);
    return nodePath.resolve(realPath, "..");
  } catch (e) {
    return "";
  }
}

function toggleServer() {
  if (serverOnline || serverProcess) {
    stopServer();
  } else {
    startServer();
  }
}

function startServer() {
  if (!childProcess) {
    showError("Cannot start server: Node.js not available in this environment.");
    return;
  }

  var projectDir = getProjectDir();
  if (!projectDir) {
    showError("Cannot determine project directory.");
    return;
  }

  var btn = document.getElementById("server-btn");
  var dot = document.getElementById("server-dot");

  btn.disabled = true;
  btn.textContent = "Starting...";
  dot.className = "server-dot starting";

  // CEP's Node.js doesn't inherit normal shell PATH — use full python3 path
  var pythonPath = "/usr/bin/python3";
  var home = nodeOs.homedir();
  var userSitePackages = nodePath.join(home, "Library", "Python", "3.9", "lib", "python", "site-packages");
  var userBin = nodePath.join(home, "Library", "Python", "3.9", "bin");

  // Build environment with correct PATH and PYTHONPATH
  var env = {};
  try { env = JSON.parse(JSON.stringify(process.env)); } catch (e) {}
  env.PATH = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + userBin + ":" + (env.PATH || "");
  env.PYTHONPATH = userSitePackages + ":" + (env.PYTHONPATH || "");
  env.HOME = home;

  try {
    // Use pipe for stderr so we can capture error messages
    serverProcess = childProcess.spawn(
      pythonPath,
      ["-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"],
      { cwd: projectDir, detached: false, stdio: ["ignore", "ignore", "pipe"], env: env }
    );

    // Collect stderr output for error reporting
    var stderrChunks = [];
    if (serverProcess.stderr) {
      serverProcess.stderr.on("data", function (chunk) {
        stderrChunks.push(chunk.toString());
      });
    }

    serverProcess.on("error", function (err) {
      showError("Failed to start server: " + err.message);
      serverProcess = null;
      btn.disabled = false;
      updateServerUI(false);
    });

    serverProcess.on("exit", function (code) {
      serverProcess = null;
      // If it exited immediately with an error, show the stderr output
      if (code !== 0 && code !== null && stderrChunks.length > 0) {
        var errMsg = stderrChunks.join("").trim().split("\n").pop();
        showError("Server exited: " + errMsg);
      }
      // The poll will pick up the offline state
    });

    // Wait a moment for uvicorn to boot, then re-enable button and let the poll take over
    setTimeout(function () { btn.disabled = false; }, 4000);

  } catch (e) {
    showError("Failed to start server: " + e.message);
    serverProcess = null;
    btn.disabled = false;
    updateServerUI(false);
  }
}

function stopServer() {
  var btn = document.getElementById("server-btn");
  var dot = document.getElementById("server-dot");

  btn.disabled = true;
  btn.textContent = "Stopping...";
  dot.className = "server-dot starting";

  // Kill the process we spawned
  if (serverProcess) {
    try {
      serverProcess.kill("SIGTERM");
    } catch (e) { /* ignore */ }
    serverProcess = null;
  }

  // Also kill anything on port 8000 as a safety net
  if (childProcess) {
    try {
      childProcess.execSync("/usr/sbin/lsof -ti:8000 | /usr/bin/xargs kill 2>/dev/null || true", { env: { PATH: "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" } });
    } catch (e) { /* ignore */ }
  }

  // Re-enable after a moment, poll will confirm the offline state
  setTimeout(function () { btn.disabled = false; }, 2000);
}


// ── Backend Health Check (polling) ───────────────────────────────────────────

async function checkBackendHealth() {
  try {
    var controller = new AbortController();
    var timeoutId = setTimeout(function () { controller.abort(); }, 2000);
    var resp = await fetch(API_BASE + "/api/formats", {
      method: "OPTIONS",
      signal: controller.signal,
    });
    clearTimeout(timeoutId);
    // Only count as online if we get an actual HTTP response (2xx or 4xx both mean the server is up)
    if (resp.status > 0) {
      serverOnline = true;
    } else {
      serverOnline = false;
    }
  } catch (e) {
    serverOnline = false;
  }
  updateServerUI(serverOnline);
}

function updateServerUI(online) {
  var btn = document.getElementById("server-btn");
  var dot = document.getElementById("server-dot");

  // Don't touch UI if button is mid-action (Starting.../Stopping...)
  if (btn.disabled) return;

  if (online) {
    dot.className = "server-dot online";
    btn.textContent = "Stop the App";
    btn.className = "btn-server stop";
  } else {
    dot.className = "server-dot offline";
    btn.textContent = "Start the App";
    btn.className = "btn-server start";
  }
}


// ── Folder Picker ────────────────────────────────────────────────────────────

function browseFolder() {
  var currentDir = document.getElementById("output-dir").value || "";
  try {
    var result = window.cep.fs.showOpenDialogEx(false, true, "Select download folder", currentDir);
    if (result && result.data && result.data.length > 0) {
      document.getElementById("output-dir").value = result.data[0];
    }
  } catch (e) {
    // Fallback: make input editable if CEP API not available
    document.getElementById("output-dir").removeAttribute("readonly");
    showError("Folder picker unavailable. Type the path manually.");
  }
}


// ── Utility ──────────────────────────────────────────────────────────────────

function formatBytes(bytes) {
  if (!bytes) return "\u2014";
  if (bytes < 1024) return bytes + " B";
  if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB";
  if (bytes < 1073741824) return (bytes / 1048576).toFixed(1) + " MB";
  return (bytes / 1073741824).toFixed(2) + " GB";
}

function formatDuration(seconds) {
  if (!seconds) return "";
  var h = Math.floor(seconds / 3600);
  var m = Math.floor((seconds % 3600) / 60);
  var s = seconds % 60;
  if (h > 0) return h + ":" + String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0");
  return m + ":" + String(s).padStart(2, "0");
}

function qualityLabel(height) {
  if (height >= 2160) return "4K";
  if (height >= 1440) return "2K";
  if (height >= 1080) return "1080p";
  if (height >= 720) return "720p";
  if (height >= 480) return "480p";
  if (height >= 360) return "360p";
  if (height >= 240) return "240p";
  return height + "p";
}


// ── Messages ─────────────────────────────────────────────────────────────────

function showError(msg) {
  var el = document.getElementById("error-msg");
  el.textContent = msg;
  el.classList.add("active");
  // Auto-hide after 8 seconds
  setTimeout(function () { el.classList.remove("active"); }, 8000);
}

function clearError() {
  document.getElementById("error-msg").classList.remove("active");
}

function showSuccess(msg) {
  var el = document.getElementById("success-msg");
  el.textContent = msg;
  el.classList.add("active");
  setTimeout(function () { el.classList.remove("active"); }, 5000);
}


// ── Fetch Formats ────────────────────────────────────────────────────────────

async function fetchFormats() {
  var url = document.getElementById("url-input").value.trim();
  if (!url) return;

  clearError();
  currentUrl = url;

  document.getElementById("video-info").classList.remove("active");
  document.getElementById("download-options").classList.remove("active");
  document.getElementById("formats-container").classList.remove("active");
  document.getElementById("loader").classList.add("active");
  document.getElementById("fetch-btn").disabled = true;

  try {
    var resp = await fetch(API_BASE + "/api/formats", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ url: url }),
    });

    if (!resp.ok) {
      var data = await resp.json();
      throw new Error(data.detail || "Failed to fetch formats");
    }

    var data = await resp.json();
    renderResults(data);
  } catch (err) {
    showError(err.message);
  } finally {
    document.getElementById("loader").classList.remove("active");
    document.getElementById("fetch-btn").disabled = false;
  }
}


// ── Render Results ───────────────────────────────────────────────────────────

function renderResults(data) {
  // Video info card
  document.getElementById("video-thumb").src = data.thumbnail;
  document.getElementById("video-title").textContent = data.title;
  document.getElementById("video-channel").textContent = data.channel;
  document.getElementById("video-duration").textContent = formatDuration(data.duration);
  document.getElementById("video-info").classList.add("active");

  // Show download options
  document.getElementById("download-options").classList.add("active");

  // Video formats
  var vBody = document.getElementById("video-tbody");
  vBody.innerHTML = "";
  document.getElementById("video-count").textContent = "(" + data.video_formats.length + ")";

  data.video_formats.forEach(function (f) {
    var tr = document.createElement("tr");
    var label = qualityLabel(f.height);
    tr.innerHTML =
      '<td><strong>' + label + '</strong></td>' +
      '<td><span class="badge badge-ext">MP4</span></td>' +
      '<td>' + formatBytes(f.filesize) + '</td>' +
      '<td><button class="btn-dl" data-itag="' + f.itag + '" data-mode="video" onclick="downloadFormat(this)">Download</button></td>';
    vBody.appendChild(tr);
  });

  // Audio formats
  var aBody = document.getElementById("audio-tbody");
  aBody.innerHTML = "";
  document.getElementById("audio-count").textContent = "(" + data.audio_formats.length + ")";

  data.audio_formats.forEach(function (f) {
    var tr = document.createElement("tr");
    tr.innerHTML =
      '<td><strong>' + (f.abr || "Auto") + '</strong></td>' +
      '<td><span class="badge badge-ext">MP3</span></td>' +
      '<td>' + formatBytes(f.filesize) + '</td>' +
      '<td><button class="btn-dl" data-itag="' + f.itag + '" data-mode="audio" onclick="downloadFormat(this)">Download</button></td>';
    aBody.appendChild(tr);
  });

  document.getElementById("formats-container").classList.add("active");
}


// ── Download (with progress) ─────────────────────────────────────────────────

async function downloadFormat(btn) {
  var itag = parseInt(btn.dataset.itag);
  var mode = btn.dataset.mode;
  var outputDir = document.getElementById("output-dir").value.trim();
  var importToPremiere = document.getElementById("import-premiere").checked;
  var binName = document.getElementById("bin-name").value.trim();

  if (!outputDir) {
    showError("Please select a download folder first.");
    return;
  }

  btn.disabled = true;

  // Replace button with progress bar UI
  var cell = btn.parentElement;
  var uid = "p" + itag + "_" + Date.now();
  btn.style.display = "none";
  cell.insertAdjacentHTML("beforeend",
    '<div class="dl-progress" id="' + uid + '">' +
      '<div class="dl-progress-bar"><div class="dl-progress-fill" id="' + uid + '-fill"></div></div>' +
      '<span class="dl-progress-text" id="' + uid + '-text">Starting...</span>' +
    '</div>'
  );

  function restoreBtn() {
    var prog = document.getElementById(uid);
    if (prog) prog.remove();
    btn.style.display = "";
    btn.disabled = false;
    btn.textContent = "Download";
  }

  try {
    // 1. Start the download task
    var resp = await fetch(API_BASE + "/api/download-start", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ url: currentUrl, itag: itag, mode: mode, output_dir: outputDir }),
    });

    if (!resp.ok) {
      var errData = await resp.json();
      throw new Error(errData.detail || "Download failed");
    }

    var taskId = (await resp.json()).task_id;

    // 2. Track progress via SSE
    var result = await trackDownloadProgress(taskId, uid, mode);

    // 3. Success — optionally import into Premiere
    if (importToPremiere) {
      var textEl = document.getElementById(uid + "-text");
      if (textEl) textEl.textContent = "Importing...";
      importFileToPremiere(result.file_path, binName, function (importResult) {
        if (importResult === "OK") {
          showSuccess("Downloaded & imported: " + result.filename);
        } else {
          showSuccess("Downloaded: " + result.filename);
          showError("Premiere import failed: " + importResult);
        }
        restoreBtn();
      });
    } else {
      showSuccess("Downloaded: " + result.filename);
      restoreBtn();
    }

  } catch (err) {
    showError("Download error: " + err.message);
    restoreBtn();
  }
}


function trackDownloadProgress(taskId, uid, dlMode) {
  return new Promise(function (resolve, reject) {
    var source = new EventSource(API_BASE + "/api/download-progress/" + taskId);

    source.onmessage = function (event) {
      var data = JSON.parse(event.data);

      var fill = document.getElementById(uid + "-fill");
      var text = document.getElementById(uid + "-text");

      if (fill && data.percent !== undefined) {
        fill.style.width = data.percent + "%";
      }

      if (text) {
        var label = stageLabel(data.stage, dlMode);
        if (data.percent > 0 && data.stage !== "complete") {
          text.textContent = data.percent + "% \u2014 " + label;
        } else {
          text.textContent = label;
        }
      }

      if (data.error) {
        source.close();
        reject(new Error(data.error));
        return;
      }

      if (data.stage === "complete" && data.result) {
        source.close();
        resolve(data.result);
      }
    };

    source.onerror = function () {
      source.close();
      reject(new Error("Lost connection to server"));
    };
  });
}


function stageLabel(stage, dlMode) {
  switch (stage) {
    case "starting":          return "Starting...";
    case "downloading":       return dlMode === "audio" ? "Downloading audio..." : "Downloading video...";
    case "downloading_audio": return "Downloading audio track...";
    case "converting":        return "Converting to MP3...";
    case "merging":           return "Merging audio & video...";
    case "complete":          return "Complete!";
    default:                  return "Processing...";
  }
}


// ── Premiere Pro Integration ─────────────────────────────────────────────────

function importFileToPremiere(filePath, binName, callback) {
  var jsx = "importFileToProject(" +
    JSON.stringify(filePath) + ", " +
    JSON.stringify(binName || "") +
    ")";

  csInterface.evalScript(jsx, function (result) {
    if (typeof callback === "function") {
      callback(result);
    }
  });
}
