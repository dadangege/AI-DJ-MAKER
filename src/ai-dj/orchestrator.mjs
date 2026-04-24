#!/usr/bin/env node
import fs from "node:fs";

import { loadDotEnv } from "../env.mjs";
import { projectRoot, config } from "./config.mjs";
import { createAiDjSession } from "./dj_session.mjs";

loadDotEnv(`${projectRoot}/.env`);

if (!fs.existsSync(config.listenerPath)) {
  console.error("Now Playing helper is missing.");
  console.error("Build it first: npm run ai-dj:build-listener");
  process.exit(1);
}

fs.mkdirSync(config.outputDir, { recursive: true });

const aiDj = createAiDjSession({ config });

console.log("AI DJ MVP started.");
console.log("Transition plan: pre_outro / gap_bridge.");
console.log("文案会提前生成，TTS 会在临近触发点时预合成。");
console.log("Waiting for system Now Playing updates...");

aiDj.start();

process.on("SIGINT", () => {
  console.log("\nStopping AI DJ MVP...");
  Promise.resolve(aiDj.stop()).finally(() => process.exit(0));
});
