import fs from "node:fs";

export function parseArgs(argv) {
  const args = {};

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) continue;

    const [rawKey, inlineValue] = token.slice(2).split("=", 2);
    const key = toCamelCase(rawKey);

    if (inlineValue !== undefined) {
      args[key] = inlineValue;
      continue;
    }

    const next = argv[index + 1];
    if (!next || next.startsWith("--")) {
      args[key] = true;
      continue;
    }

    args[key] = next;
    index += 1;
  }

  return args;
}

export function readTextArg(args) {
  if (args.text) return String(args.text);
  if (args.file) return fs.readFileSync(args.file, "utf8");

  if (!process.stdin.isTTY) {
    const stdin = fs.readFileSync(0, "utf8").trim();
    if (stdin) return stdin;
  }

  return "";
}

export function numberArg(value, fallback) {
  if (value === undefined || value === true || value === "") return fallback;

  const number = Number(value);
  if (Number.isNaN(number)) return fallback;
  return number;
}

function toCamelCase(value) {
  return value.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
}
