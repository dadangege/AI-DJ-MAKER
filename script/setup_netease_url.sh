#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$ROOT_DIR/vendor/Netease_url"
REPO_URL="https://github.com/Suxiaoqinx/Netease_url.git"

mkdir -p "$ROOT_DIR/vendor"

if [[ -d "$REPO_DIR/.git" ]]; then
  git -C "$REPO_DIR" pull --ff-only
else
  git clone "$REPO_URL" "$REPO_DIR"
fi

PYTHON_BIN="${PYTHON:-python3}"
"$PYTHON_BIN" -m venv "$REPO_DIR/.venv"
VENV_PYTHON="$REPO_DIR/.venv/bin/python"
"$VENV_PYTHON" -m pip install --upgrade pip

if [[ -f "$REPO_DIR/requirements.txt" ]]; then
  COMPAT_REQUIREMENTS="$REPO_DIR/.requirements.compat.txt"
  "$VENV_PYTHON" - "$REPO_DIR/requirements.txt" "$COMPAT_REQUIREMENTS" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
raw = source.read_bytes()
text = None
for encoding in ("utf-8-sig", "utf-16", "utf-16le"):
    try:
        text = raw.decode(encoding)
        break
    except UnicodeDecodeError:
        pass
if text is None:
    text = raw.decode("utf-8", errors="ignore")

if sys.version_info < (3, 10):
    text = re.sub(r"(?im)^click==8\.2\.1\s*$", "click==8.1.8", text)

target.write_text(text.replace("\r\n", "\n").replace("\r", "\n"), encoding="utf-8")
PY
  "$REPO_DIR/.venv/bin/pip" install -r "$COMPAT_REQUIREMENTS"
fi

echo "Netease_url ready at $REPO_DIR"
