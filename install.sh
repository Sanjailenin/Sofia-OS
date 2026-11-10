#!/bin/bash
set -euo pipefail

main() {
  REPO="${SOFIA_REPO:-Sanjailenin/Sofia-OS}"
  MODEL="${SOFIA_MODEL:-}"
  VERSION="${SOFIA_VERSION:-}"
  UNINSTALL_CMD="curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash -s -- --uninstall"

  if [ -n "${SOFIA_APP_DIR:-}" ]; then
    APP_DIR="$SOFIA_APP_DIR"
  elif [ -w /Applications ]; then
    APP_DIR=/Applications
  else
    APP_DIR="$HOME/Applications"
  fi

  if [ "${1:-}" = "--uninstall" ]; then
    uninstall
    return 0
  fi
  if [ "${1:-}" = "--voices" ]; then
    setup_voices
    return 0
  fi

  [ "$(uname -s)" = "Darwin" ] || die "Sofia runs on macOS only."
  local major
  major=$(sw_vers -productVersion | cut -d. -f1)
  [ "$major" -ge 13 ] || die "Sofia needs macOS 13 or later."
  mkdir -p "$APP_DIR" || die "Can't create $APP_DIR."

  if [ -z "${SOFIA_SKIP_MODEL:-}" ]; then
    setup_model
  fi
  if [ -z "${SOFIA_SKIP_VOICES:-}" ]; then
    setup_voices
  fi
  install_app
}

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
die() { printf '\n\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

ollama_up() { curl -fs http://localhost:11434/api/version >/dev/null 2>&1; }

find_ollama_app() {
  local d
  for d in /Applications "$HOME/Applications" "$APP_DIR"; do
    if [ -x "$d/Ollama.app/Contents/Resources/ollama" ]; then
      echo "$d/Ollama.app"
      return 0
    fi
  done
  return 1
}

find_ollama_cli() {
  local app
  if command -v ollama >/dev/null 2>&1; then
    command -v ollama
  elif app=$(find_ollama_app); then
    echo "$app/Contents/Resources/ollama"
  else
    return 1
  fi
}

OLLAMA_TEAM="3MU9H2V9Y9"

install_ollama() {
  say "Installing Ollama (the local model runner, about 230 MB)"
  local tmp
  tmp=$(mktemp -d)
  curl -fL --progress-bar -o "$tmp/Ollama.zip" https://ollama.com/download/Ollama-darwin.zip </dev/null || die "Couldn't download Ollama. Install it from https://ollama.com and run this again."
  ditto -x -k "$tmp/Ollama.zip" "$tmp" </dev/null || die "Couldn't unpack Ollama."
  [ -d "$tmp/Ollama.app" ] || die "The Ollama download didn't contain Ollama.app."
  codesign --verify --deep --strict -R="anchor apple generic and certificate leaf[subject.OU] = \"$OLLAMA_TEAM\"" "$tmp/Ollama.app" </dev/null 2>/dev/null || { rm -rf "$tmp"; die "The Ollama download isn't signed by Ollama; not installing it. Install it from https://ollama.com and run this again."; }
  rm -rf "$APP_DIR/Ollama.app"
  mv "$tmp/Ollama.app" "$APP_DIR/Ollama.app"
  xattr -dr com.apple.quarantine "$APP_DIR/Ollama.app" 2>/dev/null || true
  rm -rf "$tmp"
}

start_ollama() {
  ollama_up && return 0
  say "Starting Ollama"
  local app
  if app=$(find_ollama_app); then
    open -g -a "$app" </dev/null
  elif command -v brew >/dev/null 2>&1 && brew list --formula ollama >/dev/null 2>&1 </dev/null; then
    brew services start ollama </dev/null >/dev/null 2>&1 || true
  fi
  local i
  for i in $(seq 1 30); do ollama_up && return 0; sleep 1; done
  nohup "$OLLAMA" serve </dev/null >/dev/null 2>&1 &
  for i in $(seq 1 30); do ollama_up && return 0; sleep 1; done
  die "Ollama didn't start. Open the Ollama app once, then run this again."
}

setup_model() {
  if ! OLLAMA=$(find_ollama_cli); then
    install_ollama
    OLLAMA=$(find_ollama_cli) || die "Ollama was installed but its command-line tool wasn't found."
  fi
  start_ollama
  if [ -z "$MODEL" ]; then
    local mem_gb
    mem_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
    if [ "$mem_gb" -ge 32 ]; then MODEL="qwen3:14b"; elif [ "$mem_gb" -ge 16 ]; then MODEL="qwen3:8b"; else MODEL="qwen3:4b"; fi
  fi
  say "Pulling the model: $MODEL (this is the slow part)"
  "$OLLAMA" pull "$MODEL" </dev/null || die "Couldn't download the model $MODEL. Check your connection and run this again."
}

ENGINE_VERSION="sherpa-onnx-v1.13.8"
VOICES_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2"
VOICES_SHA="60703707bc05ccd48d60e1eb723f38b07d6e474795a0b6a588d7220400e0f7a4"
KWS_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01.tar.bz2"
KWS_SHA="f170013b4716e41b62b9bfd809687c207cef798ef9bc6534d524e17af9b6561a"
KWS_DIR="sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01"

engine_for_this_mac() {
  if [ "$(uname -m)" = "arm64" ]; then
    ENGINE_NAME="$ENGINE_VERSION-osx-arm64-shared-lib"
    ENGINE_SHA="ae77050cdae565496059d96f5ab33d77b397a0864282a4e4a26e3b3b3effb948"
  else
    ENGINE_NAME="$ENGINE_VERSION-osx-x64-shared-lib"
    ENGINE_SHA="0f88371565a06372889c76266e253abd1b415fcc6f98232cabd968933efb0711"
  fi
  ENGINE_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/$ENGINE_NAME.tar.bz2"
  VOICES_VERSION="kokoro-multi-lang-v1_0 $KWS_DIR $ENGINE_NAME"
}

fetch_checked() {
  curl -fL --progress-bar -o "$2" "$1" </dev/null || return 1
  [ "$(shasum -a 256 "$2" | cut -d' ' -f1)" = "$3" ]
}

setup_voices() {
  engine_for_this_mac
  local dest="$HOME/Library/Application Support/Sofia/Voices"
  if [ "$(cat "$dest/version" 2>/dev/null)" = "$VOICES_VERSION" ]; then
    return 0
  fi
  say "Downloading her voices and wake-word model (about 380 MB, once)"
  local tmp
  tmp=$(mktemp -d)
  if ! fetch_checked "$ENGINE_URL" "$tmp/engine.tar.bz2" "$ENGINE_SHA" || ! fetch_checked "$VOICES_URL" "$tmp/voices.tar.bz2" "$VOICES_SHA" || ! fetch_checked "$KWS_URL" "$tmp/kws.tar.bz2" "$KWS_SHA"; then
    rm -rf "$tmp"
    echo "Couldn't download the voices, so Sofia will use the Mac's own voice and Apple's speech recognition only. Run this again later to add them."
    return 0
  fi
  mkdir -p "$tmp/out/lib" "$tmp/out/kokoro" "$tmp/out/kws"
  tar -xjf "$tmp/engine.tar.bz2" -C "$tmp" </dev/null
  cp "$tmp/$ENGINE_NAME/lib/libsherpa-onnx-c-api.dylib" "$tmp/$ENGINE_NAME/lib/libonnxruntime.dylib" "$tmp/out/lib/"
  tar -xjf "$tmp/voices.tar.bz2" -C "$tmp" kokoro-multi-lang-v1_0/model.onnx kokoro-multi-lang-v1_0/voices.bin kokoro-multi-lang-v1_0/tokens.txt kokoro-multi-lang-v1_0/LICENSE kokoro-multi-lang-v1_0/espeak-ng-data </dev/null
  mv "$tmp"/kokoro-multi-lang-v1_0/* "$tmp/out/kokoro/"
  tar -xjf "$tmp/kws.tar.bz2" -C "$tmp" </dev/null
  cp "$tmp/$KWS_DIR/encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx" "$tmp/out/kws/encoder.int8.onnx"
  cp "$tmp/$KWS_DIR/decoder-epoch-12-avg-2-chunk-16-left-64.onnx" "$tmp/out/kws/decoder.onnx"
  cp "$tmp/$KWS_DIR/joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx" "$tmp/out/kws/joiner.int8.onnx"
  cp "$tmp/$KWS_DIR/tokens.txt" "$tmp/$KWS_DIR/bpe.model" "$tmp/out/kws/"
  echo "$VOICES_VERSION" > "$tmp/out/version"
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  mv "$tmp/out" "$dest"
  rm -rf "$tmp"
}

install_app() {
  say "Downloading Sofia"
  local tmp base
  tmp=$(mktemp -d)
  if [ -n "$VERSION" ]; then
    base="https://github.com/$REPO/releases/download/$VERSION"
  else
    base="https://github.com/$REPO/releases/latest/download"
  fi
  curl -fL --progress-bar -o "$tmp/Sofia.zip" "$base/Sofia.zip" </dev/null || die "Couldn't download the app from $base. Build from source instead: git clone https://github.com/$REPO && cd Sofia-OS && scripts/build-app.sh"
  curl -fsSL -o "$tmp/Sofia.zip.sha256" "$base/Sofia.zip.sha256" </dev/null || die "Couldn't download the checksum."
  (cd "$tmp" && shasum -a 256 -c Sofia.zip.sha256 >/dev/null) || die "Checksum mismatch; not installing."
  ditto -x -k "$tmp/Sofia.zip" "$tmp" </dev/null
  [ -d "$tmp/Sofia.app" ] || die "The download didn't contain Sofia.app."
  pkill -x Sofia 2>/dev/null || true
  pkill -x Sophia 2>/dev/null || true
  rm -rf "$APP_DIR/Sofia.app" "$APP_DIR/Sophia.app"
  mv "$tmp/Sofia.app" "$APP_DIR/Sofia.app" || die "Couldn't move Sofia.app into $APP_DIR."
  xattr -dr com.apple.quarantine "$APP_DIR/Sofia.app" 2>/dev/null || true
  rm -rf "$tmp"
  [ -n "$MODEL" ] && defaults write dev.sofia.app ollamaModel -string "$MODEL"
  local version
  version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Sofia.app/Contents/Info.plist" 2>/dev/null || echo "?")

  if [ -n "${SOFIA_NO_OPEN:-}" ]; then
    echo "Installed Sofia $version to $APP_DIR/Sofia.app."
    return 0
  fi
  say "Opening Sofia $version"
  open "$APP_DIR/Sofia.app" </dev/null
  cat <<EOF

SOFIA is installed in $APP_DIR. On first run a welcome window asks for her name and voice, then:
  1. Allow the microphone and speech recognition when macOS asks.
  2. For Mac control, allow Accessibility and Screen Recording for Sofia in System Settings → Privacy & Security.
  3. Optional: paste a Telegram bot token (from @BotFather) to reach this Mac from your phone, then send the
     six-digit code shown in Settings to your bot.

Say "Hey <her name>" or press ⌃⌥S. Uninstall with:
  $UNINSTALL_CMD
EOF
}

uninstall() {
  say "Removing Sofia"
  pkill -x Sofia 2>/dev/null || true
  pkill -x Sophia 2>/dev/null || true
  local d
  for d in /Applications "$HOME/Applications" "$APP_DIR"; do
    rm -rf "$d/Sofia.app" "$d/Sophia.app"
  done
  rm -rf "$HOME/Library/Application Support/Sofia" "$HOME/Library/Logs/Sofia" "$HOME/Library/Application Support/Sophia" "$HOME/Library/Logs/Sophia"
  defaults delete dev.sofia.app 2>/dev/null || true
  defaults delete dev.sophia.app 2>/dev/null || true
  echo "Done. Ollama and its models were left in place; remove the Ollama app to delete them."
}

main "$@"
