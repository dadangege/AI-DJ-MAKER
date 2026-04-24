import path from "node:path";

import { getEffectiveApiConfig } from "../app-settings.mjs";
import { createMiniMaxClient, writeAudioFromMiniMaxResponse } from "../minimax-client.mjs";

export async function synthesizeDjVoice(script, config) {
  const effective = getEffectiveApiConfig({
    ttsModel: config.ttsModel,
    voiceId: config.voiceId
  });
  const format = config.audioFormat || "mp3";
  const outPath = path.join(config.outputDir, `tts-${new Date().toISOString().replace(/[:.]/g, "-")}.${format}`);

  const payload = {
    model: effective.ttsModel,
    text: script,
    stream: false,
    language_boost: "Chinese",
    output_format: "hex",
    voice_setting: {
      voice_id: effective.voiceId,
      speed: config.ttsSpeed,
      vol: config.ttsVol,
      pitch: config.ttsPitch
    },
    audio_setting: {
      sample_rate: config.sampleRate,
      bitrate: config.bitrate,
      format,
      channel: 1
    },
    latex_read: false,
    english_normalization: true,
    subtitle_enable: false
  };

  const client = createMiniMaxClient();
  const result = await client.textToAudio(payload);
  const bytes = await writeAudioFromMiniMaxResponse(result, outPath);

  return {
    path: outPath,
    bytes,
    durationMs: result.extra_info?.audio_length || null
  };
}
