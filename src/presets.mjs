export const PRESETS = {
  radio: {
    description: "温暖、沉稳、适合电台主播和长段旁白。",
    voiceId: "Chinese (Mandarin)_Gentle_Senior",
    speed: 0.92,
    vol: 1,
    pitch: -1,
    latexRead: false,
    englishNormalization: true
  },
  story: {
    description: "慢一点、更有留白，适合故事、情感播客和深夜节目。",
    voiceId: "Chinese (Mandarin)_Gentle_Senior",
    speed: 0.86,
    vol: 1,
    pitch: -2,
    latexRead: false,
    englishNormalization: true
  },
  news: {
    description: "清晰、稳健、信息密度更高，适合资讯栏目。",
    voiceId: "Chinese (Mandarin)_Gentle_Senior",
    speed: 1,
    vol: 1,
    pitch: 0,
    latexRead: false,
    englishNormalization: true
  }
};

export function getPreset(name = "radio") {
  return PRESETS[name] || PRESETS.radio;
}

export function listPresetNames() {
  return Object.keys(PRESETS);
}
