import { spawn } from "node:child_process";

export class DuckingController {
  constructor({
    duckVolume = 22,
    fadeSteps = 4,
    fadeStepDelayMs = 70
  } = {}) {
    this.duckVolume = duckVolume;
    this.fadeSteps = fadeSteps;
    this.fadeStepDelayMs = fadeStepDelayMs;
    this.activeSession = null;
  }

  get isActive() {
    return Boolean(this.activeSession);
  }

  async begin(state, { logger = () => {} } = {}) {
    if (this.activeSession) {
      return this.activeSession;
    }

    const strategy = detectStrategy(state?.sourceApp || "");
    if (!strategy) {
      logger("warn", `Ducking unavailable for source app: ${state?.sourceApp || "unknown"}`);
      return null;
    }

    const session = {
      strategy,
      sourceApp: state?.sourceApp || "",
      previousVolume: null,
      paused: false
    };

    try {
      if (strategy.type === "volume") {
        const currentVolume = await getAppVolume(strategy.appName);
        session.previousVolume = currentVolume;
        const targetVolume = clampVolume(this.duckVolume);
        if (Number.isFinite(currentVolume)) {
          await fadeAppVolume(strategy.appName, currentVolume, targetVolume, this.fadeSteps, this.fadeStepDelayMs);
          logger("info", `${strategy.appName} 音量已压低：${currentVolume} -> ${targetVolume}`);
        } else {
          await setAppVolume(strategy.appName, targetVolume);
          logger("info", `${strategy.appName} 音量已压低到 ${targetVolume}`);
        }
      } else if (strategy.type === "pause-resume") {
        await tellApp(strategy.appName, strategy.pauseCommand);
        session.paused = true;
        logger("info", `${strategy.appName} 已暂停，TTS 结束后恢复播放。`);
      }
    } catch (error) {
      logger("warn", `Ducking setup failed for ${strategy.appName}: ${error.message}`);
      return null;
    }

    this.activeSession = session;
    return session;
  }

  async end(logger = () => {}) {
    const session = this.activeSession;
    if (!session) return;

    this.activeSession = null;

    try {
      if (session.strategy.type === "volume" && Number.isFinite(session.previousVolume)) {
        await fadeAppVolume(session.strategy.appName, this.duckVolume, session.previousVolume, this.fadeSteps, this.fadeStepDelayMs);
        logger("info", `${session.strategy.appName} 音量已恢复到 ${session.previousVolume}`);
      } else if (session.strategy.type === "pause-resume" && session.paused) {
        await tellApp(session.strategy.appName, session.strategy.resumeCommand);
        logger("info", `${session.strategy.appName} 已恢复播放。`);
      }
    } catch (error) {
      logger("warn", `Ducking restore failed: ${error.message}`);
    }
  }

  async forceEnd(logger = () => {}) {
    await this.end(logger);
  }
}

function detectStrategy(sourceApp) {
  const id = String(sourceApp || "").toLowerCase();

  if (id.includes("com.apple.music") || id === "music") {
    return {
      type: "volume",
      appName: "Music"
    };
  }

  if (id.includes("com.spotify.client") || id === "spotify") {
    return {
      type: "volume",
      appName: "Spotify"
    };
  }

  if (id.includes("com.netease.163music") || id.includes("neteasemusic")) {
    return {
      type: "pause-resume",
      appName: "NeteaseMusic",
      pauseCommand: "pause",
      resumeCommand: "play"
    };
  }

  return null;
}

async function getAppVolume(appName) {
  const result = await runAppleScript(`tell application "${escapeAppleScriptString(appName)}" to get sound volume`);
  const number = Number(String(result).trim());
  return Number.isFinite(number) ? number : null;
}

async function setAppVolume(appName, volume) {
  await runAppleScript(`tell application "${escapeAppleScriptString(appName)}" to set sound volume to ${Math.round(clampVolume(volume))}`);
}

async function fadeAppVolume(appName, fromVolume, toVolume, steps, delayMs) {
  const from = clampVolume(fromVolume);
  const to = clampVolume(toVolume);
  const totalSteps = Math.max(1, Math.floor(steps));

  for (let index = 1; index <= totalSteps; index += 1) {
    const progress = index / totalSteps;
    const nextVolume = Math.round(from + ((to - from) * progress));
    await setAppVolume(appName, nextVolume);
    if (index < totalSteps) {
      await sleep(delayMs);
    }
  }
}

async function tellApp(appName, command) {
  await runAppleScript(`tell application "${escapeAppleScriptString(appName)}" to ${command}`);
}

async function runAppleScript(script) {
  return new Promise((resolve, reject) => {
    const child = spawn("osascript", ["-e", script], {
      stdio: ["ignore", "pipe", "pipe"]
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });

    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) {
        resolve(stdout.trim());
        return;
      }

      reject(new Error(stderr.trim() || `osascript exited with code ${code}`));
    });
  });
}

function escapeAppleScriptString(value) {
  return String(value).replaceAll("\\", "\\\\").replaceAll("\"", "\\\"");
}

function clampVolume(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return 0;
  return Math.min(100, Math.max(0, number));
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, ms)));
}
