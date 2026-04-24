const DEFAULTS = {
  preOutroLeadSeconds: 15,
  introBridgeStartSeconds: 5,
  introBridgeEndSeconds: 14,
  gapBridgeGraceSeconds: 8,
  ttsPrefetchLeadSeconds: 8,
  duckVolume: 22,
  duckFadeSteps: 4,
  duckFadeStepDelayMs: 70,
  ttsPlaybackGain: 1.25
};

export function createTransitionAudioPolicy(overrides = {}) {
  return {
    preOutroLeadSeconds: numberOr(
      overrides.preOutroLeadSeconds ?? process.env.AI_DJ_PRE_OUTRO_LEAD_SECONDS,
      DEFAULTS.preOutroLeadSeconds
    ),
    introBridgeStartSeconds: numberOr(
      overrides.introBridgeStartSeconds ?? process.env.AI_DJ_INTRO_BRIDGE_START_SECONDS,
      DEFAULTS.introBridgeStartSeconds
    ),
    introBridgeEndSeconds: numberOr(
      overrides.introBridgeEndSeconds ?? process.env.AI_DJ_INTRO_BRIDGE_END_SECONDS,
      DEFAULTS.introBridgeEndSeconds
    ),
    gapBridgeGraceSeconds: numberOr(
      overrides.gapBridgeGraceSeconds ?? process.env.AI_DJ_GAP_BRIDGE_GRACE_SECONDS,
      DEFAULTS.gapBridgeGraceSeconds
    ),
    ttsPrefetchLeadSeconds: numberOr(
      overrides.ttsPrefetchLeadSeconds ?? process.env.AI_DJ_TTS_PREFETCH_SECONDS,
      DEFAULTS.ttsPrefetchLeadSeconds
    ),
    duckVolume: numberOr(
      overrides.duckVolume ?? process.env.AI_DJ_DUCK_VOLUME,
      DEFAULTS.duckVolume
    ),
    duckFadeSteps: numberOr(
      overrides.duckFadeSteps ?? process.env.AI_DJ_DUCK_FADE_STEPS,
      DEFAULTS.duckFadeSteps
    ),
    duckFadeStepDelayMs: numberOr(
      overrides.duckFadeStepDelayMs ?? process.env.AI_DJ_DUCK_FADE_STEP_DELAY_MS,
      DEFAULTS.duckFadeStepDelayMs
    ),
    ttsPlaybackGain: numberOr(
      overrides.ttsPlaybackGain ?? process.env.AI_DJ_TTS_PLAYBACK_GAIN,
      DEFAULTS.ttsPlaybackGain
    ),
    duckableApps: ["Music", "Spotify", "System Output"]
  };
}

function numberOr(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}
