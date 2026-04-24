import path from "node:path";
import { fileURLToPath } from "node:url";

import { getEffectiveApiConfig } from "../app-settings.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const projectRoot = path.resolve(__dirname, "..", "..");
const apiConfig = getEffectiveApiConfig();

export const config = {
  projectRoot,
  listenerPath: path.join(projectRoot, "native", "now-playing-listener", "now-playing-listener"),
  mediaRemoteAdapterScript: process.env.MEDIAREMOTE_ADAPTER_SCRIPT || path.join(projectRoot, "vendor", "mediaremote-adapter", "bin", "mediaremote-adapter.pl"),
  mediaRemoteAdapterFramework: process.env.MEDIAREMOTE_ADAPTER_FRAMEWORK || path.join(projectRoot, "vendor", "mediaremote-adapter", "build", "MediaRemoteAdapter.framework"),
  mediaRemoteAdapterTestClient: process.env.MEDIAREMOTE_ADAPTER_TEST_CLIENT || path.join(projectRoot, "vendor", "mediaremote-adapter", "build", "MediaRemoteAdapterTestClient"),
  outputDir: path.join(projectRoot, "output", "ai-dj"),
  triggerAtSeconds: numberEnv("AI_DJ_TRIGGER_SECONDS", 12),
  preOutroLeadSeconds: numberEnv("AI_DJ_PRE_OUTRO_LEAD_SECONDS", 15),
  introBridgeStartSeconds: numberEnv("AI_DJ_INTRO_BRIDGE_START_SECONDS", 5),
  introBridgeEndSeconds: numberEnv("AI_DJ_INTRO_BRIDGE_END_SECONDS", 14),
  gapBridgeGraceSeconds: numberEnv("AI_DJ_GAP_BRIDGE_GRACE_SECONDS", 8),
  openingMinSeconds: numberEnv("AI_DJ_OPENING_MIN_SECONDS", 10),
  openingMaxSeconds: numberEnv("AI_DJ_OPENING_MAX_SECONDS", 20),
  openingRatio: numberEnv("AI_DJ_OPENING_RATIO", 0.08),
  middleMinDurationSeconds: numberEnv("AI_DJ_MIDDLE_MIN_DURATION_SECONDS", 60),
  endingBeforeSeconds: numberEnv("AI_DJ_ENDING_BEFORE_SECONDS", 15),
  ttsPrefetchLeadSeconds: numberEnv("AI_DJ_TTS_PREFETCH_SECONDS", 8),
  duckVolume: numberEnv("AI_DJ_DUCK_VOLUME", 22),
  duckFadeSteps: numberEnv("AI_DJ_DUCK_FADE_STEPS", 4),
  duckFadeStepDelayMs: numberEnv("AI_DJ_DUCK_FADE_STEP_DELAY_MS", 70),
  ttsPlaybackGain: numberEnv("AI_DJ_TTS_PLAYBACK_GAIN", 1.25),
  textModel: apiConfig.textModel,
  ttsModel: apiConfig.ttsModel,
  voiceId: apiConfig.voiceId,
  ttsSpeed: numberEnv("AI_DJ_TTS_SPEED", 0.92),
  ttsPitch: numberEnv("AI_DJ_TTS_PITCH", -1),
  ttsVol: numberEnv("AI_DJ_TTS_VOL", 2),
  audioFormat: process.env.AI_DJ_AUDIO_FORMAT || "mp3",
  sampleRate: numberEnv("AI_DJ_SAMPLE_RATE", 32000),
  bitrate: numberEnv("AI_DJ_BITRATE", 128000)
};

function numberEnv(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? value : fallback;
}
