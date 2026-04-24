#!/usr/bin/env node
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

import { createMiniMaxClient, writeAudioFromMiniMaxResponse } from "./minimax-client.mjs";
import { loadDotEnv } from "./env.mjs";
import { getEffectiveApiConfig, publicSettingsPayload, saveAppSettings } from "./app-settings.mjs";
import { getPreset, listPresetNames, PRESETS } from "./presets.mjs";
import { createAiDjSession } from "./ai-dj/dj_session.mjs";
import { createLocalDjSession } from "./ai-dj/local_dj_session.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(__dirname, "..");
const publicDir = path.join(projectRoot, "web");
const outputDir = path.join(projectRoot, "output", "mac-app");

loadDotEnv(path.join(projectRoot, ".env"));

const args = new Set(process.argv.slice(2));
const requestedPort = Number(process.env.MINIMAX_TTS_PORT || 0);
const aiDj = createAiDjSession();
const localDj = createLocalDjSession();

const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url || "/", `http://${request.headers.host || "localhost"}`);

    if (isRead(request) && url.pathname === "/") {
      return serveFile(request, response, path.join(publicDir, "index.html"), "text/html; charset=utf-8");
    }

    if (isRead(request) && url.pathname === "/app.css") {
      return serveFile(request, response, path.join(publicDir, "app.css"), "text/css; charset=utf-8");
    }

    if (isRead(request) && url.pathname === "/app.js") {
      return serveFile(request, response, path.join(publicDir, "app.js"), "application/javascript; charset=utf-8");
    }

    if (request.method === "GET" && url.pathname === "/api/presets") {
      return sendJson(response, {
        presets: listPresetNames().map((name) => ({
          name,
          ...PRESETS[name]
        }))
      });
    }

    if (request.method === "GET" && url.pathname === "/api/settings") {
      return sendJson(response, publicSettingsPayload());
    }

    if (request.method === "POST" && url.pathname === "/api/settings") {
      const body = await readJson(request);
      const settings = {};
      for (const key of ["baseUrl", "textModel", "ttsModel", "voiceId"]) {
        if (Object.prototype.hasOwnProperty.call(body, key)) {
          settings[key] = body[key];
        }
      }
      if (Object.prototype.hasOwnProperty.call(body, "apiKey")) {
        settings.apiKey = body.apiKey;
      }
      saveAppSettings(settings);
      return sendJson(response, publicSettingsPayload());
    }

    if (request.method === "GET" && url.pathname === "/api/voices") {
      const catalog = await getChineseVoiceCatalog();
      return sendJson(response, catalog);
    }

    if (request.method === "POST" && url.pathname === "/api/tts") {
      const body = await readJson(request);
      const result = await synthesize(body);
      return sendJson(response, result);
    }

    if (request.method === "POST" && url.pathname === "/api/ai-dj/start") {
      aiDj.start();
      return sendJson(response, aiDj.snapshot());
    }

    if (request.method === "POST" && url.pathname === "/api/ai-dj/stop") {
      await aiDj.stop();
      return sendJson(response, aiDj.snapshot());
    }

    if (request.method === "POST" && url.pathname === "/api/ai-dj/test") {
      await aiDj.test();
      return sendJson(response, aiDj.snapshot());
    }

    if (request.method === "GET" && url.pathname === "/api/ai-dj/status") {
      return sendJson(response, aiDj.snapshot());
    }

    if (request.method === "POST" && url.pathname === "/api/local-dj/netease/setup") {
      const body = await readJson(request);
      return sendJson(response, await localDj.setupNetease(body));
    }

    if (request.method === "POST" && url.pathname === "/api/local-dj/netease/start") {
      return sendJson(response, await localDj.startNetease());
    }

    if (request.method === "POST" && url.pathname === "/api/local-dj/netease/login/start") {
      return sendJson(response, await localDj.startNeteaseLogin());
    }

    if (request.method === "POST" && url.pathname === "/api/local-dj/netease/login/status") {
      return sendJson(response, await localDj.checkNeteaseLogin());
    }

    if (request.method === "GET" && url.pathname === "/api/local-dj/netease/playlists") {
      return sendJson(response, await localDj.loadNeteasePlaylists());
    }

    if (request.method === "POST" && url.pathname === "/api/local-dj/netease/stop") {
      return sendJson(response, await localDj.stopNetease());
    }

    if (request.method === "POST" && url.pathname === "/api/local-dj/playlist/load") {
      const body = await readJson(request);
      return sendJson(response, await localDj.loadPlaylist({
        playlistId: body.playlistId,
        requestedQuality: body.quality,
        limit: body.limit
      }));
    }

    if (request.method === "POST" && url.pathname === "/api/local-dj/play") {
      return sendJson(response, await localDj.play());
    }

    if (request.method === "POST" && url.pathname === "/api/local-dj/pause") {
      return sendJson(response, await localDj.pause());
    }

    if (request.method === "POST" && url.pathname === "/api/local-dj/next") {
      return sendJson(response, await localDj.next());
    }

    if (request.method === "POST" && url.pathname === "/api/local-dj/stop") {
      return sendJson(response, await localDj.stop());
    }

    if (request.method === "GET" && url.pathname === "/api/local-dj/status") {
      return sendJson(response, localDj.snapshot());
    }

    if (request.method === "POST" && url.pathname === "/api/quit") {
      await aiDj.stop();
      await localDj.stop();
      await localDj.stopNetease();
      sendJson(response, { ok: true });
      setTimeout(() => server.close(() => process.exit(0)), 250);
      return;
    }

    if (isRead(request) && url.pathname.startsWith("/audio/")) {
      const fileName = path.basename(decodeURIComponent(url.pathname.replace("/audio/", "")));
      const filePath = path.join(outputDir, fileName);
      if (!filePath.startsWith(outputDir) || !fs.existsSync(filePath)) {
        return sendJson(response, { error: "Audio file not found." }, 404);
      }
      return serveFile(request, response, filePath, contentTypeFor(filePath));
    }

    sendJson(response, { error: "Not found." }, 404);
  } catch (error) {
    sendJson(response, { error: error.message || String(error) }, 500);
  }
});

server.listen(requestedPort, "127.0.0.1", () => {
  const address = server.address();
  const url = `http://127.0.0.1:${address.port}`;
  console.log(`MiniMax TTS Studio running at ${url}`);

  if (args.has("--open")) {
    spawn("open", [url], {
      detached: true,
      stdio: "ignore"
    }).unref();
  }
});

async function synthesize(body) {
  const text = String(body.text || "").trim();
  if (!text) throw new Error("请输入要合成的文本。");

  const preset = getPreset(body.preset || "radio");
  const format = String(body.format || "mp3").toLowerCase();
  const fileName = `tts-${new Date().toISOString().replace(/[:.]/g, "-")}.${format}`;
  const outPath = path.join(outputDir, fileName);

  const payload = {
    model: body.model || getEffectiveApiConfig().ttsModel,
    text,
    stream: false,
    language_boost: body.language || "Chinese",
    output_format: "hex",
    voice_setting: {
      voice_id: body.voice || getEffectiveApiConfig().voiceId || preset.voiceId,
      speed: numberOr(body.speed, preset.speed),
      vol: numberOr(body.vol, preset.vol),
      pitch: numberOr(body.pitch, preset.pitch)
    },
    audio_setting: {
      sample_rate: numberOr(body.sampleRate, 32000),
      bitrate: numberOr(body.bitrate, 128000),
      format,
      channel: numberOr(body.channel, 1)
    },
    latex_read: false,
    english_normalization: true,
    subtitle_enable: false
  };

  const client = createMiniMaxClient();
  const apiResult = await client.textToAudio(payload);
  const bytes = await writeAudioFromMiniMaxResponse(apiResult, outPath);

  return {
    ok: true,
    url: `/audio/${encodeURIComponent(fileName)}`,
    path: outPath,
    bytes,
    durationMs: apiResult.extra_info?.audio_length || null,
    voice: payload.voice_setting.voice_id,
    model: payload.model
  };
}

function serveFile(request, response, filePath, contentType) {
  if (!fs.existsSync(filePath)) {
    return sendJson(response, { error: "File not found." }, 404);
  }
  const stat = fs.statSync(filePath);
  response.writeHead(200, {
    "Content-Type": contentType,
    "Content-Length": stat.size,
    "Cache-Control": "no-store"
  });
  if (request.method === "HEAD") {
    response.end();
    return;
  }
  fs.createReadStream(filePath).pipe(response);
}

function sendJson(response, payload, statusCode = 200) {
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  });
  response.end(JSON.stringify(payload));
}

function readJson(request) {
  return new Promise((resolve, reject) => {
    let raw = "";
    request.on("data", (chunk) => {
      raw += chunk;
      if (raw.length > 200_000) {
        reject(new Error("文本太长了，请先缩短一点再测试。"));
        request.destroy();
      }
    });
    request.on("end", () => {
      if (!raw) return resolve({});
      try {
        resolve(JSON.parse(raw));
      } catch {
        reject(new Error("请求格式不是有效 JSON。"));
      }
    });
    request.on("error", reject);
  });
}

function numberOr(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function contentTypeFor(filePath) {
  if (filePath.endsWith(".wav")) return "audio/wav";
  if (filePath.endsWith(".flac")) return "audio/flac";
  return "audio/mpeg";
}

function isRead(request) {
  return request.method === "GET" || request.method === "HEAD";
}

async function getChineseVoiceCatalog() {
  const client = createMiniMaxClient();
  const result = await client.listVoices({ voiceType: "system" });
  const voiceGroups = [
    result.system_voice || [],
    result.voice_cloning || [],
    result.voice_generation || [],
    result.music_generation || []
  ];

  const voices = voiceGroups
    .flat()
    .map(normalizeVoice)
    .filter((voice) => isChineseVoice(voice));

  const deduped = [];
  const seen = new Set();
  for (const voice of voices) {
    if (!voice.voice_id || seen.has(voice.voice_id)) continue;
    seen.add(voice.voice_id);
    voice.group = classifyVoiceGroup(voice);
    deduped.push(voice);
  }

  deduped.sort((left, right) => {
    const leftRank = voiceRank(left.voice_id);
    const rightRank = voiceRank(right.voice_id);
    if (leftRank !== rightRank) return leftRank - rightRank;
    return left.voice_name.localeCompare(right.voice_name, "zh-Hans-CN");
  });

  const grouped = {
    radio: [],
    emotion: [],
    girl: [],
    male: [],
    news: []
  };

  for (const voice of deduped) {
    if (grouped[voice.group]) {
      grouped[voice.group].push(voice);
    }
  }

  return {
    voices: deduped,
    groups: grouped
  };
}

function normalizeVoice(voice) {
  return {
    voice_id: voice.voice_id || voice.voiceId || voice.id || "",
    voice_name: voice.voice_name || voice.name || voice.display_name || "",
    created_time: voice.created_time || voice.createdTime || null
  };
}

function isChineseVoice(voice) {
  const id = String(voice.voice_id || "");
  const name = String(voice.voice_name || "");
  return (
    /^Chinese \(Mandarin\)_/i.test(id) ||
    /^Cantonese_/i.test(id) ||
    hasCjk(name) ||
    isChineseStyleId(id)
  );
}

function classifyVoiceGroup(voice) {
  const id = String(voice.voice_id || "").toLowerCase();
  const name = String(voice.voice_name || "");

  if (
    id.includes("news_anchor") ||
    id.includes("male_announcer") ||
    id.includes("reliable_executive") ||
    id.includes("announcer") ||
    /新闻|播报|资讯/.test(name)
  ) {
    return "news";
  }

  if (
    id.includes("radio_host") ||
    id.includes("warm_bestie") ||
    id.includes("gentleman") ||
    id.includes("lyrical_voice") ||
    id.includes("sincere_adult") ||
    id.includes("gentle_youth") ||
    /电台|主播|旁白|抒情|温润|沉稳/.test(name)
  ) {
    return "radio";
  }

  if (
    /^((male-qn-|male_|male-)|clever_boy|cute_boy|bingjiao_didi|junlang_nanyou|chunzhen_xuedi|lengdan_xiongzhang|badao_shaoye|chunzhen_xuedi|straightforward_boy|pure-hearted_boy|unrestrained_young_man|southern_young_man)/i.test(id) ||
    /男|青年|男童|男孩|boy|man|gentleman/.test(name)
  ) {
    return "male";
  }

  if (
    /^(female-|female_|lovely_girl|sweet_girl|cute_elf|attractive_girl|serene_woman|arrogant_miss|tianxin_xiaoling|qiaopi_mengmei|wumei_yujie|diadia_xuemei|danya_xuejie)/i.test(id) ||
    /女|女孩|少女|小姐|御姐|甜美|萌|姐姐|lady|woman|girl/.test(name)
  ) {
    return "girl";
  }

  return "emotion";
}

function isChineseStyleId(id) {
  return /^(male-qn-|female-|clever_boy|cute_boy|lovely_girl|cartoon_pig|bingjiao_didi|junlang_nanyou|chunzhen_xuedi|lengdan_xiongzhang|badao_shaoye|tianxin_xiaoling|qiaopi_mengmei|wumei_yujie|diadia_xuemei|danya_xuejie|Arrogant_Miss|Robot_Armor)/i.test(id);
}

function hasCjk(text) {
  return /[\u3400-\u9fff]/.test(text);
}

function voiceRank(id) {
  const preferred = new Set([
    "Chinese (Mandarin)_Radio_Host",
    "Chinese (Mandarin)_News_Anchor",
    "Chinese (Mandarin)_Male_Announcer",
    "Chinese (Mandarin)_Reliable_Executive",
    "Chinese (Mandarin)_Warm_Bestie",
    "Chinese (Mandarin)_Gentleman",
    "Chinese (Mandarin)_Mature_Woman",
    "Chinese (Mandarin)_Lyrical_Voice",
    "Chinese (Mandarin)_Sincere_Adult"
  ]);

  if (preferred.has(id)) return 0;
  if (/^Chinese \(Mandarin\)_/.test(id)) return 1;
  if (/^Cantonese_/.test(id)) return 2;
  return 3;
}
