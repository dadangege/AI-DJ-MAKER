import { AudioDuckingController } from "./audio_ducking_controller.mjs";
import { playAudio } from "./audio_player.mjs";

export class AudioMixdownController {
  constructor({
    duckVolume = 22,
    duckFadeSteps = 4,
    duckFadeStepDelayMs = 70,
    ttsPlaybackGain = 1.25
  } = {}) {
    this.ducking = new AudioDuckingController({
      duckVolume,
      fadeSteps: duckFadeSteps,
      fadeStepDelayMs: duckFadeStepDelayMs
    });
    this.ttsPlaybackGain = ttsPlaybackGain;
  }

  get isActive() {
    return this.ducking.isActive;
  }

  get activeSession() {
    return this.ducking.activeSession;
  }

  async begin(state, { logger = () => {} } = {}) {
    return this.ducking.begin(state, { logger });
  }

  async play(audioPath) {
    return playAudio(audioPath, { volume: this.ttsPlaybackGain });
  }

  async end(logger = () => {}) {
    return this.ducking.end(logger);
  }

  async forceEnd(logger = () => {}) {
    return this.ducking.forceEnd(logger);
  }
}
