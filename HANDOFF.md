# Soul DJ Handoff

## Current App Shape

- Main app is a native macOS SwiftUI app under `native/macos-app`.
- Build entry is `npm run mac-app:build`, which creates `macos/Soul DJ.app`.
- `SoulDJStore` owns UI state, playlist state, playback state, AI host state, logs, lyrics, public playlists, and environment context.
- `LocalAudioEngine` owns music playback, TTS playback, ducking, fades, crossfade, and spectrum levels.
- `MiniMaxService` owns text generation and TTS synthesis.
- `NeteaseService` owns QR login, playlists, track metadata, lyrics, audio URL resolving, and cache.

## Important Recent Changes

- AI host picker modal:
  - Hosts: Ava, Leo, Nora, Max.
  - Modes: Nightclub DJ, Midnight Radio, Music Curator, Emotional Companion, Casual Chat.
  - Host selection only takes effect after `保存并生效`.
  - Saved host updates `selectedHostId`, `selectedHostMode`, `voiceID`, `speed`, and `pitch`.
  - If no host is saved, UI shows an unset state and prompts the user to choose one.
- Top environment chip:
  - `EnvironmentContextService` calls `ipapi.co` for city/lat/lon and Open-Meteo for current weather.
  - Success displays a small chip next to `Soul DJ`.
  - Failure is logged and hidden from UI.
- Public playlists:
  - Home recommendations use public NetEase playlists.
  - `换一换` rotates public playlist categories/pages.
- Images:
  - NetEase `http://` image URLs are upgraded to `https://` via `String.neteaseImageURL`.
- Lyrics:
  - Chat panel shows synced LRC lines and auto-scrolls based on playback elapsed time.
- Spectrum:
  - `LocalAudioEngine` installs a mixer tap and reports 36 spectrum levels.
  - Cached/local playback and TTS produce real levels; remote `AVPlayer` streaming still falls back visually.

## Playback And Mixing Notes

- Playback has two paths:
  - Cached/local audio: `AVAudioEngine.loadMusic(path:)`.
  - Uncached remote URL: `AVPlayer` streaming via `loadMusicStream(url:)`, while background caching runs.
- TTS uses `AVAudioPlayerNode` and ducks music through `playTTS`.
- Current ducking defaults:
  - Main transition duck volume: `0.14`
  - Main transition fade: `3000ms`
  - TTS gain: `1.55`, capped at `2.0` in `LocalAudioEngine`
- Fade is linear and asynchronous so the UI can see the actual music volume change.
- Main transition timing aligns the TTS midpoint to the current track end:
  - `ttsStart = currentDuration - ttsDuration / 2`
  - background duck starts `1.5s` before `ttsStart`
  - 3-second linear duck completes `1.5s` after TTS starts
- `statusLocked()` reports actual `musicVolume` plus `userMusicVolume`.
- Right-side volume slider currently reflects actual music volume, so it visibly dips during ducking and returns after TTS.

## Known Limitations

- Remote streaming uses `AVPlayer`, so true per-buffer spectrum and full engine-level mixing are only available after the song is cached.
- IP city may be inaccurate if the user is behind VPN/proxy or a remote network exit.
- Weather/city are not yet used by transition prompts; they are only displayed in the top bar.
- No full `transitionEngine` exists yet. Current AI transition still directly calls `MiniMaxService.generateTransitionScript`.
- Track style, mood, and BPM are not first-class metadata yet.
- Time announcement currently has an in-session 30-minute cooldown and strips duplicate "现在是北京时间..." text before enforcing the announcement prefix.

## Recommended Next Steps

- Add `TransitionEngine` with `TransitionType`, `HostSessionState`, and one-topic selection rules.
- Add LLM-based `TrackAnalysis` cache for genre/mood/BPM band.
- Feed `EnvironmentContext` into the transition engine once selection rules are implemented.
- Consider a buffered AVAudioEngine streaming path if real-time spectrum/mixing for uncached remote songs becomes critical.
