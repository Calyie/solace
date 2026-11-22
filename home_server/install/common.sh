# Shared by the three install scripts (sourced, not run). Solace Home: docs/HOME_SERVER.md, home_server/README.md.
# Everything goes under one folder for this user (no root needed), and llama.cpp is the official release build of
# b11669 (commit 620d2225, the engine inside the app), checked against the SHA-256 GitHub lists for each file.

set -euo pipefail

LLAMA_TAG=b11669
LLAMA_COMMIT=620d2225cc436ab0b001e3200e590e3b286ef9ab
LLAMA_URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_TAG}"
# where Solace Home keeps its programs (the gateway's own files go in its settings folder: solace-home status)
PREFIX="${SOLACE_HOME_PREFIX:-$HOME/.local/share/solace-home}"
PORT="${SOLACE_HOME_PORT:-8443}"
# the address the gateway listens on: every address of this computer by default; on a rented or cloud machine give
# 127.0.0.1 (Tailscale in userspace mode) or its Tailscale address, so nothing else reaches it (review N-01)
LISTEN="${SOLACE_HOME_LISTEN:-0.0.0.0}"

say() { printf '\n== %s\n' "$*"; }
die() { printf '\nStopped: %s\n' "$*" >&2; exit 1; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# fetch NAME SHA256: downloads one release file of llama.cpp b11669 into $PREFIX/download and checks it
fetch() {
  local name="$1" want="$2" dest="$PREFIX/download/$1"
  mkdir -p "$PREFIX/download"
  if [ ! -f "$dest" ] || [ "$(sha256_of "$dest")" != "$want" ]; then
    say "Downloading $name"
    curl -fL --retry 3 -o "$dest.part" "$LLAMA_URL/$name" || die "could not download $name"
    mv "$dest.part" "$dest"
  fi
  local got
  got="$(sha256_of "$dest")"
  [ "$got" = "$want" ] || { rm -f "$dest"; die "$name has SHA-256 $got, not $want: deleted, nothing installed"; }
}

# unpack NAME: unpacks a checked download into $PREFIX/llama-b11669. The folder is emptied before the first unpack of a
# run (review N-08: nothing left from an earlier install is kept, or has its quarantine flag removed with the rest),
# not before later ones: the NVIDIA installer unpacks the CUDA runtime into the same folder after llama.cpp (R2-02).
LLAMA_DIR_FRESH=""
unpack() {
  local name="$1" into="$PREFIX/llama-$LLAMA_TAG"
  case "$PREFIX" in /*/*) ;; *) die "the install folder $PREFIX is not a full path below a folder" ;; esac
  [ -n "$LLAMA_TAG" ] || die "no llama.cpp build is named"
  if [ -z "$LLAMA_DIR_FRESH" ]; then
    rm -rf -- "$into"
    LLAMA_DIR_FRESH=1
  fi
  mkdir -p "$into"
  tar -xzf "$PREFIX/download/$name" -C "$into"
}

# the llama-server program inside the unpacked release
find_llama_server() {
  find "$PREFIX/llama-$LLAMA_TAG" -type f -name llama-server -perm -u+x | head -n 1
}

# The SHA-256 of each prebuilt solace-home program of this version, pinned here when a release is made
# (home_server/README.md, "Making a release"). Empty: no prebuilt program is published for that system yet, and the
# script builds one from this folder's source with Dart instead. A program beside this script is installed only when
# it matches its pin (H19-12: it used to be copied unchecked, and on a Mac its quarantine flag removed unchecked).
gateway_pin() {
  case "$1" in
    darwin-arm64) echo "7a72792268c988d778ea856cfee4bf0e816f137ce5d7b0dcffd80ea16d3ee772" ;;  # Solace 1.4.0
    darwin-x86_64) echo "3a6bc4b1d1501c4208718081449518db50f7836844a1f7fe4adc4de41c6d490d" ;;  # Solace 1.4.0
    linux-x86_64) echo "a8d78bb0771d1c6bb0d8182320763022babec1f0dd72332fd648d980a70fa850" ;;  # Solace 1.4.0
    linux-aarch64) echo "" ;;
    *) echo "" ;;
  esac
}

# install_gateway: the solace-home program, a single file: the prebuilt solace-home-<os>-<arch> beside this script
# when its SHA-256 matches the pin above, else built here with Dart when the Flutter or Dart SDK is on PATH (from the
# repository's home_server/). A prebuilt program with no pin, or a different SHA-256, is never installed.
install_gateway() {
  local here os arch bin pin got part
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  mkdir -p "$PREFIX/bin"
  bin="$here/solace-home-$os-$arch"
  pin="$(gateway_pin "$os-$arch")"
  part="$PREFIX/bin/solace-home.part"
  if [ -f "$bin" ] && [ -n "$pin" ]; then
    got="$(sha256_of "$bin")"
    [ "$got" = "$pin" ] || die "solace-home-$os-$arch has SHA-256 $got, not $pin as this script pins it: not installed (download the release again, or build from source with Dart)"
    cp "$bin" "$part"
    got="$(sha256_of "$part")"
    if [ "$got" != "$pin" ]; then rm -f "$part"; die "the copied solace-home does not match its pinned SHA-256: not installed"; fi
    # the quarantine flag macOS puts on downloads comes off only now, after the program matched its pin
    if [ "$os" = darwin ]; then xattr -d com.apple.quarantine "$part" 2>/dev/null || true; fi
    mv "$part" "$PREFIX/bin/solace-home"
  elif command -v dart >/dev/null 2>&1 && [ -f "$here/../pubspec.yaml" ]; then
    if [ -f "$bin" ]; then say "solace-home-$os-$arch has no SHA-256 pinned in this script, so it is not used: building from source"; fi
    say "Building solace-home with Dart"
    (cd "$here/.." && dart pub get --enforce-lockfile >/dev/null && dart compile exe bin/solace_home.dart -o "$PREFIX/bin/solace-home")
  elif [ -f "$bin" ]; then
    die "solace-home-$os-$arch is beside this script, but this script pins no SHA-256 for it, so it is not installed. Use the install folder from the same release as the program, or install the Dart SDK to build it from source."
  else
    die "no solace-home program for $os-$arch beside this script, and no Dart SDK to build one"
  fi
  chmod 755 "$PREFIX/bin/solace-home"
}

# setup_model MODEL: points the gateway at the model and llama-server, and makes its certificate
setup_model() {
  local model="$1" server
  server="$(find_llama_server)"
  [ -n "$server" ] || die "llama-server was not found in $PREFIX/llama-$LLAMA_TAG"
  local version
  version="$("$server" --version 2>&1 || true)"  # "version: 0.7.0-dev (build 11669, commit 620d2225c)"
  case "$version" in
    *"build ${LLAMA_TAG#b}, commit ${LLAMA_COMMIT:0:9}"*) ;;
    *) die "the unpacked llama-server is not build $LLAMA_TAG (it says: $version)" ;;
  esac
  if [ -n "$model" ]; then
    [ -f "$model" ] || die "the model file $model is not there"
    "$PREFIX/bin/solace-home" setup --model "$model" --llama-server "$server" --port "$PORT" --listen "$LISTEN" "${@:2}"
  else
    "$PREFIX/bin/solace-home" setup --llama-server "$server" --port "$PORT" --listen "$LISTEN" "${@:2}"
  fi
}

finish() {
  say "Solace Home is installed in $PREFIX"
  cat <<EOF2
Next:
  1. Put the model file (.gguf) and its .sha256 list in one folder (with solace-models.json and its .sig for a
     model on the signed list), then, if you did not pass it to this script:
       $PREFIX/bin/solace-home setup --model /path/to/therapist-e4b-Q5_K_M-imat.gguf
  2. Start it:   $PREFIX/bin/solace-home serve
  3. In another terminal, to pair a phone:   $PREFIX/bin/solace-home pair
     and in Solace on the phone: Settings > Home server, with this computer's address, port $PORT and the code.
EOF2
}
