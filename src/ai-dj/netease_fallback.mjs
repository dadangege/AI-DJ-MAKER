import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const CACHE_DIR = path.join(
  os.homedir(),
  "Library",
  "Containers",
  "com.netease.163music",
  "Data",
  "Caches",
  "online_play_cache"
);

const metadataCache = new Map();

export async function getNeteaseFallbackState({ maxAgeMs = 10 * 60 * 1000 } = {}) {
  const latest = findLatestInfoFile();
  if (!latest) return null;

  const ageMs = Date.now() - latest.mtimeMs;
  if (ageMs > maxAgeMs) return null;

  const songId = parseSongId(latest.fileName);
  if (!songId) return null;

  const metadata = await getSongMetadata(songId);
  if (!metadata) return null;

  const elapsed = Math.max(0, ageMs / 1000);
  const duration = metadata.duration || null;

  return {
    state: "playing",
    title: metadata.title,
    artist: metadata.artist,
    album: metadata.album,
    duration,
    elapsed: duration ? Math.min(elapsed, Math.max(duration - 1, 0)) : elapsed,
    playbackRate: 1,
    sourceApp: "com.netease.163music-cache",
    trackId: `netease|${songId}`,
    fallback: "netease-cache",
    progressReliable: false,
    progressSource: "cache-mtime-estimate"
  };
}

function findLatestInfoFile() {
  if (!fs.existsSync(CACHE_DIR)) return null;

  const files = fs.readdirSync(CACHE_DIR)
    .filter((fileName) => fileName.endsWith(".info"))
    .map((fileName) => {
      const filePath = path.join(CACHE_DIR, fileName);
      const stat = fs.statSync(filePath);
      return {
        fileName,
        filePath,
        mtimeMs: stat.mtimeMs
      };
    })
    .sort((left, right) => right.mtimeMs - left.mtimeMs);

  return files[0] || null;
}

function parseSongId(fileName) {
  const match = /^(\d+)-_-_/.exec(fileName);
  return match ? match[1] : "";
}

async function getSongMetadata(songId) {
  if (metadataCache.has(songId)) {
    return metadataCache.get(songId);
  }

  try {
    const response = await fetch(`https://music.163.com/api/song/detail?ids=%5B${songId}%5D`);
    if (!response.ok) return null;
    const json = await response.json();
    const song = json?.songs?.[0];
    if (!song) return null;

    const metadata = {
      title: song.name || "",
      artist: (song.artists || []).map((artist) => artist.name).filter(Boolean).join(" / "),
      album: song.album?.name || "",
      duration: Number.isFinite(song.duration) ? song.duration / 1000 : null
    };

    metadataCache.set(songId, metadata);
    return metadata;
  } catch {
    return null;
  }
}
