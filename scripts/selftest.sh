#!/bin/bash
# Startet das Image ohne Bedienung und wartet, bis beide Gaeste
# "SELFTEST OK" melden. Fuer GitHub Actions; geht auch im Codespace.
#
#   scripts/selftest.sh [IMAGE] [SEKUNDEN]
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
IMG="${1:-$REPO/work/out/bootstrap_sock.elf}"
LIMIT="${2:-1200}"
LOG="${LOG:-$REPO/work/out/selftest.log}"
mkdir -p "$(dirname "$LOG")"

echo "Selbsttest mit $IMG (hoechstens $LIMIT s), Ausgabe: $LOG"
# stdin aus /dev/null: QEMU bekommt keine Tastatur
"$REPO/scripts/qemu.sh" "$IMG" </dev/null >"$LOG" 2>&1 &
pid=$!

result=1
for ((t = 0; t < LIMIT; t += 5)); do
  sleep 5
  if ! kill -0 $pid 2>/dev/null; then
    echo "QEMU hat sich beendet"; break
  fi
  ok=$(grep -a -c "SELFTEST OK" "$LOG")
  if grep -a -q "SELFTEST FEHLER" "$LOG"; then
    echo "Ein Gast meldet SELFTEST FEHLER"; break
  fi
  if [ "$ok" -ge 2 ]; then
    echo "Beide Gaeste: SELFTEST OK nach ca. $t s"; result=0; break
  fi
  (( t % 60 == 0 )) && echo "  ... $t s, letzte Zeile: $(tail -c 300 "$LOG" | tr -d '\r' | tail -1)"
done

kill $pid 2>/dev/null; wait $pid 2>/dev/null
echo "----- Ende der Ausgabe -----"
tail -n 60 "$LOG" | tr -d '\r'
exit $result
