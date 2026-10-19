#!/usr/bin/env bash
# Vercel build: uses Flutter from PATH, otherwise downloads the stable SDK, then builds the web app.
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  if [ ! -d "$HOME/flutter" ]; then
    git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter"
  fi
  export PATH="$HOME/flutter/bin:$PATH"
fi

flutter --version
flutter config --enable-web --no-analytics >/dev/null
flutter pub get
flutter build web --release
