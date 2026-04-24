#!/usr/bin/env node
import { parseArgs } from "./cli.mjs";
import { loadDotEnv } from "./env.mjs";
import { createMiniMaxClient } from "./minimax-client.mjs";

loadDotEnv();

const args = parseArgs(process.argv.slice(2));

if (args.help) {
  console.log(`
List MiniMax voices

Usage:
  npm run voices
  node src/list-voices.mjs
  npm run voices -- --type system
`);
  process.exit(0);
}

try {
  const client = createMiniMaxClient();
  const result = await client.listVoices({
    voiceType: args.type || "system"
  });

  const voices = [
    ...(result.system_voice || []),
    ...(result.voice_cloning || []),
    ...(result.voice_generation || []),
    ...(result.voice_list || []),
    ...(result.data?.voices || [])
  ];
  if (!Array.isArray(voices) || voices.length === 0) {
    console.log(JSON.stringify(result, null, 2));
    process.exit(0);
  }

  for (const voice of voices) {
    const voiceId = voice.voice_id || voice.voiceId || voice.id || "unknown";
    const name = voice.name || voice.display_name || "";
    const language = voice.language || voice.lang || "";
    console.log([voiceId, name, language].filter(Boolean).join(" | "));
  }
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
