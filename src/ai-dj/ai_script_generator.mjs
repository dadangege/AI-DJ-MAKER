import { getEffectiveApiConfig } from "../app-settings.mjs";

export async function generateDjScript(context = {}, {
  apiKey,
  baseUrl,
  model,
  triggerType = context.phaseType || context.triggerType || "pre_outro",
  moodHint = context.moodHint || ""
} = {}) {
  const effective = getEffectiveApiConfig({
    apiKey,
    baseUrl,
    textModel: model
  });
  apiKey = effective.apiKey;
  baseUrl = effective.baseUrl;
  model = effective.textModel;

  const transition = normalizeTransitionContext(context, triggerType, moodHint);
  if (!apiKey) {
    return fallbackScript(transition, triggerType);
  }

  try {
    const content = await requestDjText({
      apiKey,
      baseUrl,
      model,
      transition,
      phaseType: triggerType,
      moodHint,
      systemPrompt: buildSystemPrompt(transition, triggerType),
      temperature: 0.58,
      maxCompletionTokens: 1024
    });

    const cleaned = normalizeScriptText(content);
    if (cleaned) {
      return cleaned;
    }

    const retryContent = await requestDjText({
      apiKey,
      baseUrl,
      model,
      transition,
      phaseType: triggerType,
      moodHint,
      systemPrompt: [
        "你现在是电台的情感主播。",
        `刚才的串场没有给出可直接播报的最终版本。`,
        phasePrompt(triggerType),
        "现在只输出最终串场正文，不要思考过程，不要 <think>，不要解释，不要分行。"
      ].join("\n"),
      temperature: 0.42,
      maxCompletionTokens: 512
    });

    const retryCleaned = normalizeScriptText(retryContent);
    return retryCleaned || fallbackScript(transition, triggerType);
  } catch (error) {
    console.warn(`MiniMax text generation failed, using fallback script: ${error.message}`);
    return fallbackScript(transition, triggerType);
  }
}

async function requestDjText({
  apiKey,
  baseUrl,
  model,
  transition,
  phaseType,
  moodHint,
  systemPrompt,
  temperature,
  maxCompletionTokens
}) {
  const response = await fetch(`${versionedBaseUrl(baseUrl)}/chat/completions`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model,
      messages: [
        {
          role: "system",
          name: "AI_DJ",
          content: systemPrompt
        },
        {
          role: "user",
          name: "NowPlaying",
          content: JSON.stringify(buildPromptPayload(transition, phaseType, moodHint))
        }
      ],
      temperature,
      top_p: 0.9,
      max_completion_tokens: maxCompletionTokens
    })
  });

  const raw = await response.text();
  const json = JSON.parse(raw);
  if (!response.ok || json?.base_resp?.status_code) {
    throw new Error(json?.base_resp?.status_msg || raw);
  }

  return extractAssistantText(json);
}

function versionedBaseUrl(baseUrl) {
  const normalized = baseUrl.replace(/\/$/, "");
  return /\/v1$/i.test(normalized) ? normalized : `${normalized}/v1`;
}

function cleanModelText(text) {
  return String(text)
    .replace(/<think>[\s\S]*?<\/think>/gi, "")
    .replace(/^```[\s\S]*?\n/, "")
    .replace(/```$/g, "")
    .replace(/^["'“”‘’]+|["'“”‘’]+$/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeScriptText(text) {
  const cleaned = cleanModelText(text);
  if (!cleaned) return "";

  const withoutSpaces = cleaned.replace(/\s+/g, "");
  const utterance = takeSentenceChunk(withoutSpaces, 2);
  if (utterance && countCjkCharacters(utterance) >= 8) {
    return ensureSentenceEnding(utterance);
  }

  const cjkCount = countCjkCharacters(withoutSpaces);
  if (cjkCount < 8) {
    return "";
  }

  return ensureSentenceEnding(withoutSpaces);
}

function takeSentenceChunk(text, maxSentences = 2) {
  const sentences = String(text).match(/[^。！？!?]+[。！？!?]?/g) || [];
  if (!sentences.length) {
    return String(text).trim();
  }
  return sentences.slice(0, maxSentences).join("").trim();
}

function extractAssistantText(json) {
  const content = json?.choices?.[0]?.message?.content || "";
  if (content && content.includes("</think>")) {
    return content.replace(/<think>[\s\S]*?<\/think>/gi, "").trim();
  }
  return content;
}

function ensureSentenceEnding(text) {
  const cleaned = String(text).replace(/[，。！？、,.!?；;：:—-]+$/, "");
  return /[。！？!?]$/.test(cleaned) ? cleaned : `${cleaned}。`;
}

function fallbackScript(context, phaseType) {
  const current = context.currentTrack || context.trackState || context || {};
  const previous = context.previousTrack || context.fromTrack || null;
  const next = context.nextTrack || context.toTrack || null;
  const bridgeFrom = context.bridgeFromTrack || previous || current || null;
  const bridgeTo = context.bridgeToTrack || next || null;

  if (phaseType === "gap_bridge") {
    if (bridgeFrom?.title && bridgeTo?.title) {
      return `刚从《${bridgeFrom.title}》走出来，下一首《${bridgeTo.title}》也会顺着接上。`;
    }
    return `刚才那首的余韵还在，下一首也会顺着这份情绪接上。`;
  }

  if (current?.title) {
    if (bridgeFrom?.title && bridgeTo?.title) {
      return `从《${bridgeFrom.title}》到《${bridgeTo.title}》，情绪会顺着接上。`;
    }
    return `《${current.title}》快要收尾了，先把这一段情绪留住。`;
  }

  if (previous?.title) {
    return `刚刚《${previous.title}》的情绪还在，下一首也会顺着接上。`;
  }

  return `这首歌快到尾声了，下一首也会顺着接上。`;
}

function buildSystemPrompt(transition, phaseType) {
  const bridgeFrom = transition.bridgeFromTrack || transition.previousTrack || transition.fromTrack || transition.currentTrack || transition.trackState || transition || {};
  const bridgeTo = transition.bridgeToTrack || transition.nextTrack || transition.toTrack || null;

  return [
    "你现在是电台的情感主播。",
    "你正在为两首歌之间的衔接生成串场。",
    `当前阶段是 ${phaseType}，重点只围绕上一首和下一首的连接来写，不要把它写成单首歌介绍。`,
    bridgeFrom?.title ? `上一首是《${bridgeFrom.title}》${bridgeFrom.artist ? `，演唱者是 ${bridgeFrom.artist}` : ""}。` : "上一首信息可能缺失。",
    bridgeTo?.title ? `下一首是《${bridgeTo.title}》${bridgeTo.artist ? `，演唱者是 ${bridgeTo.artist}` : ""}。` : "下一首信息可能缺失。",
    phasePrompt(phaseType),
    "可以是情绪类的，也可以是正常描述类的，像真实主播自然接话。",
    "不要输出思考过程，不要输出 <think>。",
    "只输出可以直接播报的正文，不要 Markdown，不要解释，不要分行。"
  ].join("\n");
}

function buildPromptPayload(transition, phaseType, moodHint) {
  const current = transition.currentState || transition.trackState || transition.currentTrack || transition || {};
  const previous = transition.previousState || transition.previousTrack || transition.fromTrack || null;
  const next = transition.nextState || transition.nextTrack || transition.toTrack || null;
  const bridgeFrom = transition.bridgeFromTrack || previous || current || null;
  const bridgeTo = transition.bridgeToTrack || next || null;

  return {
    phaseType,
    phaseRole: transition.phaseRole || "",
    moodHint,
    bridgeFromTrack: summarizeTrack(bridgeFrom),
    bridgeToTrack: summarizeTrack(bridgeTo),
    previousTrack: summarizeTrack(previous),
    currentTrack: summarizeTrack(current),
    nextTrack: summarizeTrack(next),
    transitionGoal: transition.phaseRole || phasePrompt(phaseType),
    elapsed: numberOrNull(current.elapsed),
    duration: numberOrNull(current.duration),
    sourceApp: current.sourceApp || ""
  };
}

function summarizeTrack(track) {
  if (!track) return null;
  return {
    title: track.title || "",
    artist: track.artist || "",
    album: track.album || "",
    trackId: track.trackId || "",
    sourceApp: track.sourceApp || ""
  };
}

function phasePrompt(phaseType) {
  if (phaseType === "pre_outro") {
    return [
      "这是 pre_outro 串场。",
      "重点是把上一首收住，再把下一首自然带出来。",
      "语气要像主播在两首歌的交界处轻轻接话，顺滑、不突兀。"
    ].join("\n");
  }

  if (phaseType === "gap_bridge") {
    return [
      "这是 gap_bridge 串场。",
      "重点是承接上一首，并把下一首稳稳接进来。",
      "语气要自然、短促一点，但要完整。"
    ].join("\n");
  }

  return [
    "这是 pre_outro 串场。",
    "重点是承接当前歌曲尾声，并顺势引出下一首。",
    "语气要像主播在收尾时轻轻接话，顺滑、不突兀。"
  ].join("\n");
}

function countCjkCharacters(text) {
  return (String(text).match(/[\u3400-\u9fff]/g) || []).length;
}

function normalizeTransitionContext(context, triggerType, moodHint) {
  const currentState = context.currentState || context.trackState || context.currentTrack || context || {};
  const previousState = context.previousState || context.fromTrack || context.previousTrack || null;
  const nextState = context.nextState || context.toTrack || context.nextTrack || null;
  const bridgeFromState = context.bridgeFromState || context.bridgeFromTrack || previousState || currentState;
  const bridgeToState = context.bridgeToState || context.bridgeToTrack || nextState || null;

  return {
    phaseType: context.phaseType || context.triggerType || triggerType,
    phaseRole: context.phaseRole || "",
    moodHint: context.moodHint || moodHint || "",
    currentState,
    previousState,
    nextState,
    bridgeFromTrack: summarizeTrack(bridgeFromState),
    bridgeToTrack: summarizeTrack(bridgeToState),
    currentTrack: summarizeTrack(currentState),
    previousTrack: summarizeTrack(previousState),
    nextTrack: summarizeTrack(nextState),
    trackState: summarizeTrack(currentState)
  };
}

function numberOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}
