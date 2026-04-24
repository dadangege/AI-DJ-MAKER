import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const APP_SUPPORT_DIR = path.join(os.homedir(), "Library", "Application Support", "MiniMax TTS Studio");
const SETTINGS_PATH = path.join(APP_SUPPORT_DIR, "settings.json");

const DEFAULTS = {
  baseUrl: "https://api.minimaxi.com/v1",
  textModel: "MiniMax-M2.7-highspeed",
  ttsModel: "speech-2.8-hd",
  voiceId: "Chinese (Mandarin)_Gentle_Senior"
};

export function getSettingsPath() {
  return SETTINGS_PATH;
}

export function loadAppSettings() {
  try {
    if (!fs.existsSync(SETTINGS_PATH)) {
      return {};
    }
    const parsed = JSON.parse(fs.readFileSync(SETTINGS_PATH, "utf8"));
    return sanitizeSettings(parsed, { includeApiKey: true });
  } catch {
    return {};
  }
}

export function saveAppSettings(input = {}) {
  const current = loadAppSettings();
  const next = sanitizeSettings({
    ...current,
    ...input
  }, { includeApiKey: true });

  if (Object.prototype.hasOwnProperty.call(input, "apiKey") && !String(input.apiKey || "").trim()) {
    delete next.apiKey;
  }

  fs.mkdirSync(APP_SUPPORT_DIR, { recursive: true });
  fs.writeFileSync(SETTINGS_PATH, `${JSON.stringify(next, null, 2)}\n`, { mode: 0o600 });
  try {
    fs.chmodSync(SETTINGS_PATH, 0o600);
  } catch {
    // Best effort on filesystems that do not support chmod.
  }
  return next;
}

export function getEffectiveApiConfig(overrides = {}) {
  const settings = loadAppSettings();
  const apiKey = firstNonEmpty(
    overrides.apiKey,
    settings.apiKey,
    process.env.OPENAI_API_KEY,
    process.env.MINIMAX_API_KEY
  );
  const baseUrl = firstNonEmpty(
    overrides.baseUrl,
    settings.baseUrl,
    process.env.OPENAI_BASE_URL,
    process.env.MINIMAX_BASE_URL,
    DEFAULTS.baseUrl
  );
  const textModel = firstNonEmpty(
    overrides.textModel,
    settings.textModel,
    process.env.OPENAI_MODEL,
    process.env.AI_DJ_TEXT_MODEL,
    DEFAULTS.textModel
  );
  const ttsModel = firstNonEmpty(
    overrides.ttsModel,
    settings.ttsModel,
    process.env.AI_DJ_TTS_MODEL,
    DEFAULTS.ttsModel
  );
  const voiceId = firstNonEmpty(
    overrides.voiceId,
    settings.voiceId,
    process.env.AI_DJ_VOICE_ID,
    DEFAULTS.voiceId
  );

  return {
    apiKey,
    baseUrl,
    textModel,
    ttsModel,
    voiceId,
    hasApiKey: Boolean(apiKey)
  };
}

export function publicSettingsPayload() {
  const effective = getEffectiveApiConfig();
  const saved = loadAppSettings();
  return {
    baseUrl: effective.baseUrl,
    textModel: effective.textModel,
    ttsModel: effective.ttsModel,
    voiceId: effective.voiceId,
    hasApiKey: effective.hasApiKey,
    maskedApiKey: effective.apiKey ? maskApiKey(effective.apiKey) : "",
    settingsPath: SETTINGS_PATH,
    usingSavedKey: Boolean(saved.apiKey)
  };
}

function sanitizeSettings(input = {}, { includeApiKey = false } = {}) {
  const output = {};
  for (const key of ["baseUrl", "textModel", "ttsModel", "voiceId"]) {
    const value = String(input[key] || "").trim();
    if (value) output[key] = value;
  }
  if (includeApiKey && Object.prototype.hasOwnProperty.call(input, "apiKey")) {
    const value = String(input.apiKey || "").trim();
    if (value) output.apiKey = value;
  }
  return output;
}

function firstNonEmpty(...values) {
  for (const value of values) {
    const string = String(value || "").trim();
    if (string) return string;
  }
  return "";
}

function maskApiKey(apiKey) {
  if (apiKey.length <= 10) return "已保存";
  return `${apiKey.slice(0, 6)}...${apiKey.slice(-4)}`;
}
