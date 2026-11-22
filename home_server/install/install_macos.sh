#!/usr/bin/env bash
# Solace Home on a Mac (docs/HOME_SERVER.md). One command:
#
#   bash install_macos.sh [/path/to/model.gguf]
#
# Apple silicon uses the graphics processor (Metal); an Intel Mac uses the processor (llama.cpp's Metal path is not
# reliable there, as in the app). Installs llama.cpp's official b11669 release for macOS (checked by SHA-256) and the
# solace-home gateway (solace-home-darwin-<arch> beside this script, built on a Mac) under
# ~/.local/share/solace-home, for this user only. macOS has curl, tar and openssl (LibreSSL) already.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$here/common.sh"

[ "$(uname -s)" = Darwin ] || die "this script is for macOS"
case "$(uname -m)" in
  arm64) fetch llama-b11669-bin-macos-arm64.tar.gz dbed55493d72bc1ba2babc8770d669c2289b5bc4ee9fb2a4dfc158d45b7d13fd
         unpack llama-b11669-bin-macos-arm64.tar.gz
         layers=all ;;
  x86_64) fetch llama-b11669-bin-macos-x64.tar.gz cab28238d78158109b48deb27b05d50e0dcef56275d2e76da9ca8281526c7532
          unpack llama-b11669-bin-macos-x64.tar.gz
          layers=0 ;;
  *) die "no llama.cpp release build for $(uname -m)" ;;
esac
# the download is checked by its SHA-256 above, so the quarantine flag macOS sets on downloads is removed from it
xattr -dr com.apple.quarantine "$PREFIX/llama-$LLAMA_TAG" 2>/dev/null || true
install_gateway  # checks a prebuilt solace-home against its pinned SHA-256 before its quarantine flag comes off
setup_model "${1:-}" --gpu-layers "$layers"
finish
cat <<'EOF2'
The first time solace-home serve starts, macOS asks whether it may accept incoming network connections: allow it, or
phones cannot reach it.
EOF2
