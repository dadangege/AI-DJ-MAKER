const DEFAULT_PLAYER_URL = "http://127.0.0.1:54641";

export class LocalPlayerClient {
  constructor({ baseUrl = process.env.LOCAL_DJ_PLAYER_URL || DEFAULT_PLAYER_URL } = {}) {
    this.baseUrl = baseUrl.replace(/\/$/, "");
  }

  status() {
    return this.request("GET", "/status");
  }

  loadMusic(track, { autoplay = false, volume = 1 } = {}) {
    return this.request("POST", "/music/load", {
      path: track.localPath,
      track,
      autoplay,
      volume
    });
  }

  play() {
    return this.request("POST", "/music/play");
  }

  pause() {
    return this.request("POST", "/music/pause");
  }

  stop() {
    return this.request("POST", "/music/stop");
  }

  playTts(audioPath, {
    duckVolume = 0.22,
    fadeMs = 300,
    ttsGain = 1.25
  } = {}) {
    return this.request("POST", "/tts/play", {
      path: audioPath,
      duckVolume,
      fadeMs,
      ttsGain
    });
  }

  async request(method, pathName, payload = null) {
    const response = await fetch(`${this.baseUrl}${pathName}`, {
      method,
      headers: payload ? { "Content-Type": "application/json" } : undefined,
      body: payload ? JSON.stringify(payload) : undefined
    });
    const text = await response.text();
    const json = text ? JSON.parse(text) : {};
    if (!response.ok || json?.ok === false) {
      throw new Error(json?.error || `Local player ${pathName} failed: HTTP ${response.status}`);
    }
    return json;
  }
}
