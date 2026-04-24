#!/usr/bin/env node
import path from "node:path";

import { parseArgs, readTextArg, numberArg } from "./cli.mjs";
import { loadDotEnv } from "./env.mjs";
import { createMiniMaxClient, writeAudioFromMiniMaxResponse } from "./minimax-client.mjs";
import { getPreset, listPresetNames } from "./presets.mjs";

loadDotEnv();

const args = parseArgs(process.argv.slice(2));

if (args.help) {
  printHelp();
  process.exit(0);
}

const text = readTextArg(args).trim();
if (!text) {
  console.error("Missing text. Use --text, --file, or pipe text through stdin.");
  printHelp();
  process.exit(1);
}

const preset = getPreset(args.preset);
const format = args.format || "mp3";
const outPath = args.out || path.join("output", `tts-${Date.now()}.${format}`);
const voiceModify = buildVoiceModify(args);

const payload = {
  model: args.model || "speech-2.8-hd",
  text,
  stream: false,
  language_boost: args.language || "Chinese",
  output_format: args.outputFormat || "hex",
  voice_setting: {
    voice_id: args.voice || preset.voiceId,
    speed: numberArg(args.speed, preset.speed),
    vol: numberArg(args.vol, preset.vol),
    pitch: numberArg(args.pitch, preset.pitch)
  },
  audio_setting: {
    sample_rate: numberArg(args.sampleRate, 32000),
    bitrate: numberArg(args.bitrate, 128000),
    format,
    channel: numberArg(args.channel, 1)
  },
  pronunciation_dict: {
    tone: args.tone ? String(args.tone).split(",").map((item) => item.trim()).filter(Boolean) : []
  },
  timbre_weights: args.timbreWeights || args.timberWeights ? parseTimbreWeights(args.timbreWeights || args.timberWeights) : undefined,
  voice_modify: voiceModify,
  subtitle_enable: Boolean(args.subtitle)
};

if (args.latexRead !== undefined) {
  payload.latex_read = args.latexRead !== "false";
} else {
  payload.latex_read = preset.latexRead;
}

if (args.englishNormalization !== undefined) {
  payload.english_normalization = args.englishNormalization !== "false";
} else {
  payload.english_normalization = preset.englishNormalization;
}

for (const key of Object.keys(payload)) {
  if (payload[key] === undefined) delete payload[key];
}

try {
  const client = createMiniMaxClient();
  const result = await client.textToAudio(payload);
  const byteLength = await writeAudioFromMiniMaxResponse(result, outPath);

  console.log(`Audio written: ${path.resolve(outPath)} (${byteLength} bytes)`);
  if (result.extra_info) {
    console.log(`Duration: ${result.extra_info.audio_length || "unknown"} ms`);
  }
} catch (error) {
  console.error(error.message);
  process.exit(1);
}

function buildVoiceModify(cliArgs) {
  const modify = {};

  if (cliArgs.modifyPitch !== undefined) modify.pitch = numberArg(cliArgs.modifyPitch, 0);
  if (cliArgs.intensity !== undefined) modify.intensity = numberArg(cliArgs.intensity, 0);
  if (cliArgs.timbre !== undefined) modify.timbre = numberArg(cliArgs.timbre, 0);
  if (cliArgs.effects) modify.sound_effects = String(cliArgs.effects).trim();

  return Object.keys(modify).length > 0 ? modify : undefined;
}

function parseTimbreWeights(value) {
  return String(value).split(",").map((item) => {
    const [voiceId, weight] = item.split(":");
    return {
      voice_id: voiceId,
      weight: Number(weight)
    };
  }).filter((item) => item.voice_id && Number.isFinite(item.weight));
}

function printHelp() {
  console.log(`
MiniMax TTS CLI

Usage:
  npm run tts -- --text "欢迎收听今晚的节目" --out output/radio.mp3
  npm run tts -- --file examples/radio-script.txt --preset story --out output/story.mp3
  node src/minimax-tts.mjs --file examples/radio-script.txt --preset story --out output/story.mp3
  echo "欢迎收听" | npm run tts -- --out output/pipe.mp3

Options:
  --preset radio|story|news       Built-in voice tuning preset. Defaults to radio.
  --model speech-2.8-hd           MiniMax T2A model. Use speech-2.8-hd for high quality.
  --voice <voice_id>              Voice ID. Defaults to Chinese (Mandarin)_Gentle_Senior.
  --speed <0.5-2>                 Speaking speed.
  --pitch <-12-12>                Pitch adjustment.
  --vol <0-10>                    Volume.
  --language Chinese|auto|...     Language boost. Defaults to Chinese.
  --format mp3|wav|flac           Output audio format. Defaults to mp3.
  --sample-rate <number>          Defaults to 32000.
  --bitrate <number>              Defaults to 128000.
  --channel 1|2                   Defaults to mono.
  --effects <effect>              Optional MiniMax sound effect, e.g. spacious_echo.
  --modify-pitch <number>         Optional voice_modify pitch effect.
  --intensity <number>            Optional voice_modify intensity effect.
  --timbre <number>               Optional voice_modify timbre effect.
  --timbre-weights id:weight,...  Optional voice blending weights.
  --tone "字/(zi4),..."            Optional pronunciation dictionary entries.
  --subtitle                      Ask MiniMax to include subtitle metadata.
  --help                          Show this help.

Emotional radio tip:
  Add MiniMax supported control tags in your script, such as <#0.8#>, (breath), (laughs), (sighs).
  The speech-2.8 family currently gives better control over pauses and interjections.
`);
}
