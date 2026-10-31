#!/bin/bash
# Im Codespace: fertiges Image aus dem neuesten Release holen (falls noch
# nicht da) und QEMU starten.
#
#   scripts/run.sh            starten (laedt beim ersten Mal das Image)
#   scripts/run.sh --neu      Image neu laden, dann starten
#   scripts/run.sh --lokal    selbst gebautes work/out/bootstrap_sock.elf nehmen
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
IMG="$REPO/images/bootstrap_sock.elf"

case "${1:-}" in
  --lokal) exec "$REPO/scripts/qemu.sh" "$REPO/work/out/bootstrap_sock.elf" ;;
  --neu)   rm -f "$IMG" ;;
esac

if [ ! -f "$IMG" ]; then
  mkdir -p "$REPO/images"
  echo "Lade bootstrap_sock.elf aus dem Release 'latest' ..."
  gh release download latest --pattern bootstrap_sock.elf --dir "$REPO/images" --clobber \
    || { echo "Download fehlgeschlagen. Ist der Build in GitHub Actions durchgelaufen?"; exit 1; }
fi

command -v qemu-system-aarch64 >/dev/null || {
  echo "qemu-system-aarch64 fehlt: sudo apt-get install -y qemu-system-arm"; exit 1; }

echo
echo "Start dauert ohne KVM etwas (bis die Gaeste melden: SELFTEST OK)."
echo "Strg+E 1 / Strg+E 2: Konsole vm1 / vm2.  Strg+A X: beenden."
echo
exec "$REPO/scripts/qemu.sh" "$IMG"
