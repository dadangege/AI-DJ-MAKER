import { EventEmitter } from "node:events";
import { spawn } from "node:child_process";
import fs from "node:fs";
import readline from "node:readline";

export class PlayerListener extends EventEmitter {
  constructor({ listenerPath, adapterScriptPath = "", adapterFrameworkPath = "", adapterTestClientPath = "" }) {
    super();
    this.listenerPath = listenerPath;
    this.adapterScriptPath = adapterScriptPath;
    this.adapterFrameworkPath = adapterFrameworkPath;
    this.adapterTestClientPath = adapterTestClientPath;
    this.listenerMode = "swift-helper";
    this.child = null;
    this.adapterState = {};
    this.adapterTick = null;
  }

  start() {
    if (this.child) return this;

    const command = this.buildCommand();
    this.listenerMode = command.mode;
    this.emit("stderr", `Now Playing listener mode: ${command.mode}`);

    this.child = spawn(command.bin, command.args, {
      stdio: ["ignore", "pipe", "pipe"]
    });

    const lines = readline.createInterface({
      input: this.child.stdout,
      crlfDelay: Infinity
    });

    if (this.listenerMode === "mediaremote-adapter") {
      this.adapterTick = setInterval(() => {
        if (!Object.keys(this.adapterState).length) return;
        const state = normalizeAdapterState(this.adapterState);
        if (state?.title) this.emit("state", state);
      }, 1000);
    }

    lines.on("line", (line) => {
      if (!line.trim()) return;
      try {
        const parsed = JSON.parse(line);
        const state = this.listenerMode === "mediaremote-adapter"
          ? this.normalizeAdapterLine(parsed)
          : normalizeState(parsed);
        if (state.error) {
          this.emit("error", new Error(state.message || state.error));
          return;
        }
        if (state) this.emit("state", state);
      } catch (error) {
        this.emit("error", new Error(`Failed to parse now-playing JSON: ${error.message}`));
      }
    });

    this.child.stderr.on("data", (chunk) => {
      const message = chunk.toString().trim();
      if (message) this.emit("stderr", message);
    });

    this.child.on("error", (error) => {
      this.emit("error", error);
    });

    this.child.on("exit", (code, signal) => {
      if (this.adapterTick) {
        clearInterval(this.adapterTick);
        this.adapterTick = null;
      }
      this.child = null;
      this.emit("exit", { code, signal });
    });

    return this;
  }

  buildCommand() {
    if (
      this.adapterScriptPath &&
      this.adapterFrameworkPath &&
      fs.existsSync(this.adapterScriptPath) &&
      fs.existsSync(this.adapterFrameworkPath)
    ) {
      const args = [
        this.adapterScriptPath,
        this.adapterFrameworkPath
      ];
      if (this.adapterTestClientPath && fs.existsSync(this.adapterTestClientPath)) {
        args.push(this.adapterTestClientPath);
      }
      args.push("stream", "--no-diff", "--debounce=100");
      return {
        mode: "mediaremote-adapter",
        bin: "/usr/bin/perl",
        args
      };
    }

    return {
      mode: "swift-helper",
      bin: this.listenerPath,
      args: []
    };
  }

  normalizeAdapterLine(raw) {
    const payload = raw?.payload && typeof raw.payload === "object"
      ? raw.payload
      : raw;

    if (!payload || typeof payload !== "object" || !Object.keys(payload).length) {
      this.adapterState = {};
      return normalizeState({
        state: "stopped",
        progressReliable: true,
        progressSource: "mediaremote-adapter"
      });
    }

    this.adapterState = {
      ...this.adapterState,
      ...payload
    };

    for (const [key, value] of Object.entries(this.adapterState)) {
      if (value === null) delete this.adapterState[key];
    }

    return normalizeAdapterState(this.adapterState);
  }

  stop() {
    if (this.adapterTick) {
      clearInterval(this.adapterTick);
      this.adapterTick = null;
    }
    if (this.child) {
      this.child.kill("SIGTERM");
      this.child = null;
    }
  }
}

export function createPlayerListener(options) {
  return new PlayerListener(options);
}

function normalizeState(raw) {
  const title = raw.title || raw.queueCurrentTitle || "";
  const artist = raw.artist || raw.queueCurrentArtist || "";
  const album = raw.album || raw.queueCurrentAlbum || "";

  return {
    state: raw.state || "stopped",
    title,
    artist,
    album,
    duration: numberOrNull(raw.duration),
    elapsed: numberOrNull(raw.elapsed),
    playbackRate: numberOrNull(raw.playbackRate),
    sourceApp: raw.sourceApp || "",
    trackId: hasTrackIdentity(raw) ? (raw.trackId || buildTrackId({ ...raw, title, artist, album })) : buildTrackId({ ...raw, title, artist, album }),
    progressReliable: raw.progressReliable !== false,
    progressSource: raw.progressSource || "system-now-playing",
    queueAvailable: Boolean(raw.queueAvailable),
    queueLocation: numberOrNull(raw.queueLocation),
    queueItemCount: numberOrNull(raw.queueItemCount),
    queueCurrentTitle: raw.queueCurrentTitle || "",
    queueCurrentArtist: raw.queueCurrentArtist || "",
    queueCurrentAlbum: raw.queueCurrentAlbum || "",
    queueCurrentIdentifier: raw.queueCurrentIdentifier || null,
    nextTrackAvailable: Boolean(raw.nextTrackAvailable),
    nextTitle: raw.nextTitle || "",
    nextArtist: raw.nextArtist || "",
    nextAlbum: raw.nextAlbum || "",
    nextIdentifier: raw.nextIdentifier || null,
    nextDuration: numberOrNull(raw.nextDuration),
    error: raw.error || "",
    message: raw.message || ""
  };
}

function normalizeAdapterState(raw) {
  const title = raw.title || "";
  const artist = raw.artist || "";
  const album = raw.album || "";
  const duration = secondsFromAdapter(raw.duration ?? raw.durationMicros);
  const elapsed = adapterElapsedSeconds(raw);
  const playbackRate = numberOrNull(raw.playbackRate);
  const playing = raw.playing === true || playbackRate > 0.01;

  return normalizeState({
    state: playing ? "playing" : (title ? "paused" : "stopped"),
    title,
    artist,
    album,
    duration,
    elapsed,
    playbackRate: playbackRate ?? (playing ? 1 : 0),
    sourceApp: raw.bundleIdentifier || raw.parentApplicationBundleIdentifier || "",
    trackId: raw.uniqueIdentifier || raw.contentItemIdentifier || buildTrackId({ artist, title, album, duration }),
    queueIndex: raw.queueIndex,
    totalQueueCount: raw.totalQueueCount,
    progressReliable: Boolean(title),
    progressSource: "mediaremote-adapter"
  });
}

function adapterElapsedSeconds(raw) {
  if (raw.elapsedTimeNow !== undefined || raw.elapsedTimeNowMicros !== undefined) {
    return secondsFromAdapter(raw.elapsedTimeNow ?? raw.elapsedTimeNowMicros);
  }

  const elapsed = secondsFromAdapter(raw.elapsedTime ?? raw.elapsedTimeMicros);
  const timestampMs = timestampMillis(raw.timestamp ?? raw.timestampEpochMicros);
  const playbackRate = numberOrNull(raw.playbackRate);
  if (Number.isFinite(elapsed) && Number.isFinite(timestampMs) && playbackRate > 0.01 && raw.playing === true) {
    return elapsed + ((Date.now() - timestampMs) / 1000) * playbackRate;
  }
  return elapsed;
}

function secondsFromAdapter(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return null;
  return number > 100_000 ? number / 1_000_000 : number;
}

function timestampMillis(value) {
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    if (Number.isFinite(parsed)) return parsed;
  }

  const number = Number(value);
  if (!Number.isFinite(number)) return null;
  if (number > 10_000_000_000_000) return number / 1000;
  if (number > 10_000_000_000) return number;
  return number * 1000;
}

function hasTrackIdentity(raw) {
  return Boolean(String(raw.title || raw.artist || raw.album || "").trim());
}

function numberOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function buildTrackId(raw) {
  return [
    raw.artist || "",
    raw.title || "",
    raw.album || "",
    raw.duration || ""
  ].join("|");
}
