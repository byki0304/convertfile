#!/usr/bin/env bash
# Vercel build: uses Flutter from PATH, otherwise downloads the stable SDK, then builds the web app.
set -euo pipefail

# Vercel may start in a subfolder when Root Directory is not the repo root; build from the root
# and copy the output back so outputDirectory (build/web) resolves either way.
START_DIR="$(pwd)"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
echo "==> repo root: $ROOT_DIR (started in $START_DIR)"

missing=()
for tool in git curl unzip xz tar which file; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "==> installing: ${missing[*]}"
  pkgs=()
  for t in "${missing[@]}"; do
    case "$t" in
      xz) pkgs+=(xz) ;;
      *) pkgs+=("$t") ;;
    esac
  done
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y "${pkgs[@]}"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "${pkgs[@]}"
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y "${pkgs[@]}"
  fi
fi

if command -v flutter >/dev/null 2>&1; then
  FLUTTER="$(command -v flutter)"
else
  SDK="$HOME/flutter"
  if [ ! -x "$SDK/bin/flutter" ]; then
    echo "==> downloading Flutter stable"
    rm -rf "$SDK"
    git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$SDK"
  fi
  FLUTTER="$SDK/bin/flutter"
fi

export CI=true
echo "==> flutter version"
"$FLUTTER" --version
"$FLUTTER" config --enable-web --no-analytics >/dev/null
echo "==> pub get"
"$FLUTTER" pub get
echo "==> build web"
"$FLUTTER" build web --release

if [ "$START_DIR" != "$ROOT_DIR" ]; then
  echo "==> copying build/web to $START_DIR/build/web"
  rm -rf "$START_DIR/build/web"
  mkdir -p "$START_DIR/build"
  cp -R "$ROOT_DIR/build/web" "$START_DIR/build/web"
fi
