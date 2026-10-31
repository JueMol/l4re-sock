#!/bin/bash
# Pakete fuer Bauen und Starten (Ubuntu 24.04: GitHub Actions, Codespace).
#   scripts/deps.sh          alles zum Bauen und Starten
#   scripts/deps.sh run      nur zum Starten (QEMU)
set -euo pipefail
SUDO=; [ "$(id -u)" = 0 ] || SUDO=sudo
$SUDO apt-get update -q
if [ "${1:-}" = run ]; then
  $SUDO apt-get install -y -q qemu-system-arm
  exit 0
fi
$SUDO apt-get install -y -q --no-install-recommends \
  gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libc6-dev-arm64-cross \
  make gawk perl pkg-config device-tree-compiler python3 \
  flex bison bc libssl-dev cpio gzip git ca-certificates \
  qemu-system-arm
