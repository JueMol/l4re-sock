#!/bin/bash
# Startet das Image in QEMU (arm64, ohne KVM: QEMU bildet auch die
# Virtualisierung in Software nach).
#
#   scripts/qemu.sh [IMAGE]       Standard: images/bootstrap_sock.elf
#
# Bedienung im laufenden System:
#   Strg+E dann 1 / 2   zur Konsole von vm1 / vm2 wechseln
#   Strg+E dann 0       Ausgaben aller Gaeste gemischt
#   Strg+A dann X       QEMU beenden
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
IMG="${1:-$REPO/images/bootstrap_sock.elf}"
[ -f "$IMG" ] || { echo "Image fehlt: $IMG (erst scripts/run.sh oder scripts/build.sh)"; exit 1; }

exec qemu-system-aarch64 \
  -M virt,virtualization=true \
  -cpu cortex-a57 \
  -smp "${QEMU_SMP:-2}" \
  -m 1024 \
  -nographic \
  -kernel "$IMG" \
  ${QEMU_EXTRA:-}
