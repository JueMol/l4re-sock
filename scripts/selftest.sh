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

STALL="${STALL:-300}"     # so lange ohne neue Ausgabe: haengt
result=1
last_size=-1; still=0
for ((t = 0; t < LIMIT; t += 5)); do
  sleep 5
  if ! kill -0 $pid 2>/dev/null; then
    echo "QEMU hat sich beendet"; break
  fi
  size=$(stat -c %s "$LOG")
  if [ "$size" = "$last_size" ]; then still=$((still + 5)); else still=0; last_size=$size; fi
  if [ $still -ge "$STALL" ]; then
    echo "Seit $STALL s keine neue Ausgabe: das System haengt"; break
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
