const $ = (selector) => document.querySelector(selector);

const controls = {
  text: $("#text"),
  apiKey: $("#apiKey"),
  baseUrl: $("#baseUrl"),
  textModel: $("#textModel"),
  ttsModel: $("#ttsModel"),
  saveSettings: $("#saveSettings"),
  settingsStatus: $("#settingsStatus"),
  preset: $("#preset"),
  model: $("#model"),
  voiceGroup: $("#voiceGroup"),
  voiceList: $("#voiceList"),
  voiceSearch: $("#voiceSearch"),
  voiceMeta: $("#voiceMeta"),
  format: $("#format"),
  speed: $("#speed"),
  pitch: $("#pitch"),
  vol: $("#vol"),
  speedValue: $("#speedValue"),
  pitchValue: $("#pitchValue"),
  volValue: $("#volValue"),
  synthesize: $("#synthesize"),
  stopServer: $("#stopServer"),
  status: $("#status"),
  player: $("#player"),
  aiDjStart: $("#aiDjStart"),
  aiDjStop: $("#aiDjStop"),
  aiDjRefresh: $("#aiDjRefresh"),
  aiDjTest: $("#aiDjTest"),
  aiDjRunning: $("#aiDjRunning"),
  aiDjPlayback: $("#aiDjPlayback"),
  aiDjSource: $("#aiDjSource"),
  aiDjPhase: $("#aiDjPhase"),
  aiDjNext: $("#aiDjNext"),
  aiDjCache: $("#aiDjCache"),
  aiDjDucking: $("#aiDjDucking"),
  aiDjSpeaking: $("#aiDjSpeaking"),
  aiDjTrack: $("#aiDjTrack"),
  aiDjMeta: $("#aiDjMeta"),
  aiDjProgress: $("#aiDjProgress"),
  aiDjProgressText: $("#aiDjProgressText"),
  aiDjScript: $("#aiDjScript"),
  aiDjLogs: $("#aiDjLogs"),
  localDjPlaylistSelect: $("#localDjPlaylistSelect"),
  localDjLogin: $("#localDjLogin"),
  localDjRefreshPlaylists: $("#localDjRefreshPlaylists"),
  localDjQr: $("#localDjQr"),
  localDjLoginStatus: $("#localDjLoginStatus"),
  localDjQuality: $("#localDjQuality"),
  localDjLimit: $("#localDjLimit"),
  localDjStartNetease: $("#localDjStartNetease"),
  localDjLoad: $("#localDjLoad"),
  localDjPlay: $("#localDjPlay"),
  localDjPause: $("#localDjPause"),
  localDjNext: $("#localDjNext"),
  localDjService: $("#localDjService"),
  localDjPlayback: $("#localDjPlayback"),
  localDjQueue: $("#localDjQueue"),
  localDjMix: $("#localDjMix"),
  localDjTrack: $("#localDjTrack"),
  localDjMeta: $("#localDjMeta"),
  localDjProgress: $("#localDjProgress"),
  localDjProgressText: $("#localDjProgressText"),
  localDjTransition: $("#localDjTransition"),
  localDjLogs: $("#localDjLogs")
};

const GROUP_LABELS = {
  radio: "电台推荐",
  emotion: "情感播客",
  girl: "少女",
  male: "男声",
  news: "资讯"
};

const GROUP_ORDER = ["radio", "emotion", "girl", "male", "news"];

const presetValues = {
  radio: { speed: 0.92, pitch: -1, vol: 2, voice: "Chinese (Mandarin)_Gentle_Senior" },
  story: { speed: 0.86, pitch: -2, vol: 2, voice: "Chinese (Mandarin)_Gentle_Senior" },
  news: { speed: 1, pitch: 0, vol: 2, voice: "Chinese (Mandarin)_Gentle_Senior" }
};

let voiceGroups = createEmptyGroups();
let selectedVoiceGroup = "radio";
let selectedVoiceId = "";
let apiSettings = null;
let localDjLoginPoll = null;
let localDjPlaylistCache = [];
let localDjPlaylistsLoading = false;
let localDjTriedAutoLoadPlaylists = false;

for (const input of [controls.speed, controls.pitch, controls.vol]) {
  input.addEventListener("input", updateNumbers);
}

controls.voiceGroup.addEventListener("click", (event) => {
  const button = event.target.closest("[data-group]");
  if (!button) return;
  selectedVoiceGroup = button.dataset.group;
  renderVoiceTabs();
  renderVoiceList();
});

controls.voiceSearch.addEventListener("input", () => {
  renderVoiceList();
});

controls.preset.addEventListener("change", () => {
  const preset = presetValues[controls.preset.value] || presetValues.radio;
  controls.speed.value = preset.speed;
  controls.pitch.value = preset.pitch;
  controls.vol.value = preset.vol;
  setVoice(preset.voice, true);
  updateNumbers();
});

controls.saveSettings.addEventListener("click", async () => {
  controls.saveSettings.disabled = true;
  controls.settingsStatus.textContent = "正在保存配置...";

  try {
    const payload = {
      baseUrl: controls.baseUrl.value,
      textModel: controls.textModel.value,
      ttsModel: controls.ttsModel.value,
      voiceId: selectedVoiceId || presetValues[controls.preset.value]?.voice || ""
    };
    if (controls.apiKey.value.trim()) {
      payload.apiKey = controls.apiKey.value.trim();
    }

    const response = await fetch("/api/settings", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
    const settings = await response.json();
    if (!response.ok) {
      throw new Error(settings.error || "配置保存失败。");
    }
    applySettings(settings);
    controls.apiKey.value = "";
    controls.settingsStatus.textContent = `配置已保存 · Key ${settings.maskedApiKey || "未填写"} · ${settings.baseUrl}`;
    await loadChineseVoices();
  } catch (error) {
    controls.settingsStatus.textContent = error.message || String(error);
  } finally {
    controls.saveSettings.disabled = false;
  }
});

controls.player.loop = false;
controls.player.preload = "none";
controls.player.addEventListener("ended", () => {
  controls.player.pause();
  controls.player.removeAttribute("src");
  controls.player.load();
});

controls.synthesize.addEventListener("click", async () => {
  controls.synthesize.disabled = true;
  setStatus("合成中，MiniMax 正在生成音频...");

  try {
    const response = await fetch("/api/tts", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        text: controls.text.value,
        preset: controls.preset.value,
        model: controls.ttsModel.value || controls.model.value,
        voice: selectedVoiceId,
        format: controls.format.value,
        speed: Number(controls.speed.value),
        pitch: Number(controls.pitch.value),
        vol: Number(controls.vol.value)
      })
    });

    const result = await response.json();
    if (!response.ok || !result.ok) {
      throw new Error(result.error || "合成失败。");
    }

    controls.player.pause();
    controls.player.removeAttribute("src");
    controls.player.load();
    controls.player.src = `${result.url}?t=${Date.now()}`;
    await controls.player.play().catch(() => undefined);
    const seconds = result.durationMs ? `${(result.durationMs / 1000).toFixed(1)}s` : "未知时长";
    setStatus(`合成完成：${seconds}，${formatBytes(result.bytes)}。`);
  } catch (error) {
    setStatus(error.message || String(error), true);
  } finally {
    controls.synthesize.disabled = false;
  }
});

controls.stopServer.addEventListener("click", async () => {
  setStatus("正在退出本地服务...");
  await fetch("/api/quit", { method: "POST" }).catch(() => undefined);
  setStatus("本地服务已退出，可以关闭这个窗口。");
});

controls.aiDjStart.addEventListener("click", async () => {
  controls.aiDjStart.disabled = true;
  controls.aiDjStart.textContent = "启动中...";
  appendLocalAiDjLog("正在请求启动 AI DJ...");
  await postAiDj("/api/ai-dj/start");
  controls.aiDjStart.disabled = false;
});

controls.aiDjStop.addEventListener("click", async () => {
  controls.aiDjStop.disabled = true;
  appendLocalAiDjLog("正在停止 AI DJ...");
  await postAiDj("/api/ai-dj/stop");
  controls.aiDjStop.disabled = false;
});

controls.aiDjRefresh.addEventListener("click", async () => {
  appendLocalAiDjLog("正在刷新 AI DJ 状态...");
  await refreshAiDjStatus();
});

controls.aiDjTest.addEventListener("click", async () => {
  controls.aiDjTest.disabled = true;
  appendLocalAiDjLog("正在触发一次测试口播...");
  await postAiDj("/api/ai-dj/test");
  controls.aiDjTest.disabled = false;
});

controls.localDjLogin.addEventListener("click", async () => {
  controls.localDjLogin.disabled = true;
  appendLocalDjLog("正在生成网易云扫码登录二维码...");
  const status = await postLocalDj("/api/local-dj/netease/login/start");
  if (status?.login) {
    renderNeteaseLogin(status.login, status);
    startLocalDjLoginPolling();
  }
  controls.localDjLogin.disabled = false;
});

controls.localDjRefreshPlaylists.addEventListener("click", async () => {
  controls.localDjRefreshPlaylists.disabled = true;
  appendLocalDjLog("正在读取网易云歌单...");
  await loadLocalDjPlaylists();
  controls.localDjRefreshPlaylists.disabled = false;
});

controls.localDjStartNetease.addEventListener("click", async () => {
  controls.localDjStartNetease.disabled = true;
  appendLocalDjLog("正在启动 Netease_url 服务...");
  await postLocalDj("/api/local-dj/netease/start");
  controls.localDjStartNetease.disabled = false;
});

controls.localDjLoad.addEventListener("click", async () => {
  controls.localDjLoad.disabled = true;
  appendLocalDjLog("正在加载并缓存歌单...");
  await postLocalDj("/api/local-dj/playlist/load", {
    playlistId: controls.localDjPlaylistSelect.value,
    quality: controls.localDjQuality.value,
    limit: Number(controls.localDjLimit.value)
  });
  controls.localDjLoad.disabled = false;
});

controls.localDjPlay.addEventListener("click", async () => {
  await postLocalDj("/api/local-dj/play");
});

controls.localDjPause.addEventListener("click", async () => {
  await postLocalDj("/api/local-dj/pause");
});

controls.localDjNext.addEventListener("click", async () => {
  await postLocalDj("/api/local-dj/next");
});

loadSettings();
loadChineseVoices();
renderVoiceTabs();
refreshAiDjStatus();
refreshLocalDjStatus();
setInterval(refreshAiDjStatus, 1000);
setInterval(refreshLocalDjStatus, 1000);

function createEmptyGroups() {
  return {
    radio: [],
    emotion: [],
    girl: [],
    male: [],
    news: []
  };
}

function updateNumbers() {
  controls.speedValue.textContent = controls.speed.value;
  controls.pitchValue.textContent = controls.pitch.value;
  controls.volValue.textContent = controls.vol.value;
}

async function loadChineseVoices() {
  try {
    const response = await fetch("/api/voices");
    const data = await response.json();

    if (!response.ok || !Array.isArray(data.voices) || !data.groups) {
      throw new Error(data.error || "音色列表加载失败。");
    }

    voiceGroups = normalizeGroups(data.groups);

    const presetVoice = presetValues[controls.preset.value]?.voice;
    const firstVoice = findFirstVoice();
    const initialVoice = findVoice(presetVoice) || firstVoice;
    selectedVoiceGroup = initialVoice ? initialVoice.group : "radio";
    selectedVoiceId = initialVoice ? initialVoice.voice_id : "";

    renderVoiceTabs();
    renderVoiceList();

    if (initialVoice) {
      setVoice(initialVoice.voice_id, false);
    }

    setStatus(`已加载 ${countVoices()} 个中文音色。`);
  } catch (error) {
    setStatus(error.message || String(error), true);
    controls.voiceMeta.textContent = "中文音色加载失败，请检查 API Key、Base URL 或 MiniMax 接口。";
    controls.voiceList.innerHTML = "";
  }
}

async function loadSettings() {
  try {
    const response = await fetch("/api/settings");
    const settings = await response.json();
    if (!response.ok) {
      throw new Error(settings.error || "配置读取失败。");
    }
    applySettings(settings);
  } catch (error) {
    controls.settingsStatus.textContent = error.message || String(error);
  }
}

function applySettings(settings) {
  apiSettings = settings;
  controls.baseUrl.value = settings.baseUrl || "https://api.minimaxi.com/v1";
  controls.textModel.value = settings.textModel || "MiniMax-M2.7-highspeed";
  controls.ttsModel.value = settings.ttsModel || "speech-2.8-hd";
  controls.apiKey.placeholder = settings.hasApiKey ? `${settings.maskedApiKey} · 留空表示继续使用` : "sk-...";
  controls.settingsStatus.textContent = settings.hasApiKey
    ? `已配置 · Key ${settings.maskedApiKey} · ${settings.baseUrl}`
    : "未配置 API Key，TTS 和 AI 文案会不可用或使用兜底文案。";
  if (settings.voiceId) {
    presetValues.radio.voice = settings.voiceId;
    presetValues.story.voice = settings.voiceId;
    presetValues.news.voice = settings.voiceId;
    setVoice(settings.voiceId, true);
  }
}

function normalizeGroups(groups) {
  const normalized = createEmptyGroups();
  for (const group of GROUP_ORDER) {
    const voices = Array.isArray(groups[group]) ? groups[group] : [];
    normalized[group] = voices.slice().sort((left, right) => left.voice_name.localeCompare(right.voice_name, "zh-Hans-CN"));
  }
  return normalized;
}

function renderVoiceTabs() {
  controls.voiceGroup.innerHTML = GROUP_ORDER.map((group) => {
    const active = group === selectedVoiceGroup ? " active" : "";
    return `<button type="button" class="group-tab${active}" data-group="${group}">${GROUP_LABELS[group]} (${voiceGroups[group].length})</button>`;
  }).join("");
}

function renderVoiceList() {
  const keyword = controls.voiceSearch.value.trim().toLowerCase();
  const voices = voiceGroups[selectedVoiceGroup] || [];

  const filtered = keyword
    ? voices.filter((voice) => `${voice.voice_name} ${voice.voice_id}`.toLowerCase().includes(keyword))
    : voices;

  if (!filtered.length) {
    controls.voiceList.innerHTML = '<div class="voice-empty">没有匹配的中文音色</div>';
    updateVoiceMeta(null, 0);
    return;
  }

  controls.voiceList.innerHTML = filtered.map((voice) => {
    const active = voice.voice_id === selectedVoiceId ? " active" : "";
    return `
      <button type="button" class="voice-item${active}" data-voice="${escapeHtml(voice.voice_id)}">
        <span class="voice-item-name">${escapeHtml(voice.voice_name)}</span>
        <span class="voice-item-id">${escapeHtml(voice.voice_id)}</span>
      </button>
    `;
  }).join("");

  controls.voiceList.querySelectorAll("[data-voice]").forEach((button) => {
    button.addEventListener("click", () => {
      setVoice(button.dataset.voice, true);
    });
  });

  updateVoiceMeta(findVoice(selectedVoiceId), filtered.length);
}

function setVoice(voiceId, syncGroup = false) {
  const voice = findVoice(voiceId);
  if (!voice) return;

  selectedVoiceId = voice.voice_id;
  if (syncGroup) {
    selectedVoiceGroup = voice.group || "emotion";
    renderVoiceTabs();
  }
  renderVoiceList();
}

function findVoice(voiceId) {
  for (const group of GROUP_ORDER) {
    const found = (voiceGroups[group] || []).find((voice) => voice.voice_id === voiceId);
    if (found) return found;
  }
  return null;
}

function findFirstVoice() {
  for (const group of GROUP_ORDER) {
    const voice = (voiceGroups[group] || [])[0];
    if (voice) return voice;
  }
  return null;
}

function countVoices() {
  return GROUP_ORDER.reduce((sum, group) => sum + (voiceGroups[group]?.length || 0), 0);
}

function updateVoiceMeta(voice = null, filteredCount = null) {
  const current = voice || findVoice(selectedVoiceId);
  if (!current) {
    controls.voiceMeta.textContent = `当前分组：${GROUP_LABELS[selectedVoiceGroup]}，请选择一个中文音色。`;
    return;
  }

  const countInfo = filteredCount === null ? "" : ` · 当前 ${filteredCount} 个音色`;
  controls.voiceMeta.textContent = `当前分组：${GROUP_LABELS[selectedVoiceGroup]}${countInfo} · ${current.voice_name} · ${current.voice_id}`;
}

async function postAiDj(url) {
  try {
    const response = await fetch(url, { method: "POST" });
    const status = await response.json();
    renderAiDjStatus(status);
  } catch (error) {
    renderAiDjError(error);
  }
}

async function postLocalDj(url, payload = null) {
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: payload ? { "Content-Type": "application/json" } : undefined,
      body: payload ? JSON.stringify(payload) : undefined
    });
    const status = await response.json();
    if (!response.ok) {
      throw new Error(status.error || "自建播放器请求失败。");
    }
    renderLocalDjStatus(status);
    return status;
  } catch (error) {
    renderLocalDjError(error);
    return null;
  }
}

async function getLocalDj(url) {
  try {
    const response = await fetch(url);
    const status = await response.json();
    if (!response.ok) {
      throw new Error(status.error || "自建播放器请求失败。");
    }
    renderLocalDjStatus(status);
    return status;
  } catch (error) {
    renderLocalDjError(error);
    return null;
  }
}

async function refreshAiDjStatus() {
  try {
    const response = await fetch("/api/ai-dj/status");
    const status = await response.json();
    renderAiDjStatus(status);
  } catch (error) {
    renderAiDjError(error);
  }
}

async function refreshLocalDjStatus() {
  try {
    const response = await fetch("/api/local-dj/status");
    const status = await response.json();
    renderLocalDjStatus(status);
  } catch (error) {
    renderLocalDjError(error);
  }
}

function startLocalDjLoginPolling() {
  stopLocalDjLoginPolling();
  localDjLoginPoll = setInterval(() => {
    void pollNeteaseLogin();
  }, 2000);
}

function stopLocalDjLoginPolling() {
  if (localDjLoginPoll) {
    clearInterval(localDjLoginPoll);
    localDjLoginPoll = null;
  }
}

async function pollNeteaseLogin() {
  const status = await postLocalDj("/api/local-dj/netease/login/status");
  const login = status?.login;
  if (!login) return;
  renderNeteaseLogin(login, status);

  if (login.status === "success") {
    stopLocalDjLoginPolling();
    localDjTriedAutoLoadPlaylists = false;
    appendLocalDjLog("网易云登录成功，正在读取歌单...");
    await loadLocalDjPlaylists();
    return;
  }

  if (["expired", "error"].includes(login.status)) {
    stopLocalDjLoginPolling();
  }
}

async function loadLocalDjPlaylists() {
  if (localDjPlaylistsLoading) return null;
  localDjPlaylistsLoading = true;
  const status = await getLocalDj("/api/local-dj/netease/playlists");
  if (Array.isArray(status?.playlists)) {
    renderLocalDjPlaylists(status.playlists);
  }
  localDjPlaylistsLoading = false;
  return status;
}

function renderAiDjStatus(status) {
  const state = status.state || {};
  const elapsed = Number(state.elapsed);
  const duration = Number(state.duration);
  const hasDuration = Number.isFinite(duration) && duration > 0;
  const percent = hasDuration && Number.isFinite(elapsed) ? Math.min(100, Math.max(0, (elapsed / duration) * 100)) : 0;
  const phaseStates = Array.isArray(status.phaseStates) ? status.phaseStates : [];
  const currentPhase = phaseStates.find((phase) => phase.type === status.currentPhaseType) || null;
  const nextPhase = phaseStates.find((phase) => phase.type === status.nextPhaseType) || null;

  controls.aiDjRunning.textContent = status.running ? "运行中" : "未启动";
  controls.aiDjStart.textContent = status.running ? "AI DJ 已运行" : "启动 AI DJ";
  controls.aiDjStart.disabled = Boolean(status.running);
  controls.aiDjPlayback.textContent = state.state || "unknown";
  controls.aiDjSource.textContent = formatStateSource(state, status);
  controls.aiDjPhase.textContent = currentPhase ? `${currentPhase.label || currentPhase.type} · ${formatPhaseStatus(currentPhase)}` : "idle";
  controls.aiDjNext.textContent = nextPhase
    ? `${nextPhase.label || nextPhase.type} @ ${formatPhaseTime(nextPhase.playAtSeconds ?? nextPhase.triggerAtSeconds)}`
    : "暂无下一阶段";
  controls.aiDjCache.textContent = status.cacheSummary || "文案 0/0 · 音频 0/0 · 已播 0/0";
  controls.aiDjDucking.textContent = status.duckingActive
    ? `active · ${status.mixdownTargetApp || status.duckingTargetApp || "unknown"} · gain ${Number(status.mixdownGain || 0).toFixed(2)}`
    : "idle";
  controls.aiDjSpeaking.textContent = status.speaking ? "口播中" : "idle";
  controls.aiDjTrack.textContent = state.title ? `${state.artist || "未知歌手"} - ${state.title}` : "等待系统 Now Playing...";
  controls.aiDjMeta.textContent = [
    state.album ? `专辑：${state.album}` : "",
    state.sourceApp ? `来源：${state.sourceApp}` : "",
    state.stateSourceLabel ? `数据源：${state.stateSourceLabel}` : "",
    state.progressReliable === false ? "进度：缓存估算，不支持暂停/拖动识别" : "",
    state.fallback ? `fallback：${state.fallback}` : "",
    nextPhase?.anchorAtSeconds ? `对齐：歌曲结束 ${formatPhaseTime(nextPhase.anchorAtSeconds)}` : "",
    nextPhase?.audioDurationMs ? `口播：${(Number(nextPhase.audioDurationMs) / 1000).toFixed(1)}s` : "",
    status.planSummary ? `计划：${status.planSummary}` : ""
  ].filter(Boolean).join(" · ") || "没有读取到歌曲信息时，请确认播放器支持 macOS 系统 Now Playing。";
  controls.aiDjProgress.style.width = `${percent}%`;
  controls.aiDjProgressText.textContent = `${formatTime(elapsed)} / ${hasDuration ? formatTime(duration) : "?"}`;
  controls.aiDjScript.textContent = status.lastScript || "还没有触发口播。";
  controls.aiDjLogs.innerHTML = (status.logs || []).slice(-12).reverse().map((entry) => {
    return `<div class="log-line ${escapeHtml(entry.level || "info")}"><time>${escapeHtml(formatClock(entry.time))}</time><span>${escapeHtml(entry.message || "")}</span></div>`;
  }).join("");
}

function renderNeteaseLogin(login = null, status = {}) {
  const hasCookie = Boolean(status.netease?.hasCookie || login?.hasCookie);
  const activeLogin = login?.url && ["waiting", "scanned"].includes(login.status);
  const message = activeLogin
    ? login.message
    : hasCookie ? "已保存登录态，启动后会自动读取歌单。" : "点击“扫码登录网易云”生成二维码。";

  controls.localDjLoginStatus.textContent = message;
  controls.localDjLogin.textContent = hasCookie && !activeLogin ? "重新扫码登录" : "扫码登录网易云";

  if (activeLogin) {
    const qrUrl = `https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=${encodeURIComponent(login.url)}`;
    controls.localDjQr.innerHTML = `
      <img src="${escapeHtml(qrUrl)}" alt="网易云扫码登录二维码">
      <a href="${escapeHtml(login.url)}" target="_blank" rel="noreferrer">二维码打不开时点这里</a>
    `;
    return;
  }

  if (login?.status === "success" || hasCookie) {
    controls.localDjQr.textContent = localDjPlaylistCache.length
      ? `已登录，已读取 ${localDjPlaylistCache.length} 个歌单。`
      : "已登录，正在读取你的网易云歌单。";
    return;
  }

  if (login?.status === "expired") {
    controls.localDjQr.textContent = "二维码已过期，请重新生成。";
    return;
  }

  if (login?.status === "error") {
    controls.localDjQr.textContent = login.message || "登录失败，请重新生成二维码。";
    return;
  }

  controls.localDjQr.textContent = "点击“扫码登录网易云”生成二维码。";
}

function renderLocalDjPlaylists(playlists = []) {
  localDjPlaylistCache = Array.isArray(playlists) ? playlists : [];
  const selected = controls.localDjPlaylistSelect.value;

  if (!localDjPlaylistCache.length) {
    controls.localDjPlaylistSelect.innerHTML = '<option value="">没有读取到歌单</option>';
    return;
  }

  controls.localDjPlaylistSelect.innerHTML = localDjPlaylistCache.map((playlist) => {
    const label = `${playlist.name}${playlist.trackCount ? ` (${playlist.trackCount} 首)` : ""}`;
    const isSelected = playlist.id === selected ? " selected" : "";
    return `<option value="${escapeHtml(playlist.id)}"${isSelected}>${escapeHtml(label)}</option>`;
  }).join("");
}

function renderLocalDjStatus(status) {
  const current = status.currentTrack || {};
  const next = status.nextTrack || {};
  const elapsed = Number(status.elapsed);
  const duration = Number(status.duration);
  const hasDuration = Number.isFinite(duration) && duration > 0;
  const percent = hasDuration && Number.isFinite(elapsed) ? Math.min(100, Math.max(0, (elapsed / duration) * 100)) : 0;
  const transition = status.transition || null;

  renderNeteaseLogin(status.login || status.netease?.login, status);
  if (Array.isArray(status.playlists)) {
    renderLocalDjPlaylists(status.playlists);
  }
  if (status.netease?.hasCookie && !localDjPlaylistCache.length && !localDjPlaylistsLoading && !localDjTriedAutoLoadPlaylists) {
    localDjTriedAutoLoadPlaylists = true;
    void loadLocalDjPlaylists();
  }

  controls.localDjService.textContent = status.netease?.running
    ? "Netease_url 运行中"
    : status.netease?.installed ? "已安装，未启动" : "未安装";
  controls.localDjPlayback.textContent = status.playing ? "播放中" : status.loading ? "加载中" : "idle";
  controls.localDjQueue.textContent = `${status.queueCount || 0} 首 · ${Number(status.currentIndex || 0) + 1}/${Math.max(1, status.queueCount || 0)}`;
  controls.localDjMix.textContent = status.ttsPlaying
    ? `TTS 中 · music ${(Number(status.musicVolume || 0) * 100).toFixed(0)}%`
    : `music ${(Number(status.musicVolume ?? 1) * 100).toFixed(0)}%`;
  controls.localDjTrack.textContent = current.title
    ? `${current.artist || "未知歌手"} - ${current.title}`
    : "等待加载网易云歌单...";
  controls.localDjMeta.textContent = [
    next.title ? `下一首：${next.artist || "未知歌手"} - ${next.title}` : "暂无下一首",
    current.localPath ? `缓存：${current.localPath.split("/").pop()}` : "",
    status.netease?.hasCookie ? "网易云：已登录" : "网易云：未登录",
    status.netease?.baseUrl ? `服务：${status.netease.baseUrl}` : ""
  ].filter(Boolean).join(" · ");
  controls.localDjProgress.style.width = `${percent}%`;
  controls.localDjProgressText.textContent = `${formatTime(elapsed)} / ${hasDuration ? formatTime(duration) : "?"}`;
  controls.localDjTransition.textContent = transition
    ? [
        `${transition.fromTitle || "当前歌"} -> ${transition.toTitle || "下一首"}`,
        `文案 ${transition.scriptStatus}`,
        `音频 ${transition.audioStatus}`,
        `播放 ${transition.playStatus}`,
        Number.isFinite(Number(transition.playAtSeconds)) ? `@ ${formatTime(transition.playAtSeconds)}` : "",
        transition.audioDurationMs ? `口播 ${(Number(transition.audioDurationMs) / 1000).toFixed(1)}s` : "",
        transition.error ? `错误：${transition.error}` : ""
      ].filter(Boolean).join(" · ")
    : "还没有串场计划。";
  controls.localDjLogs.innerHTML = (status.logs || []).slice(-12).reverse().map((entry) => {
    return `<div class="log-line ${escapeHtml(entry.level || "info")}"><time>${escapeHtml(formatClock(entry.time))}</time><span>${escapeHtml(entry.message || "")}</span></div>`;
  }).join("");
}

function renderAiDjError(error) {
  controls.aiDjRunning.textContent = "状态异常";
  controls.aiDjLogs.innerHTML = `<div class="log-line error"><time>${escapeHtml(formatClock(new Date().toISOString()))}</time><span>${escapeHtml(error.message || String(error))}</span></div>`;
}

function renderLocalDjError(error) {
  controls.localDjService.textContent = "状态异常";
  controls.localDjLogs.innerHTML = `<div class="log-line error"><time>${escapeHtml(formatClock(new Date().toISOString()))}</time><span>${escapeHtml(error.message || String(error))}</span></div>`;
}

function appendLocalAiDjLog(message) {
  const current = controls.aiDjLogs.innerHTML;
  const line = `<div class="log-line info"><time>${escapeHtml(formatClock(new Date().toISOString()))}</time><span>${escapeHtml(message)}</span></div>`;
  controls.aiDjLogs.innerHTML = line + current;
}

function appendLocalDjLog(message) {
  const current = controls.localDjLogs.innerHTML;
  const line = `<div class="log-line info"><time>${escapeHtml(formatClock(new Date().toISOString()))}</time><span>${escapeHtml(message)}</span></div>`;
  controls.localDjLogs.innerHTML = line + current;
}

function setStatus(message, isError = false) {
  controls.status.textContent = message;
  controls.status.style.color = isError ? "#9f2f14" : "";
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes)) return "未知大小";
  if (bytes < 1024) return `${bytes} bytes`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
}

function formatTime(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return "0s";
  const minutes = Math.floor(number / 60);
  const seconds = Math.floor(number % 60).toString().padStart(2, "0");
  return `${minutes}:${seconds}`;
}

function formatPhaseStatus(phase) {
  const scriptReady = phase.scriptStatus === "ready" ? "文案已缓存" : phase.scriptStatus === "pending" ? "文案生成中" : "文案待生成";
  const audioReady = phase.audioStatus === "ready" ? "音频已缓存" : phase.audioStatus === "pending" ? "音频合成中" : "音频待预热";
  return `${scriptReady} · ${audioReady}`;
}

function formatPhaseTime(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return "--";
  return formatTime(number);
}

function formatStateSource(state, status) {
  const label = state?.stateSourceLabel || "";
  if (label) {
    return `${label}${state?.sourceApp ? ` · ${state.sourceApp}` : ""}`;
  }
  if (state?.fallback) {
    return `fallback · ${state.fallback}`;
  }
  if (state?.sourceApp) {
    return `系统 Now Playing · ${state.sourceApp}`;
  }
  if (status?.running) {
    return "等待系统数据";
  }
  return "未知";
}

function formatClock(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleTimeString("zh-CN", { hour12: false });
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}
