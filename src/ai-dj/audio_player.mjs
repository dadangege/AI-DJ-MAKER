import { spawn } from "node:child_process";

export function playAudio(audioPath, { volume = 1 } = {}) {
  return new Promise((resolve, reject) => {
    const args = [];
    const playbackVolume = Number(volume);
    if (Number.isFinite(playbackVolume) && playbackVolume !== 1) {
      args.push("-v", String(playbackVolume));
    }
    args.push(audioPath);

    const child = spawn("afplay", args, {
      stdio: ["ignore", "ignore", "pipe"]
    });

    let stderr = "";
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });

    child.on("error", reject);
    child.on("exit", (code, signal) => {
      if (code === 0) {
        resolve();
        return;
      }
      reject(new Error(`afplay failed: code=${code} signal=${signal || ""} ${stderr.trim()}`));
    });
  });
}
