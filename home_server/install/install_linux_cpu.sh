#!/usr/bin/env bash
# Solace Home on Linux, on the processor (docs/HOME_SERVER.md). One command:
#
#   bash install_linux_cpu.sh [/path/to/model.gguf]
#
# Installs llama.cpp's official b11669 release for Linux (x86-64 or arm64; checked by SHA-256) and the solace-home
# gateway under ~/.local/share/solace-home, for this user only. Needs curl, tar and openssl, and the libraries
# llama-server links with (libgomp1, libssl3, zlib: present on most systems).
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$here/common.sh"

[ "$(uname -s)" = Linux ] || die "this script is for Linux"
case "$(uname -m)" in
  x86_64) fetch llama-b11669-bin-ubuntu-x64.tar.gz cf07c1c112d709bd67e522017471de57ed0ec8bea031d732c5422351c07f65ac
          unpack llama-b11669-bin-ubuntu-x64.tar.gz ;;
  aarch64) fetch llama-b11669-bin-ubuntu-arm64.tar.gz 9ac6fda2058d35677608a06f751a50122ddfa4ce0ddb7f084466b8e79b6d4a99
           unpack llama-b11669-bin-ubuntu-arm64.tar.gz ;;
  *) die "no llama.cpp release build for $(uname -m)" ;;
esac
command -v openssl >/dev/null || die "openssl is needed for the server's certificate (apt install openssl)"
missing="$(ldd "$(find_llama_server)" 2>/dev/null | grep 'not found' || true)"
[ -z "$missing" ] || die "llama-server needs libraries this system lacks: $missing (on Debian or Ubuntu: apt install libgomp1 libssl3 zlib1g)"
install_gateway
setup_model "${1:-}" --gpu-layers 0
finish
