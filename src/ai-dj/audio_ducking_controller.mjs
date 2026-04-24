import { spawn } from "node:child_process";

const SUPPORTED_APPS = new Map([
  ["com.apple.music", { label: "Music", appId: "com.apple.Music" }],
  ["music", { label: "Music", appId: "com.apple.Music" }],
  ["com.spotify.client", { label: "Spotify", appId: "com.spotify.client" }],
  ["spotify", { label: "Spotify", appId: "com.spotify.client" }]
]);

const SYSTEM_DUCKING_DISABLED_VALUES = new Set(["0", "false", "no", "off"]);

export class AudioDuckingController {
  constructor({
    duckVolume = 22,
    fadeSteps = 4,
    fadeStepDelayMs = 70,
    allowSystemDucking = true
  } = {}) {
    this.duckVolume = duckVolume;
    this.fadeSteps = fadeSteps;
    this.fadeStepDelayMs = fadeStepDelayMs;
    this.allowSystemDucking = allowSystemDucking && !SYSTEM_DUCKING_DISABLED_VALUES.has(String(process.env.AI_DJ_ALLOW_SYSTEM_DUCKING || "").toLowerCase());
    this.activeSession = null;
  }

  get isActive() {
    return Boolean(this.activeSession);
  }

  async begin(state, { logger = () => {} } = {}) {
    if (this.activeSession) {
      return this.activeSession;
    }

    const strategy = detectDuckingStrategy(state?.sourceApp || "", this.allowSystemDucking);
    if (!strategy) {
      logger("warn", `Ducking unavailable for source app: ${state?.sourceApp || "unknown"}`);
      return null;
    }

    const session = {
      strategy,
      previousVolume: null
    };

    try {
      const currentVolume = await getStrategyVolume(strategy);
      session.previousVolume = currentVolume;

      const targetVolume = clampVolume(this.duckVolume);
      if (Number.isFinite(currentVolume)) {
        await fadeStrategyVolume(strategy, currentVolume, targetVolume, this.fadeSteps, this.fadeStepDelayMs);
        logger("info", `${strategy.label} 音量已压低：${currentVolume} -> ${targetVolume}`);
      } else {
        await setStrategyVolume(strategy, targetVolume);
        logger("info", `${strategy.label} 音量已压低到 ${targetVolume}`);
      }
    } catch (error) {
      logger("warn", `Ducking setup failed for ${strategy.label}: ${error.message}`);
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
      if (Number.isFinite(session.previousVolume)) {
        await fadeStrategyVolume(session.strategy, this.duckVolume, session.previousVolume, this.fadeSteps, this.fadeStepDelayMs);
        logger("info", `${session.strategy.label} 音量已恢复到 ${session.previousVolume}`);
      }
    } catch (error) {
      logger("warn", `Ducking restore failed: ${error.message}`);
    }
  }

  async forceEnd(logger = () => {}) {
    await this.end(logger);
  }
}

export { AudioDuckingController as DuckingController };

function detectDuckingStrategy(sourceApp, allowSystemDucking) {
  const key = String(sourceApp || "").toLowerCase();
  const app = SUPPORTED_APPS.get(key);
  if (app) {
    return {
      type: "app-volume",
      ...app
    };
  }

  if (allowSystemDucking) {
    return {
      type: "system-output-volume",
      label: "系统输出"
    };
  }

  return null;
}

async function getStrategyVolume(strategy) {
  if (strategy.type === "app-volume") {
    return getAppVolume(strategy);
  }

  if (strategy.type === "system-output-volume") {
    return getSystemOutputVolume();
  }

  return null;
}

async function setStrategyVolume(strategy, volume) {
  if (strategy.type === "app-volume") {
    await setAppVolume(strategy, volume);
    return;
  }

  if (strategy.type === "system-output-volume") {
    await setSystemOutputVolume(volume);
  }
}

async function fadeStrategyVolume(strategy, fromVolume, toVolume, steps, delayMs) {
  const from = clampVolume(fromVolume);
  const to = clampVolume(toVolume);
  const totalSteps = Math.max(1, Math.floor(steps));

  for (let index = 1; index <= totalSteps; index += 1) {
    const progress = index / totalSteps;
    const nextVolume = Math.round(from + ((to - from) * progress));
    await setStrategyVolume(strategy, nextVolume);
    if (index < totalSteps) {
      await sleep(delayMs);
    }
  }
}

async function getAppVolume(strategy) {
  const result = await runAppleScript(`tell application id "${escapeAppleScriptString(strategy.appId)}" to get sound volume`);
  const number = Number(String(result).trim());
  return Number.isFinite(number) ? number : null;
}

async function setAppVolume(strategy, volume) {
  await runAppleScript(`tell application id "${escapeAppleScriptString(strategy.appId)}" to set sound volume to ${Math.round(clampVolume(volume))}`);
}

async function getSystemOutputVolume() {
  const result = await runAppleScript("output volume of (get volume settings)");
  const number = Number(String(result).trim());
  return Number.isFinite(number) ? number : null;
}

async function setSystemOutputVolume(volume) {
  await runAppleScript(`set volume output volume ${Math.round(clampVolume(volume))}`);
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
