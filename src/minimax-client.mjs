import fs from "node:fs";
import path from "node:path";

import { getEffectiveApiConfig } from "./app-settings.mjs";

export function createMiniMaxClient({
  apiKey,
  baseUrl
} = {}) {
  const effective = getEffectiveApiConfig({ apiKey, baseUrl });
  apiKey = effective.apiKey;
  baseUrl = effective.baseUrl;

  if (!apiKey) {
    throw new Error("缺少 API Key。请在 App 顶部的 OpenAI-compatible 配置里填写，或设置 OPENAI_API_KEY / MINIMAX_API_KEY。");
  }

  const normalizedBaseUrl = baseUrl.replace(/\/$/, "");

  return {
    async textToAudio(payload) {
      const response = await fetch(buildEndpoint(normalizedBaseUrl, "t2a_v2"), {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify(payload)
      });

      const rawBody = await response.text();
      const json = parseJson(rawBody);

      if (!response.ok) {
        throw new Error(`MiniMax TTS request failed: HTTP ${response.status} ${rawBody}`);
      }

      const statusCode = json?.base_resp?.status_code;
      if (statusCode !== undefined && statusCode !== 0) {
        const statusMessage = json?.base_resp?.status_msg || "unknown error";
        throw new Error(`MiniMax TTS request failed: ${statusCode} ${statusMessage}`);
      }

      return json;
    },

    async listVoices({ voiceType = "system" } = {}) {
      const response = await fetch(buildEndpoint(normalizedBaseUrl, "get_voice"), {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          voice_type: voiceType
        })
      });

      const rawBody = await response.text();
      const json = parseJson(rawBody);

      if (!response.ok) {
        throw new Error(`MiniMax voices request failed: HTTP ${response.status} ${rawBody}`);
      }

      const statusCode = json?.base_resp?.status_code;
      if (statusCode !== undefined && statusCode !== 0) {
        const statusMessage = json?.base_resp?.status_msg || "unknown error";
        throw new Error(`MiniMax voices request failed: ${statusCode} ${statusMessage}`);
      }

      return json;
    }
  };
}

function buildEndpoint(baseUrl, pathName) {
  const versionedBaseUrl = /\/v1$/i.test(baseUrl) ? baseUrl : `${baseUrl}/v1`;
  return `${versionedBaseUrl}/${pathName}`;
}

export async function writeAudioFromMiniMaxResponse(result, outPath) {
  const audio = result?.data?.audio;
  if (!audio) {
    throw new Error(`MiniMax response did not include data.audio: ${JSON.stringify(result)}`);
  }

  fs.mkdirSync(path.dirname(outPath), { recursive: true });

  if (/^https?:\/\//i.test(audio)) {
    const response = await fetch(audio);
    if (!response.ok) {
      throw new Error(`Failed to download audio URL: HTTP ${response.status}`);
    }
    const buffer = Buffer.from(await response.arrayBuffer());
    fs.writeFileSync(outPath, buffer);
    return buffer.length;
  }

  const buffer = Buffer.from(audio, "hex");
  fs.writeFileSync(outPath, buffer);
  return buffer.length;
}

function parseJson(rawBody) {
  try {
    return JSON.parse(rawBody);
  } catch {
    throw new Error(`MiniMax returned non-JSON response: ${rawBody}`);
  }
}
