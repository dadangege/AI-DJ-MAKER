import { createTransitionAudioPolicy } from "./transition_audio_policy.mjs";

const PHASE_PRIORITY = {
  pre_outro: 30,
  gap_bridge: 20
};

export class TransitionPlanner {
  constructor(policy = createTransitionAudioPolicy()) {
    this.policy = policy;
  }

  buildPlan(input = {}) {
    const currentState = input.currentState || input.state || input;
    const previousState = input.previousState || null;
    const nextTrack = sanitizeTrack(input.nextTrack || null);

    if (isPlayingState(currentState) && currentState?.title) {
      return this.buildActivePlan({
        currentState,
        previousState,
        nextTrack
      });
    }

    if (previousState?.title) {
      return this.buildGapPlan({
        previousState,
        nextTrack
      });
    }

    return null;
  }

  buildActivePlan({ currentState, previousState = null, nextTrack = null } = {}) {
    const currentTrack = sanitizeTrack(currentState);
    if (!currentTrack.title) {
      return null;
    }

    const phases = [];
    const duration = numberOrNull(currentTrack.duration);
    const elapsed = numberOrNull(currentTrack.elapsed);

    if (Number.isFinite(duration) && duration > 0) {
      const preOutroTriggerAt = clamp(
        Math.round(duration - this.policy.preOutroLeadSeconds),
        Math.max(0, Math.min(8, duration)),
        Math.max(0, duration - 1)
      );

      if (Number.isFinite(preOutroTriggerAt)) {
        phases.push(this.buildPhase({
          type: "pre_outro",
          label: "收尾串场",
          triggerAtSeconds: preOutroTriggerAt,
          anchorAtSeconds: duration,
          prefetchLeadSeconds: this.policy.ttsPrefetchLeadSeconds,
          windowEndSeconds: duration,
          fromTrack: currentTrack,
          toTrack: nextTrack,
          phaseRole: "承接当前歌曲尾声并顺势引出下一首",
          state: currentTrack
        }));
      }
    }

    return {
      planType: "active",
      trackId: currentTrack.trackId,
      currentTrack,
      previousTrack: previousState ? sanitizeTrack(previousState) : null,
      nextTrack,
      elapsed,
      duration,
      phases: sortByTrigger(phases)
    };
  }

  buildGapPlan({ previousState, nextTrack = null } = {}) {
    const previousTrack = sanitizeTrack(previousState);
    if (!previousTrack.title) {
      return null;
    }

    const phase = this.buildPhase({
      type: "gap_bridge",
      label: "切歌串场",
      triggerAtSeconds: 0,
      prefetchLeadSeconds: 0,
      windowEndSeconds: this.policy.gapBridgeGraceSeconds,
      fromTrack: previousTrack,
      toTrack: nextTrack,
      phaseRole: nextTrack?.title
        ? "承接上一首并引出下一首"
        : "承接上一首并维持切歌间隙的连贯感",
      state: previousTrack
    });
    phase.expiresAt = Date.now() + Math.max(1, Math.round(this.policy.gapBridgeGraceSeconds)) * 1000;

    return {
      planType: "gap",
      trackId: `gap|${previousTrack.trackId}`,
      currentTrack: null,
      previousTrack,
      nextTrack,
      elapsed: null,
      duration: null,
      phases: [phase]
    };
  }

  buildPhase({
    type,
    label,
    triggerAtSeconds,
    anchorAtSeconds,
    prefetchLeadSeconds,
    windowEndSeconds,
    fromTrack,
    toTrack,
    phaseRole,
    state
  }) {
    return {
      type,
      label,
      priority: PHASE_PRIORITY[type] || 0,
      triggerAtSeconds: Math.max(0, Math.round(Number(triggerAtSeconds) || 0)),
      anchorAtSeconds: Number.isFinite(Number(anchorAtSeconds)) ? Number(anchorAtSeconds) : Math.max(0, Math.round(Number(triggerAtSeconds) || 0)),
      prefetchAtSeconds: Math.max(0, Math.round(Number(triggerAtSeconds) || 0) - Math.max(0, Math.round(Number(prefetchLeadSeconds) || 0))),
      windowEndSeconds: Math.max(0, Math.round(Number(windowEndSeconds) || 0)),
      fromTrack,
      toTrack,
      phaseRole,
      moodHint: buildMoodHint(type, fromTrack, toTrack, state)
    };
  }
}

export function findCurrentPhase(plan, state) {
  if (!plan || !Array.isArray(plan.phases) || !plan.phases.length) {
    return null;
  }

  const elapsed = numberOrNull(state?.elapsed);
  const isPlaying = isPlayingState(state);
  const now = Date.now();

  const candidates = plan.phases.filter((phase) => {
    if (phase.playStatus === "done") return false;
    if (phase.type === "gap_bridge") {
      if (!isPlaying) {
        return elapsed == null || elapsed <= phase.windowEndSeconds || now <= (phase.expiresAt || now + 1);
      }
      return false;
    }
    if (!Number.isFinite(elapsed)) return false;
    return elapsed >= phase.triggerAtSeconds && elapsed <= phase.windowEndSeconds;
  });

  return candidates.sort((left, right) => {
    const priorityDiff = (right.priority || 0) - (left.priority || 0);
    if (priorityDiff) return priorityDiff;
    return (left.triggerAtSeconds || 0) - (right.triggerAtSeconds || 0);
  })[0] || null;
}

export function findNextPhase(plan, state) {
  if (!plan || !Array.isArray(plan.phases) || !plan.phases.length) {
    return null;
  }

  const elapsed = numberOrNull(state?.elapsed);
  if (!Number.isFinite(elapsed)) {
    return sortByTrigger(plan.phases).find((phase) => phase.playStatus !== "done") || null;
  }

  return sortByTrigger(plan.phases).find((phase) => phase.playStatus !== "done" && elapsed < phase.triggerAtSeconds) || null;
}

export function formatPlanSummary(plan) {
  if (!plan || !Array.isArray(plan.phases) || !plan.phases.length) {
    return "";
  }

  return sortByTrigger(plan.phases)
    .map((phase) => `${phase.label}@${formatSeconds(phase.triggerAtSeconds)}`)
    .join(" · ");
}

export function summarizePhaseStates(phaseStates = []) {
  const total = phaseStates.length;
  const scriptsReady = phaseStates.filter((phase) => phase.scriptStatus === "ready").length;
  const audioReady = phaseStates.filter((phase) => phase.audioStatus === "ready").length;
  const spoken = phaseStates.filter((phase) => phase.playStatus === "done").length;

  return {
    total,
    scriptsReady,
    audioReady,
    spoken,
    text: total
      ? `文案 ${scriptsReady}/${total} · 音频 ${audioReady}/${total} · 已播 ${spoken}/${total}`
      : "暂无阶段计划"
  };
}

function buildMoodHint(type, fromTrack, toTrack, state) {
  const fromLabel = trackLabel(fromTrack);
  const toLabel = trackLabel(toTrack);
  const titleText = `${fromTrack?.title || ""} ${toTrack?.title || ""} ${state?.title || ""}`;

  if (type === "pre_outro") {
    if (toTrack?.title) {
      return `承接《${fromTrack?.title || "当前这首"}》的尾声，顺势引出《${toTrack.title}》`;
    }
    if (/[夜梦风雨月星海静]/.test(titleText)) return "收尾柔和，给下一首留一点余韵";
    if (/[爱心恋情]/.test(titleText)) return "收尾温柔，保留一点心事感";
    if (/[燃热光火奔]/.test(titleText)) return "收尾稳住情绪，顺势把能量递过去";
    return `承接${fromLabel}的尾声，顺势把下一首接上`;
  }

  if (type === "gap_bridge") {
    if (toTrack?.title) {
      return `切歌间隙里承接${fromLabel}，再把《${toTrack.title}》轻轻接上`;
    }
    return `切歌间隙里承接${fromLabel}，保持现场感和连贯感`;
  }

  return "自然、克制、像真人主播在串场";
}

function sortByTrigger(phases) {
  return [...phases].sort((left, right) => (left.triggerAtSeconds || 0) - (right.triggerAtSeconds || 0));
}

function isPlayingState(state) {
  return state?.state === "playing" && Boolean(state?.title);
}

function sanitizeTrack(state) {
  if (!state) return null;

  const title = String(state.title || "");
  const artist = String(state.artist || "");
  const album = String(state.album || "");
  const duration = numberOrNull(state.duration);
  const elapsed = numberOrNull(state.elapsed);
  const playbackRate = numberOrNull(state.playbackRate);
  const sourceApp = String(state.sourceApp || "");

  if (!title && !artist && !album && duration == null && elapsed == null && !sourceApp) {
    return null;
  }

  return {
    title,
    artist,
    album,
    duration,
    elapsed,
    playbackRate,
    sourceApp,
    trackId: state.trackId || buildTrackId({ title, artist, album, duration })
  };
}

function trackLabel(track) {
  if (!track?.title) {
    return "这首歌";
  }
  if (track.artist) {
    return `《${track.title}》`;
  }
  return `《${track.title}》`;
}

function buildTrackId(track) {
  return [
    track.artist || "",
    track.title || "",
    track.album || "",
    track.duration || ""
  ].join("|");
}

function numberOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function formatSeconds(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return "?";
  const minutes = Math.floor(number / 60);
  const seconds = Math.floor(number % 60).toString().padStart(2, "0");
  return `${minutes}:${seconds}`;
}
