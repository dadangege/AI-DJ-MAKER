import fs from "node:fs";
import path from "node:path";

import { config as defaultConfig } from "./config.mjs";
import { createPlayerListener } from "./player_listener.mjs";
import { ProgressWatcher, findCurrentPhase, findNextPhase, formatPlanSummary, summarizePhaseStates } from "./progress_watcher.mjs";
import { generateDjScript } from "./ai_script_generator.mjs";
import { synthesizeDjVoice } from "./tts_service.mjs";
import { createTransitionAudioPolicy } from "./transition_audio_policy.mjs";
import { AudioMixdownController } from "./audio_mixdown_controller.mjs";
import { getNeteaseFallbackState } from "./netease_fallback.mjs";

export function createAiDjSession({
  config = defaultConfig,
  listenerPath = config.listenerPath
} = {}) {
  let listener = null;
  const transitionPolicy = createTransitionAudioPolicy(config);
  let watcher = new ProgressWatcher(transitionPolicy);

  let running = false;
  let speaking = false;
  let lastState = null;
  let lastScript = "";
  let lastAudioPath = "";
  let logs = [];
  let runtime = null;
  let currentPhaseType = "";
  let stateQueue = Promise.resolve();
  let lastNowPlayingLogKey = "";
  let mixdown = new AudioMixdownController(transitionPolicy);

  return {
    start,
    stop,
    test,
    snapshot
  };

  function start() {
    if (running) return;

    if (!fs.existsSync(listenerPath)) {
      addLog("error", "Now Playing helper missing. Run: npm run ai-dj:build-listener");
      return;
    }

    runtime = null;
    watcher = new ProgressWatcher({
      ...transitionPolicy
    });

    listener = createPlayerListener({
      listenerPath,
      adapterScriptPath: config.mediaRemoteAdapterScript,
      adapterFrameworkPath: config.mediaRemoteAdapterFramework,
      adapterTestClientPath: config.mediaRemoteAdapterTestClient
    });
    running = true;
    addLog(
      "info",
      `AI DJ started. pre_outro ${transitionPolicy.preOutroLeadSeconds}s, gap_bridge ${transitionPolicy.gapBridgeGraceSeconds}s, TTS prefetch ${transitionPolicy.ttsPrefetchLeadSeconds}s before each trigger.`
    );

    listener.on("state", (state) => {
      enqueueState(state);
    });

    listener.on("stderr", (message) => addLog("warn", `helper: ${message}`));
    listener.on("error", (error) => addLog("error", `listener error: ${error.message}`));
    listener.on("exit", ({ code, signal }) => {
      running = false;
      addLog("warn", `Now Playing helper exited: code=${code} signal=${signal || ""}`);
    });

    listener.start();
  }

  async function stop() {
    if (listener) listener.stop();
    listener = null;
    running = false;
    speaking = false;
    currentPhaseType = "";
    runtime = null;
    await mixdown.forceEnd(addLog);
    addLog("info", "AI DJ stopped.");
  }

  async function test() {
    if (speaking) {
      addLog("info", "Test skipped because DJ voice is already playing.");
      return;
    }

    const state = lastState?.title
      ? { ...lastState, state: "playing", elapsed: Math.max(0, Number(lastState.elapsed) || 0) }
      : {
          title: "测试歌曲",
          artist: "AI DJ",
          album: "本地测试",
          elapsed: 12,
          duration: 180,
          playbackRate: 1,
          sourceApp: "manual-test",
          trackId: "manual-test"
        };

    addLog("info", "Manual test trigger requested.");
    await triggerPhaseImmediately("pre_outro", state);
  }

  async function enqueueState(state) {
    stateQueue = stateQueue
      .then(() => handleState(state))
      .catch((error) => {
        addLog("error", `AI DJ state handling failed: ${error.message}`);
      });
    return stateQueue;
  }

  async function handleState(rawState) {
    const effectiveState = await resolveEffectiveState(rawState);
    const previousState = lastState?.trackId && lastState.trackId !== effectiveState.trackId ? lastState : null;
    lastState = effectiveState;
    logNowPlaying(effectiveState);

    const plan = watcher.buildPlan({
      currentState: effectiveState,
      previousState
    });
    if (!plan) {
      return;
    }

    if (!runtime || runtime.trackId !== plan.trackId) {
      await mixdown.forceEnd(addLog);
      runtime = createRuntime(plan, effectiveState);
      currentPhaseType = "";
      addLog("info", `Phase plan ready: ${formatPlanSummary(plan) || "暂无计划"}.`);
      primePhaseCache(runtime);
    } else {
      runtime.plan = mergeRuntimePlan(runtime.plan, plan);
      runtime.state = effectiveState;
      syncPhaseStatusFromState(runtime, effectiveState);
    }

    warmAudioCache(runtime, effectiveState);
    void tryPlayDuePhase(runtime, effectiveState);
  }

  function createRuntime(plan, state) {
    const phases = plan.phases.map((phase) => ({
      ...phase,
      scriptStatus: "idle",
      audioStatus: "idle",
      playStatus: "idle",
      script: "",
      audioPath: "",
      audioBytes: 0,
      error: "",
      scriptPromise: null,
      audioPromise: null,
      unreliableProgressWarned: false,
      duckingWarned: false
    }));

    return {
      trackId: plan.trackId,
      plan: {
        ...plan,
        phases
      },
      state,
      timing: {
        scriptMsEma: null,
        audioMsEma: null,
        scriptSamples: 0,
        audioSamples: 0
      }
    };
  }

  function mergeRuntimePlan(previousPlan, nextPlan) {
    const previousPhases = new Map(
      (previousPlan?.phases || []).map((phase) => [phaseKey(phase), phase])
    );

    const phases = nextPlan.phases.map((nextPhase) => {
      const previousPhase = previousPhases.get(phaseKey(nextPhase));
      if (!previousPhase) {
        return initializePhaseRuntime(nextPhase);
      }

      const triggerAtSeconds = previousPhase.playAtSeconds ?? previousPhase.triggerAtSeconds ?? nextPhase.triggerAtSeconds;
      const anchorAtSeconds = previousPhase.anchorAtSeconds ?? nextPhase.anchorAtSeconds ?? nextPhase.triggerAtSeconds;
      const prefetchAtSeconds = previousPhase.prefetchAtSeconds ?? nextPhase.prefetchAtSeconds;
      const effectivePrefetchAtSeconds = previousPhase.effectivePrefetchAtSeconds ?? nextPhase.effectivePrefetchAtSeconds;
      const windowEndSeconds = Math.max(Number(previousPhase.windowEndSeconds) || 0, Number(nextPhase.windowEndSeconds) || 0);

      Object.assign(previousPhase, nextPhase, {
        triggerAtSeconds,
        anchorAtSeconds,
        prefetchAtSeconds,
        effectivePrefetchAtSeconds,
        windowEndSeconds,
        unreliableProgressWarned: Boolean(previousPhase.unreliableProgressWarned)
      });

      return previousPhase;
    });

    return {
      ...nextPlan,
      phases
    };
  }

  function initializePhaseRuntime(phase) {
    return {
      ...phase,
      scriptStatus: "idle",
      audioStatus: "idle",
      playStatus: "idle",
      script: "",
      audioPath: "",
      audioBytes: 0,
      error: "",
      scriptPromise: null,
      audioPromise: null,
      unreliableProgressWarned: false,
      duckingWarned: false
    };
  }

  function phaseKey(phase) {
    return `${phase.type}|${phase.fromTrack?.trackId || ""}|${phase.toTrack?.trackId || ""}`;
  }

  function primePhaseCache(currentRuntime) {
    for (const phase of currentRuntime.plan.phases) {
      addLog("info", `${phase.label} 开始提前生成文案和音频。`);
      void ensurePhaseAudio(currentRuntime, phase);
    }
  }

  function warmAudioCache(currentRuntime, state) {
    if (currentRuntime.plan.planType === "gap") {
      for (const phase of currentRuntime.plan.phases) {
        if (phase.audioStatus === "idle") {
          void ensurePhaseAudio(currentRuntime, phase);
        }
      }
      return;
    }

    const elapsed = Number(state.elapsed);
    if (!Number.isFinite(elapsed)) return;

    for (const phase of currentRuntime.plan.phases) {
      if (phase.audioStatus !== "idle") continue;
      const warmupLeadSeconds = estimateWarmupLeadSeconds(currentRuntime, phase);
      const effectivePrefetchAt = Math.max(0, Math.round(phase.triggerAtSeconds - warmupLeadSeconds));
      phase.effectivePrefetchAtSeconds = effectivePrefetchAt;
      if (elapsed < effectivePrefetchAt) continue;
      void ensurePhaseAudio(currentRuntime, phase);
    }
  }

  function syncPhaseStatusFromState(currentRuntime, state) {
    const elapsed = Number(state.elapsed);
    for (const phase of currentRuntime.plan.phases) {
      if (phase.playStatus === "done") continue;
      if (!Number.isFinite(elapsed)) continue;
      if (elapsed >= phase.triggerAtSeconds && elapsed <= phase.windowEndSeconds) {
        currentPhaseType = phase.type;
        break;
      }
    }
  }

  async function triggerPhaseImmediately(phaseType, state) {
    const manualPreviousState = {
      title: "上一首测试歌",
      artist: "AI DJ",
      album: "本地测试",
      elapsed: 128,
      duration: 240,
      playbackRate: 1,
      sourceApp: "manual-test",
      trackId: "manual-test-prev"
    };

    const plan = watcher.buildPlan({
      currentState: state,
      previousState: manualPreviousState
    }) || createManualPlan(state);
    const phase = plan.phases.find((item) => item.type === phaseType) || plan.phases[0];
    if (!phase) return;

    const manualRuntime = createRuntime(plan, state);
    runtime = manualRuntime;
    currentPhaseType = phase.type;
    primePhaseCache(manualRuntime);
    await playPhase(manualRuntime, phase, state, { bypassWindow: true });
  }

  function createManualPlan(state) {
    const duration = Number.isFinite(Number(state.duration)) ? Number(state.duration) : 180;
    const currentState = {
      ...state,
      state: "playing",
      title: state.title || "测试歌曲",
      artist: state.artist || "AI DJ",
      album: state.album || "本地测试",
      duration,
      elapsed: Number.isFinite(Number(state.elapsed)) ? Number(state.elapsed) : 12,
      playbackRate: Number(state.playbackRate) || 1,
      sourceApp: state.sourceApp || "manual-test",
      trackId: state.trackId || `manual|${state.title || "test"}`
    };
    const previousState = {
      title: "上一首测试歌",
      artist: "AI DJ",
      album: "本地测试",
      duration: 240,
      elapsed: 128,
      playbackRate: 1,
      sourceApp: "manual-test",
      trackId: "manual-test-prev"
    };

    return watcher.buildPlan({
      currentState,
      previousState
    }) || {
      planType: "active",
      trackId: currentState.trackId,
      currentTrack: currentState,
      previousTrack: previousState,
      nextTrack: null,
      phases: [
        watcher.buildPhase({
          type: "pre_outro",
          label: "收尾串场",
          triggerAtSeconds: 5,
          prefetchLeadSeconds: transitionPolicy.ttsPrefetchLeadSeconds,
          windowEndSeconds: 14,
          fromTrack: currentState,
          toTrack: null,
          phaseRole: "承接当前歌曲尾声并顺势引出下一首",
          state: currentState
        })
      ]
    };
  }

  async function resolveEffectiveState(state) {
    if (hasMeaningfulNowPlayingState(state)) {
      return annotateStateSource(state, "system-now-playing", "系统 Now Playing");
    }

    const fallback = await getNeteaseFallbackState();
    if (fallback) {
      if (lastState?.trackId !== fallback.trackId) {
        addLog("info", `Using NetEase fallback: ${fallback.artist || "未知歌手"} - ${fallback.title}`);
      }
      return annotateStateSource(fallback, "netease-fallback", "网易云缓存兜底");
    }

    return annotateStateSource(state, "system-now-playing", "系统 Now Playing");
  }

  async function ensurePhaseScript(currentRuntime, phase) {
    if (!phase) {
      return "";
    }

    if (phase.scriptStatus === "ready") {
      return phase.script || "";
    }

    if (phase.scriptStatus === "pending" && phase.scriptPromise) {
      return phase.scriptPromise;
    }

    phase.scriptStatus = "pending";
    phase.scriptPromise = (async () => {
      const startedAt = Date.now();
      const script = await generateDjScript({
        currentState: currentRuntime.state,
        previousState: currentRuntime.plan?.previousTrack || phase.fromTrack || null,
        nextTrack: currentRuntime.plan?.nextTrack || phase.toTrack || null,
        bridgeFromTrack: phase.fromTrack || currentRuntime.plan?.previousTrack || currentRuntime.state || null,
        bridgeToTrack: phase.toTrack || currentRuntime.plan?.nextTrack || null,
        phaseType: phase.type,
        phaseRole: phase.phaseRole,
        moodHint: phase.moodHint
      }, {
        model: config.textModel,
        triggerType: phase.type,
        moodHint: phase.moodHint
      });

      if (!isRuntimeCurrent(currentRuntime)) {
        return "";
      }

      phase.script = script;
      phase.scriptStatus = "ready";
      phase.scriptLatencyMs = Date.now() - startedAt;
      bumpLatencyEstimate(currentRuntime, "scriptMsEma", "scriptSamples", phase.scriptLatencyMs);
      addLog("script", `${phase.label}文案已缓存：${script}`);
      return script;
    })()
      .catch((error) => {
        phase.error = error.message;
        phase.scriptStatus = "error";
        addLog("error", `${phase.label}文案生成失败: ${error.message}`);
        return "";
      })
      .finally(() => {
        phase.scriptPromise = null;
      });

    return phase.scriptPromise;
  }

  async function ensurePhaseAudio(currentRuntime, phase) {
    if (!phase) return null;
    if (phase.audioStatus === "ready" && phase.audioPath) {
      return {
        path: phase.audioPath,
        bytes: phase.audioBytes
      };
    }

    if (phase.audioStatus === "pending") {
      return phase.audioPromise;
    }

    phase.audioStatus = "pending";
    phase.audioPromise = (async () => {
      const script = phase.script || (await ensurePhaseScript(currentRuntime, phase));
      if (!isRuntimeCurrent(currentRuntime)) {
        return null;
      }
      if (!script) {
        throw new Error(`${phase.label} 没有可用的口播文案。`);
      }

      const startedAt = Date.now();
      const audio = await synthesizeDjVoice(script, config);
      if (!isRuntimeCurrent(currentRuntime)) {
        return null;
      }

      phase.audioPath = audio.path;
      phase.audioBytes = audio.bytes;
      phase.audioDurationMs = Number.isFinite(Number(audio.durationMs)) ? Number(audio.durationMs) : null;
      phase.audioLatencyMs = Date.now() - startedAt;
      bumpLatencyEstimate(currentRuntime, "audioMsEma", "audioSamples", phase.audioLatencyMs);
      phase.anchorAtSeconds = Number.isFinite(Number(phase.anchorAtSeconds)) ? Number(phase.anchorAtSeconds) : phase.triggerAtSeconds;

      if (phase.type === "pre_outro" && Number.isFinite(phase.audioDurationMs)) {
        const fadeLeadSeconds = (transitionPolicy.duckFadeSteps * transitionPolicy.duckFadeStepDelayMs) / 1000;
        const boundarySeconds = Number.isFinite(Number(phase.anchorAtSeconds)) ? Number(phase.anchorAtSeconds) : phase.triggerAtSeconds;
        const halfDurationSeconds = phase.audioDurationMs / 2000;
        const playAtSeconds = Math.max(0, boundarySeconds - halfDurationSeconds - fadeLeadSeconds);
        phase.playAtSeconds = playAtSeconds;
        phase.triggerAtSeconds = playAtSeconds;
        phase.windowEndSeconds = Math.max(phase.windowEndSeconds, playAtSeconds + (phase.audioDurationMs / 1000) + fadeLeadSeconds);
        addLog(
          "info",
          `${phase.label} 对齐到切歌边界：边界 ${formatSeconds(boundarySeconds)}，音频 ${Math.round(phase.audioDurationMs)}ms，播放点 ${formatSeconds(playAtSeconds)}。`
        );
      }

      phase.audioStatus = "ready";
      addLog("tts", `${phase.label} 音频已缓存：${path.basename(audio.path)} (${audio.bytes} bytes${Number.isFinite(phase.audioDurationMs) ? `, ${Math.round(phase.audioDurationMs)}ms` : ""})`);
      return audio;
    })()
      .catch((error) => {
        phase.error = error.message;
        phase.audioStatus = "error";
        addLog("error", `${phase.label} 音频合成失败: ${error.message}`);
        return null;
      })
      .finally(() => {
        phase.audioPromise = null;
      });

    return phase.audioPromise;
  }

  async function tryPlayDuePhase(currentRuntime, state) {
    const phase = findPlayablePhase(currentRuntime, state);
    if (!phase) {
      return;
    }

    if (speaking) {
      return;
    }

    await playPhase(currentRuntime, phase, state);
  }

  async function playPhase(currentRuntime, phase, state, { bypassWindow = false } = {}) {
    if (!phase || speaking) return;
    if (!isRuntimeCurrent(currentRuntime)) return;
    if (!bypassWindow && state.progressReliable === false) {
      if (!phase.unreliableProgressWarned) {
        phase.unreliableProgressWarned = true;
        addLog("warn", `${phase.label} 暂停自动播放：当前进度来自缓存估算，无法可靠识别暂停或拖动。`);
      }
      return;
    }

    const elapsed = Number(state.elapsed);
    if (!bypassWindow && Number.isFinite(elapsed)) {
      if (elapsed < phase.triggerAtSeconds || elapsed > phase.windowEndSeconds) {
        return;
      }
    }

    speaking = true;
    currentPhaseType = phase.type;
    phase.playStatus = "queued";
    const logTrack = state?.title ? state : phase.toTrack || phase.fromTrack || state || {};
    addLog("info", `Trigger ${phase.label} @ ${formatSeconds(phase.triggerAtSeconds)}: ${logTrack.artist || "未知歌手"} - ${logTrack.title || "未知歌曲"}`);

    try {
      const audio = await ensurePhaseAudio(currentRuntime, phase);
      if (!audio || !isRuntimeCurrent(currentRuntime)) {
        phase.playStatus = "error";
        return;
      }

      const useMixdown = phase.type !== "gap_bridge";
      const duckSession = useMixdown ? await mixdown.begin(state, { logger: addLog }) : null;
      phase.playStatus = "playing";
      lastScript = phase.script || "";
      lastAudioPath = audio.path;
      try {
        await mixdown.play(audio.path);
        phase.playStatus = "done";
        addLog("info", `${phase.label} TTS playback finished.`);
      } finally {
        if (duckSession) {
          await mixdown.end(addLog);
        }
        if (useMixdown && !duckSession && !currentRuntime.duckingWarned) {
          currentRuntime.duckingWarned = true;
          addLog("warn", `Ducking fallback: ${state.sourceApp || "unknown"} 无法压低背景音乐，已退回到不调整播放器。`);
        }
      }
    } catch (error) {
      phase.playStatus = "error";
      addLog("error", `${phase.label} playback failed: ${error.message}`);
    } finally {
      speaking = false;
      if (currentPhaseType === phase.type) {
        currentPhaseType = "";
      }
    }
  }

  function findPlayablePhase(currentRuntime, state) {
    if (!currentRuntime) return null;

    const elapsed = Number(state.elapsed);
    const isPlaying = state?.state === "playing";

    return currentRuntime.plan.phases.find((phase) => {
      if (phase.playStatus === "done" || phase.playStatus === "queued" || phase.playStatus === "playing" || phase.playStatus === "error") {
        return false;
      }

      if (phase.type === "gap_bridge") {
        return !isPlaying;
      }

      if (!Number.isFinite(elapsed)) {
        return false;
      }

      return elapsed >= phase.triggerAtSeconds && elapsed <= phase.windowEndSeconds;
    }) || null;
  }

  function isRuntimeCurrent(currentRuntime) {
    return Boolean(runtime && currentRuntime && runtime.trackId === currentRuntime.trackId);
  }

  function snapshot() {
    const phaseStates = runtime?.plan?.phases ? runtime.plan.phases.map(serializePhase) : [];
    const summary = summarizePhaseStates(phaseStates);
    const currentPhase = currentPhaseType
      ? phaseStates.find((phase) => phase.type === currentPhaseType) || null
      : findCurrentPhase(runtime?.plan, lastState);
    const nextPhase = findNextPhase(runtime?.plan, lastState);

    return {
      running,
      speaking,
      currentPhaseType: currentPhase?.type || "",
      nextPhaseType: nextPhase?.type || "",
      planSummary: formatPlanSummary(runtime?.plan) || "",
      cacheSummary: summary.text,
      duckingActive: mixdown.isActive,
      duckingTargetApp: mixdown.isActive ? mixdown.activeSession?.strategy?.label || "" : "",
      mixdownActive: mixdown.isActive,
      mixdownTargetApp: mixdown.isActive ? mixdown.activeSession?.strategy?.label || "" : "",
      mixdownGain: config.ttsPlaybackGain,
      stateSource: lastState?.stateSource || "",
      stateSourceLabel: lastState?.stateSourceLabel || "",
      triggerAtSeconds: nextPhase?.triggerAtSeconds || runtime?.plan?.phases?.[0]?.triggerAtSeconds || config.triggerAtSeconds,
      state: lastState,
      lastScript,
      lastAudioPath,
      phaseStates,
      logs
    };
  }

  function serializePhase(phase) {
    return {
      type: phase.type,
      label: phase.label,
      triggerAtSeconds: phase.triggerAtSeconds,
      anchorAtSeconds: phase.anchorAtSeconds ?? null,
      playAtSeconds: phase.playAtSeconds ?? null,
      audioDurationMs: phase.audioDurationMs ?? null,
      prefetchAtSeconds: phase.prefetchAtSeconds,
      effectivePrefetchAtSeconds: phase.effectivePrefetchAtSeconds ?? phase.prefetchAtSeconds,
      windowEndSeconds: phase.windowEndSeconds,
      moodHint: phase.moodHint,
      scriptStatus: phase.scriptStatus,
      audioStatus: phase.audioStatus,
      playStatus: phase.playStatus,
      scriptPreview: phase.script ? previewText(phase.script, 24) : "",
      scriptLatencyMs: phase.scriptLatencyMs ?? null,
      audioLatencyMs: phase.audioLatencyMs ?? null,
      audioPath: phase.audioPath || "",
      error: phase.error || ""
    };
  }

  function previewText(text, limit) {
    const cleaned = String(text).replace(/\s+/g, " ").trim();
    if (cleaned.length <= limit) return cleaned;
    return `${cleaned.slice(0, limit)}…`;
  }

  function estimateWarmupLeadSeconds(currentRuntime, phase) {
    const scriptMs = phase.scriptStatus === "ready"
      ? phase.scriptLatencyMs
      : currentRuntime.timing?.scriptMsEma;
    const audioMs = phase.audioStatus === "ready"
      ? phase.audioLatencyMs
      : currentRuntime.timing?.audioMsEma;
    const fadeLeadMs = transitionPolicy.duckFadeSteps * transitionPolicy.duckFadeStepDelayMs;
    const scriptLeadMs = Number.isFinite(scriptMs) ? scriptMs : 1500;
    const audioLeadMs = Number.isFinite(audioMs) ? audioMs : 3000;
    const safetyMs = 800;
    const totalSeconds = (scriptLeadMs + audioLeadMs + fadeLeadMs + safetyMs) / 1000;
    return Math.max(transitionPolicy.ttsPrefetchLeadSeconds, totalSeconds);
  }

  function bumpLatencyEstimate(currentRuntime, key, samplesKey, sampleMs) {
    if (!currentRuntime?.timing || !Number.isFinite(sampleMs)) return;
    currentRuntime.timing[samplesKey] += 1;
    const previous = currentRuntime.timing[key];
    const alpha = 0.35;
    currentRuntime.timing[key] = Number.isFinite(previous)
      ? Math.round(previous * (1 - alpha) + sampleMs * alpha)
      : Math.round(sampleMs);
  }

  function logNowPlaying(state) {
    const title = state.title || "(no title)";
    const artist = state.artist || "(unknown artist)";
    const elapsed = formatSeconds(state.elapsed);
    const duration = formatSeconds(state.duration);
    const key = `${state.state}|${state.trackId}|${Math.floor((Number(state.elapsed) || 0) / 5)}`;

    if (key === lastNowPlayingLogKey) return;
    lastNowPlayingLogKey = key;

    const sourceLabel = state.stateSourceLabel || "系统 Now Playing";
    addLog("info", `Now playing: ${artist} - ${title} [${elapsed}/${duration}] state=${state.state} source=${sourceLabel} app=${state.sourceApp || "unknown"}`);
  }

  function hasMeaningfulNowPlayingState(state) {
    if (!state) return false;
    if (String(state.title || "").trim()) return true;
    if (String(state.artist || "").trim()) return true;
    if (String(state.album || "").trim()) return true;
    if (String(state.queueCurrentTitle || "").trim()) return true;
    if (String(state.queueCurrentArtist || "").trim()) return true;
    return false;
  }

  function annotateStateSource(state, stateSource, stateSourceLabel) {
    return {
      ...state,
      stateSource,
      stateSourceLabel
    };
  }

  function addLog(level, message) {
    logs.push({
      time: new Date().toISOString(),
      level,
      message
    });
    logs = logs.slice(-100);
    console.log(`[ai-dj:${level}] ${message}`);
  }

  function formatSeconds(value) {
    const number = Number(value);
    if (!Number.isFinite(number)) return "?";
    const minutes = Math.floor(number / 60);
    const seconds = Math.floor(number % 60).toString().padStart(2, "0");
    return `${minutes}:${seconds}`;
  }
}
