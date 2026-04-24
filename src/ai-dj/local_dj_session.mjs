import path from "node:path";

import { config as defaultConfig } from "./config.mjs";
import { generateDjScript } from "./ai_script_generator.mjs";
import { synthesizeDjVoice } from "./tts_service.mjs";
import { createTransitionAudioPolicy } from "./transition_audio_policy.mjs";
import { NeteaseServiceManager } from "./netease_service.mjs";
import { LocalPlayerClient } from "./local_player_client.mjs";

export function createLocalDjSession({
  config = defaultConfig,
  netease = new NeteaseServiceManager(),
  player = new LocalPlayerClient()
} = {}) {
  const policy = createTransitionAudioPolicy(config);
  let queue = [];
  let currentIndex = -1;
  let running = false;
  let speaking = false;
  let loading = false;
  let lastScript = "";
  let lastAudioPath = "";
  let logs = [];
  let transition = null;
  let pollTimer = null;
  let lastPlayerStatus = null;
  let quality = "lossless";

  return {
    setupNetease,
    startNeteaseLogin,
    checkNeteaseLogin,
    loadNeteasePlaylists,
    startNetease,
    stopNetease,
    loadPlaylist,
    play,
    pause,
    next,
    stop,
    snapshot
  };

  async function setupNetease({ cookie = "" } = {}) {
    if (cookie) {
      netease.saveCookie(cookie);
      addLog("info", "网易云 Cookie 已保存到本机用户目录。");
    }
    if (!netease.status.installed) {
      addLog("info", "Netease_url 未安装，开始安装依赖。");
      await netease.install();
    }
    return snapshot();
  }

  async function startNeteaseLogin() {
    const login = await netease.startQrLogin();
    addLog("info", "网易云二维码登录已生成。");
    return {
      ...snapshot(),
      login
    };
  }

  async function checkNeteaseLogin() {
    const login = await netease.checkQrLogin();
    if (login.status === "success") {
      addLog("info", "网易云扫码登录成功。");
    }
    return {
      ...snapshot(),
      login
    };
  }

  async function loadNeteasePlaylists() {
    const result = await netease.userPlaylists();
    addLog("info", `已加载网易云账号歌单：${result.playlists.length} 个。`);
    return {
      ...snapshot(),
      account: {
        userId: result.userId,
        nickname: result.nickname
      },
      playlists: result.playlists
    };
  }

  async function startNetease() {
    const status = await netease.start();
    addLog("info", "Netease_url 服务已启动。");
    return {
      ...snapshot(),
      netease: status
    };
  }

  async function stopNetease() {
    const status = netease.stop();
    addLog("info", "Netease_url 服务已停止。");
    return {
      ...snapshot(),
      netease: status
    };
  }

  async function loadPlaylist({
    playlistId,
    requestedQuality = "lossless",
    limit = 3
  } = {}) {
    const id = String(playlistId || "").trim();
    if (!id) throw new Error("请先扫码登录并在下拉框选择网易云歌单。");
    if (loading) throw new Error("歌单正在加载中，请等当前缓存任务完成。");

    loading = true;
    quality = requestedQuality || quality;
    queue = [];
    currentIndex = -1;
    transition = null;
    addLog("info", `开始加载网易云歌单 ${id}，音质 ${quality}。`);

    try {
      await netease.start();
      const playlist = await netease.playlist(id);
      const tracks = playlist.tracks.slice(0, Math.max(1, Math.min(20, Number(limit) || 3)));
      addLog("info", `歌单返回 ${playlist.tracks.length} 首，准备缓存前 ${tracks.length} 首。`);

      for (const track of tracks) {
        try {
          const localPath = await netease.downloadTrack(track, { quality });
          queue.push({
            ...track,
            localPath,
            trackId: `netease|${track.id}|${quality}`,
            sourceApp: "local-dj"
          });
          addLog("info", `已缓存：${track.artist || "未知歌手"} - ${track.title} -> ${path.basename(localPath)}`);
        } catch (error) {
          addLog("warn", `跳过下载失败歌曲：${track.artist || "未知歌手"} - ${track.title || track.id}，${error.message}`);
        }
      }

      if (!queue.length) throw new Error("没有可播放的歌曲缓存成功。");
      currentIndex = 0;
      await loadCurrent({ autoplay: false });
      primeTransition();
      return snapshot();
    } finally {
      loading = false;
    }
  }

  async function play() {
    if (!queue.length) throw new Error("请先加载歌单。");
    if (currentIndex < 0) currentIndex = 0;
    await loadCurrent({ autoplay: false });
    await player.play();
    running = true;
    startPolling();
    addLog("info", "自建播放器已开始播放。");
    primeTransition();
    return snapshot();
  }

  async function pause() {
    await player.pause();
    running = false;
    addLog("info", "自建播放器已暂停。");
    return snapshot();
  }

  async function stop() {
    stopPolling();
    await player.stop().catch(() => undefined);
    running = false;
    speaking = false;
    transition = null;
    addLog("info", "自建播放器已停止。");
    return snapshot();
  }

  async function next() {
    if (!queue.length) throw new Error("队列为空。");
    currentIndex = Math.min(queue.length - 1, currentIndex + 1);
    transition = null;
    await loadCurrent({ autoplay: running });
    primeTransition();
    addLog("info", `切到下一首：${currentTrackLabel()}`);
    return snapshot();
  }

  async function loadCurrent({ autoplay = false } = {}) {
    const track = queue[currentIndex];
    if (!track) return;
    await player.loadMusic(track, {
      autoplay,
      volume: speaking || lastPlayerStatus?.ttsPlaying ? normalizedDuckVolume() : 1
    });
  }

  function startPolling() {
    if (pollTimer) return;
    pollTimer = setInterval(() => {
      void tick().catch((error) => addLog("error", `自建播放器状态更新失败：${error.message}`));
    }, 500);
  }

  function stopPolling() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  async function tick() {
    lastPlayerStatus = await player.status();
    const status = lastPlayerStatus || {};
    const track = queue[currentIndex];
    if (!track) return;

    if (!transition) {
      primeTransition();
    }

    await maybePlayTransition(status);

    const duration = Number(status.duration || track.duration);
    const elapsed = Number(status.elapsed);
    const ended = Number.isFinite(duration) && duration > 0 && Number.isFinite(elapsed) && elapsed >= duration - 0.2;
    if (running && ended && currentIndex < queue.length - 1) {
      await next();
    }
  }

  function primeTransition() {
    const current = queue[currentIndex];
    const nextTrack = queue[currentIndex + 1] || null;
    if (!current || !nextTrack) return;
    if (transition?.fromTrack?.trackId === current.trackId && transition?.toTrack?.trackId === nextTrack.trackId) return;

    transition = {
      fromTrack: current,
      toTrack: nextTrack,
      scriptStatus: "idle",
      audioStatus: "idle",
      playStatus: "idle",
      script: "",
      audioPath: "",
      audioDurationMs: null,
      playAtSeconds: null,
      error: "",
      promise: null
    };
    addLog("info", `提前准备串场：${current.title} -> ${nextTrack.title}`);
    void ensureTransitionAudio();
  }

  async function ensureTransitionAudio() {
    if (!transition) return null;
    if (transition.audioStatus === "ready") return transition;
    if (transition.promise) return transition.promise;

    transition.promise = (async () => {
      try {
        transition.scriptStatus = "pending";
        const currentState = trackToState(transition.fromTrack);
        const nextTrack = trackToState(transition.toTrack);
        const script = await generateDjScript({
          currentState,
          previousState: null,
          nextTrack,
          bridgeFromTrack: currentState,
          bridgeToTrack: nextTrack,
          phaseType: "pre_outro",
          phaseRole: "承接上一首尾声并引出下一首"
        }, {
          model: config.textModel,
          triggerType: "pre_outro"
        });
        transition.script = script;
        transition.scriptStatus = "ready";
        lastScript = script;
        addLog("script", `自建串场文案已缓存：${script}`);

        transition.audioStatus = "pending";
        const audio = await synthesizeDjVoice(script, config);
        transition.audioPath = audio.path;
        transition.audioDurationMs = Number(audio.durationMs) || null;
        transition.audioStatus = "ready";
        lastAudioPath = audio.path;

        const duration = Number(transition.fromTrack.duration);
        const halfTts = Number.isFinite(transition.audioDurationMs) ? transition.audioDurationMs / 2000 : 4;
        const fadeLead = (policy.duckFadeSteps * policy.duckFadeStepDelayMs) / 1000;
        transition.playAtSeconds = Number.isFinite(duration) && duration > 0
          ? Math.max(0, duration - halfTts - fadeLead)
          : 0;
        addLog("tts", `自建串场音频已缓存：${path.basename(audio.path)}，播放点 ${formatSeconds(transition.playAtSeconds)}。`);
        return transition;
      } catch (error) {
        transition.error = error.message;
        transition.audioStatus = "error";
        transition.scriptStatus = transition.script ? "ready" : "error";
        addLog("error", `自建串场准备失败：${error.message}`);
        return null;
      } finally {
        if (transition) transition.promise = null;
      }
    })();

    return transition.promise;
  }

  async function maybePlayTransition(status) {
    if (!transition || transition.playStatus !== "idle" || speaking) return;
    const ready = await ensureTransitionAudio();
    if (!ready || transition.audioStatus !== "ready") return;

    const elapsed = Number(status.elapsed);
    if (!Number.isFinite(elapsed) || elapsed < Number(transition.playAtSeconds || 0)) return;

    transition.playStatus = "playing";
    speaking = true;
    addLog("info", `开始播放自建串场：${transition.fromTrack.title} -> ${transition.toTrack.title}`);
    try {
      await player.playTts(transition.audioPath, {
        duckVolume: normalizedDuckVolume(),
        fadeMs: policy.duckFadeSteps * policy.duckFadeStepDelayMs,
        ttsGain: config.ttsPlaybackGain
      });
      transition.playStatus = "done";
    } catch (error) {
      transition.playStatus = "error";
      transition.error = error.message;
      addLog("error", `自建串场播放失败：${error.message}`);
    } finally {
      speaking = false;
    }
  }

  function snapshot() {
    const currentTrack = queue[currentIndex] || null;
    const nextTrack = queue[currentIndex + 1] || null;
    const playerStatus = lastPlayerStatus || {};
    return {
      running,
      loading,
      speaking,
      quality,
      queueCount: queue.length,
      currentIndex,
      currentTrack,
      nextTrack,
      elapsed: playerStatus.elapsed ?? 0,
      duration: playerStatus.duration ?? currentTrack?.duration ?? 0,
      playing: Boolean(playerStatus.playing),
      musicVolume: playerStatus.musicVolume ?? 1,
      ttsPlaying: Boolean(playerStatus.ttsPlaying),
      transition: serializeTransition(),
      lastScript,
      lastAudioPath,
      player: playerStatus,
      netease: netease.status,
      login: netease.status.login,
      logs
    };
  }

  function serializeTransition() {
    if (!transition) return null;
    return {
      fromTitle: transition.fromTrack?.title || "",
      toTitle: transition.toTrack?.title || "",
      scriptStatus: transition.scriptStatus,
      audioStatus: transition.audioStatus,
      playStatus: transition.playStatus,
      playAtSeconds: transition.playAtSeconds,
      audioDurationMs: transition.audioDurationMs,
      error: transition.error,
      scriptPreview: transition.script ? `${transition.script.slice(0, 40)}${transition.script.length > 40 ? "..." : ""}` : ""
    };
  }

  function trackToState(track) {
    return {
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration,
      elapsed: 0,
      state: "playing",
      playbackRate: 1,
      sourceApp: "local-dj",
      trackId: track.trackId
    };
  }

  function normalizedDuckVolume() {
    return Math.max(0, Math.min(1, Number(policy.duckVolume) / 100));
  }

  function currentTrackLabel() {
    const track = queue[currentIndex];
    return track ? `${track.artist || "未知歌手"} - ${track.title}` : "无";
  }

  function addLog(level, message) {
    logs.push({
      time: new Date().toISOString(),
      level,
      message
    });
    logs = logs.slice(-100);
    console.log(`[local-dj:${level}] ${message}`);
  }

  function formatSeconds(value) {
    const number = Number(value);
    if (!Number.isFinite(number)) return "?";
    const minutes = Math.floor(number / 60);
    const seconds = Math.floor(number % 60).toString().padStart(2, "0");
    return `${minutes}:${seconds}`;
  }
}
