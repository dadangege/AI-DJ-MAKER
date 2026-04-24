import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";

import { projectRoot } from "./config.mjs";

const APP_SUPPORT_DIR = path.join(os.homedir(), "Library", "Application Support", "MiniMax TTS Studio");
const COOKIE_PATH = path.join(APP_SUPPORT_DIR, "netease-cookie.txt");
const DEFAULT_BASE_URL = "http://127.0.0.1:5000";

export class NeteaseServiceManager {
  constructor({
    repoDir = path.join(projectRoot, "vendor", "Netease_url"),
    cookiePath = COOKIE_PATH,
    setupScript = path.join(projectRoot, "script", "setup_netease_url.sh"),
    baseUrl = process.env.NETEASE_URL_BASE_URL || DEFAULT_BASE_URL
  } = {}) {
    this.repoDir = repoDir;
    this.cookiePath = cookiePath;
    this.setupScript = setupScript;
    this.baseUrl = baseUrl.replace(/\/$/, "");
    this.process = null;
    this.externalRunning = false;
    this.loginSession = null;
    this.logs = [];
  }

  get status() {
    return {
      installed: fs.existsSync(path.join(this.repoDir, "main.py")),
      running: Boolean((this.process && !this.process.killed) || this.externalRunning),
      baseUrl: this.baseUrl,
      repoDir: this.repoDir,
      setupScript: this.setupScript,
      cookiePath: this.cookiePath,
      hasCookie: fs.existsSync(this.cookiePath) && fs.readFileSync(this.cookiePath, "utf8").trim().length > 0,
      login: this.publicLoginSession(),
      logs: this.logs.slice(-20)
    };
  }

  saveCookie(cookie) {
    fs.mkdirSync(path.dirname(this.cookiePath), { recursive: true });
    fs.writeFileSync(this.cookiePath, `${String(cookie || "").trim()}\n`, { mode: 0o600 });
    try {
      fs.chmodSync(this.cookiePath, 0o600);
    } catch {
      // Best effort for filesystems without chmod.
    }
    this.syncCookieToVendor();
  }

  async install() {
    if (!fs.existsSync(this.setupScript)) {
      throw new Error(`缺少 Netease_url 安装脚本：${this.setupScript}`);
    }

    this.addLog("开始安装/更新 Netease_url。");
    await runCommand(this.setupScript, [], {
      cwd: projectRoot,
      onLog: (message) => this.addLog(message)
    });
    this.syncCookieToVendor();
    this.addLog("Netease_url 安装/更新完成。");
    return this.status;
  }

  syncCookieToVendor() {
    if (!fs.existsSync(this.cookiePath) || !fs.existsSync(this.repoDir)) return;
    const cookie = fs.readFileSync(this.cookiePath, "utf8");
    fs.writeFileSync(path.join(this.repoDir, "cookie.txt"), cookie, { mode: 0o600 });
  }

  async start() {
    if (!fs.existsSync(path.join(this.repoDir, "main.py"))) {
      throw new Error("Netease_url 未安装。请先运行：npm run netease-url:setup");
    }

    if (this.process && !this.process.killed) {
      return this.status;
    }

    const existing = await this.health();
    if (existing.ok) {
      this.addLog("检测到 Netease_url 服务已在运行。");
      this.externalRunning = true;
      return {
        ...this.status,
        running: true
      };
    }

    this.syncCookieToVendor();
    const python = findPython(this.repoDir);
    const child = spawn(python, ["main.py"], {
      cwd: this.repoDir,
      env: {
        ...process.env,
        PYTHONUNBUFFERED: "1"
      },
      stdio: ["ignore", "pipe", "pipe"]
    });

    this.process = child;
    child.stdout.on("data", (chunk) => this.addLog(chunk.toString().trim()));
    child.stderr.on("data", (chunk) => this.addLog(chunk.toString().trim()));
    child.on("exit", (code, signal) => {
      this.addLog(`Netease_url exited: code=${code} signal=${signal || ""}`);
      if (this.process === child) this.process = null;
    });

    await sleep(900);
    return this.status;
  }

  stop() {
    if (this.process && !this.process.killed) {
      this.process.kill("SIGTERM");
    }
    this.process = null;
    this.externalRunning = false;
    return this.status;
  }

  async health() {
    try {
      const response = await fetch(`${this.baseUrl}/health`, { method: "GET" });
      return {
        ok: response.ok || response.status < 500,
        status: response.status,
        ...this.status
      };
    } catch (error) {
      return {
        ok: false,
        error: error.message,
        ...this.status
      };
    }
  }

  async playlist(id) {
    this.syncCookieToVendor();
    const payload = await this.postJson("/playlist", { id: String(id || "").trim() });
    const tracks = normalizeTracks(payload);
    return {
      raw: payload,
      tracks
    };
  }

  async userPlaylists() {
    const cookies = this.readCookieMap();
    if (!cookies.MUSIC_U) {
      throw new Error("还没有登录网易云，请先扫码登录。");
    }

    const profile = await this.fetchNeteaseJson("https://music.163.com/api/nuser/account/get", cookies);
    const userId = profile?.profile?.userId || profile?.account?.id;
    if (!userId) {
      throw new Error("没有从网易云账号信息里拿到 userId。");
    }

    const payload = await this.fetchNeteaseJson(`https://music.163.com/api/user/playlist/?offset=0&limit=1001&uid=${encodeURIComponent(userId)}`, cookies);
    const playlists = (payload.playlist || []).map((playlist) => ({
      id: String(playlist.id || ""),
      name: String(playlist.name || ""),
      trackCount: Number(playlist.trackCount || 0),
      creator: playlist.creator?.nickname || "",
      coverImgUrl: playlist.coverImgUrl || ""
    })).filter((playlist) => playlist.id && playlist.name);

    return {
      userId: String(userId),
      nickname: profile?.profile?.nickname || "",
      playlists
    };
  }

  async startQrLogin() {
    await this.ensureInstalled();
    const script = [
      "import json",
      "from music_api import QRLoginManager",
      "manager = QRLoginManager()",
      "key = manager.generate_qr_key()",
      "print(json.dumps({'key': key, 'url': 'https://music.163.com/login?codekey=' + key}, ensure_ascii=False))"
    ].join("\n");
    const output = await runCommand(findPython(this.repoDir), ["-c", script], {
      cwd: this.repoDir,
      onLog: (message) => this.addLog(message),
      collect: true
    });
    const parsed = parseJson(output.trim().split("\n").at(-1) || "{}");
    if (!parsed.key) throw new Error("生成网易云登录二维码失败。");
    this.loginSession = {
      key: parsed.key,
      url: parsed.url,
      status: "waiting",
      message: "等待扫码",
      cookie: "",
      createdAt: Date.now(),
      expiresAt: Date.now() + 3 * 60 * 1000
    };
    return this.publicLoginSession();
  }

  async checkQrLogin() {
    if (!this.loginSession?.key) {
      throw new Error("还没有二维码登录会话。");
    }

    if (this.loginSession.status === "success") {
      return this.publicLoginSession();
    }

    if (Date.now() > this.loginSession.expiresAt) {
      this.loginSession.status = "expired";
      this.loginSession.message = "二维码已过期，请重新生成。";
      return this.publicLoginSession();
    }

    const script = [
      "import json",
      "from music_api import QRLoginManager",
      `key = ${JSON.stringify(this.loginSession.key)}`,
      "manager = QRLoginManager()",
      "code, cookies = manager.check_qr_login(key)",
      "print(json.dumps({'code': code, 'cookies': cookies}, ensure_ascii=False))"
    ].join("\n");
    const output = await runCommand(findPython(this.repoDir), ["-c", script], {
      cwd: this.repoDir,
      onLog: (message) => this.addLog(message),
      collect: true
    });
    const result = parseJson(output.trim().split("\n").at(-1) || "{}");
    const code = Number(result.code);

    if (code === 803) {
      const musicU = result.cookies?.MUSIC_U;
      if (!musicU) throw new Error("扫码成功但没有拿到 MUSIC_U。");
      const cookie = `MUSIC_U=${musicU};os=pc;appver=8.9.70;`;
      this.saveCookie(cookie);
      this.loginSession.status = "success";
      this.loginSession.message = "登录成功";
      this.loginSession.cookie = cookie;
      return this.publicLoginSession();
    }

    if (code === 802) {
      this.loginSession.status = "scanned";
      this.loginSession.message = "已扫码，请在手机上确认登录。";
      return this.publicLoginSession();
    }

    if (code === 801) {
      this.loginSession.status = "waiting";
      this.loginSession.message = "等待扫码。";
      return this.publicLoginSession();
    }

    if (code === 800) {
      this.loginSession.status = "expired";
      this.loginSession.message = "二维码已过期，请重新生成。";
      return this.publicLoginSession();
    }

    this.loginSession.status = "error";
    this.loginSession.message = `登录失败，状态码 ${code || "unknown"}`;
    return this.publicLoginSession();
  }

  async ensureInstalled() {
    if (!this.status.installed) {
      await this.install();
    }
  }

  async downloadTrack(track, {
    quality = "lossless",
    cacheDir = path.join(projectRoot, "output", "ai-dj", "music-cache")
  } = {}) {
    const id = track.id || track.songId;
    if (!id) throw new Error(`歌曲缺少 id：${track.title || "未知歌曲"}`);

    fs.mkdirSync(cacheDir, { recursive: true });
    const safeQuality = sanitizeFilePart(quality || "lossless");
    const baseName = `${sanitizeFilePart(String(id))}-${safeQuality}`;
    const existing = findExistingAudio(cacheDir, baseName);
    if (existing) return existing;

    const download = await this.postMaybeBinary("/download", { id: String(id), quality, format: "json" });
    const savedFromDownload = await saveDownloadResponse(download, cacheDir, baseName);
    if (savedFromDownload) return savedFromDownload;

    const song = await this.postJson("/song", { id: String(id), level: quality, type: "url" });
    const audioUrl = findFirstUrl(song);
    if (!audioUrl) {
      throw new Error(`没有拿到歌曲音频地址：${track.artist || "未知歌手"} - ${track.title || id}`);
    }

    return downloadAudioUrl(audioUrl, cacheDir, baseName);
  }

  async postJson(pathName, payload) {
    const response = await fetch(`${this.baseUrl}${pathName}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
    const text = await response.text();
    const json = parseJson(text);
    if (!response.ok) {
      throw new Error(`Netease_url ${pathName} failed: HTTP ${response.status} ${text}`);
    }
    return json;
  }

  async postMaybeBinary(pathName, payload) {
    const response = await fetch(`${this.baseUrl}${pathName}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
    const contentType = response.headers.get("content-type") || "";
    const buffer = Buffer.from(await response.arrayBuffer());
    if (!response.ok) {
      throw new Error(`Netease_url ${pathName} failed: HTTP ${response.status} ${buffer.toString("utf8")}`);
    }

    if (/audio|octet-stream/i.test(contentType)) {
      return { type: "binary", contentType, buffer };
    }

    const text = buffer.toString("utf8");
    return { type: "json", json: parseJson(text) };
  }

  readCookieMap() {
    if (!fs.existsSync(this.cookiePath)) return {};
    return parseCookieString(fs.readFileSync(this.cookiePath, "utf8"));
  }

  async fetchNeteaseJson(url, cookies = {}) {
    const response = await fetch(url, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/121.0.0.0 Safari/537.36",
        "Referer": "https://music.163.com/",
        "Cookie": formatCookieHeader({
          os: "pc",
          appver: "8.9.70",
          ...cookies
        })
      }
    });
    const text = await response.text();
    const json = parseJson(text);
    if (!response.ok) {
      throw new Error(`网易云请求失败：HTTP ${response.status} ${text.slice(0, 120)}`);
    }
    return json;
  }

  publicLoginSession() {
    if (!this.loginSession) return null;
    return {
      url: this.loginSession.url,
      status: this.loginSession.status,
      message: this.loginSession.message,
      createdAt: this.loginSession.createdAt,
      expiresAt: this.loginSession.expiresAt,
      hasCookie: Boolean(this.loginSession.cookie)
    };
  }

  addLog(message) {
    if (!message) return;
    this.logs.push({
      time: new Date().toISOString(),
      message: redactSensitive(message)
    });
    this.logs = this.logs.slice(-100);
  }
}

export function getNeteaseCookiePath() {
  return COOKIE_PATH;
}

function findPython(repoDir) {
  const venvPython = path.join(repoDir, ".venv", "bin", "python");
  if (fs.existsSync(venvPython)) return venvPython;
  return process.env.PYTHON || "python3";
}

function runCommand(command, args, { cwd, onLog }) {
  return new Promise((resolve, reject) => {
    let stdout = "";
    let stderr = "";
    const child = spawn(command, args, {
      cwd,
      stdio: ["ignore", "pipe", "pipe"]
    });
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
      onLog?.(chunk.toString().trim());
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
      onLog?.(chunk.toString().trim());
    });
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) {
        resolve(stdout);
        return;
      }
      reject(new Error(`${path.basename(command)} exited with code ${code}: ${stderr || stdout}`));
    });
  });
}

function normalizeTracks(payload) {
  const candidates = [
    payload?.tracks,
    payload?.songs,
    payload?.playlist?.tracks,
    payload?.data?.playlist?.tracks,
    payload?.data?.tracks,
    payload?.data?.songs,
    payload?.result?.tracks,
    payload?.result?.songs,
    payload?.data
  ];
  const array = candidates.find(Array.isArray) || (Array.isArray(payload) ? payload : []);
  return array.map(normalizeTrack).filter((track) => track.id && track.title);
}

function normalizeTrack(item) {
  const artists = item.ar || item.artists || item.artist || item.singer || [];
  const artist = Array.isArray(artists)
    ? artists.map((entry) => entry?.name || entry).filter(Boolean).join(" / ")
    : String(artists?.name || artists || "");
  const album = item.al?.name || item.album?.name || item.album || "";
  const durationMs = Number(item.dt || item.duration || item.time || item.playTime);
  return {
    id: String(item.id || item.songId || item.song_id || ""),
    title: String(item.name || item.title || item.songName || ""),
    artist,
    album: String(album || ""),
    duration: Number.isFinite(durationMs) && durationMs > 1000 ? durationMs / 1000 : Number(item.durationSeconds || 0),
    source: "netease"
  };
}

async function saveDownloadResponse(response, cacheDir, baseName) {
  if (response.type === "binary") {
    const ext = extensionForContentType(response.contentType) || "mp3";
    const outPath = path.join(cacheDir, `${baseName}.${ext}`);
    fs.writeFileSync(outPath, response.buffer);
    return outPath;
  }

  const json = response.json;
  const localPath = findFirstLocalPath(json);
  if (localPath && fs.existsSync(localPath)) {
    const ext = path.extname(localPath) || ".mp3";
    const outPath = path.join(cacheDir, `${baseName}${ext}`);
    fs.copyFileSync(localPath, outPath);
    return outPath;
  }

  const audioUrl = findFirstUrl(json);
  if (audioUrl) {
    return downloadAudioUrl(audioUrl, cacheDir, baseName);
  }

  return "";
}

async function downloadAudioUrl(url, cacheDir, baseName) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`下载音频失败：HTTP ${response.status}`);
  const contentType = response.headers.get("content-type") || "";
  const ext = extensionForContentType(contentType) || extensionFromUrl(url) || "mp3";
  const outPath = path.join(cacheDir, `${baseName}.${ext}`);
  const buffer = Buffer.from(await response.arrayBuffer());
  fs.writeFileSync(outPath, buffer);
  return outPath;
}

function findExistingAudio(cacheDir, baseName) {
  for (const ext of ["mp3", "flac", "m4a", "wav", "aac"]) {
    const filePath = path.join(cacheDir, `${baseName}.${ext}`);
    if (fs.existsSync(filePath)) return filePath;
  }
  return "";
}

function findFirstUrl(value) {
  if (!value) return "";
  if (typeof value === "string" && /^https?:\/\//i.test(value)) return value;
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findFirstUrl(item);
      if (found) return found;
    }
    return "";
  }
  if (typeof value === "object") {
    for (const key of ["url", "download_url", "downloadUrl", "musicUrl", "audio", "data"]) {
      const found = findFirstUrl(value[key]);
      if (found) return found;
    }
    for (const item of Object.values(value)) {
      const found = findFirstUrl(item);
      if (found) return found;
    }
  }
  return "";
}

function findFirstLocalPath(value) {
  if (!value) return "";
  if (typeof value === "string" && (value.startsWith("/") || value.startsWith("."))) return path.resolve(value);
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findFirstLocalPath(item);
      if (found) return found;
    }
  }
  if (typeof value === "object") {
    for (const key of ["path", "file", "file_path", "filePath", "downloadPath"]) {
      const found = findFirstLocalPath(value[key]);
      if (found) return found;
    }
  }
  return "";
}

function extensionForContentType(contentType) {
  if (/flac/i.test(contentType)) return "flac";
  if (/wav/i.test(contentType)) return "wav";
  if (/mp4|m4a/i.test(contentType)) return "m4a";
  if (/mpeg|mp3/i.test(contentType)) return "mp3";
  return "";
}

function extensionFromUrl(url) {
  const clean = String(url).split("?")[0];
  const ext = path.extname(clean).replace(".", "").toLowerCase();
  return ext || "";
}

function sanitizeFilePart(value) {
  return String(value || "unknown").replace(/[^a-zA-Z0-9._-]+/g, "_").slice(0, 80);
}

function parseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`Netease_url 返回了非 JSON 内容：${String(text).slice(0, 200)}`);
  }
}

function parseCookieString(cookieString) {
  const cookies = {};
  for (const pair of String(cookieString || "").split(";")) {
    const trimmed = pair.trim();
    if (!trimmed || !trimmed.includes("=")) continue;
    const [key, ...rest] = trimmed.split("=");
    const value = rest.join("=");
    if (key && value) cookies[key] = value;
  }
  return cookies;
}

function formatCookieHeader(cookies) {
  return Object.entries(cookies)
    .filter(([, value]) => value !== undefined && value !== null && value !== "")
    .map(([key, value]) => `${key}=${value}`)
    .join("; ");
}

function redactSensitive(value) {
  return String(value)
    .replace(/MUSIC_U=([^;"\s]+)/g, "MUSIC_U=[redacted]")
    .replace(/"MUSIC_U"\s*:\s*"[^"]+"/g, '"MUSIC_U":"[redacted]"');
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
