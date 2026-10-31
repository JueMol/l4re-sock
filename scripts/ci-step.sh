#!/bin/bash
# Fuer GitHub Actions: fuehrt einen Befehl aus, schreibt die Ausgabe nach
# work/out/log-NAME.txt und meldet bei einem Fehler die wichtigsten Zeilen
# als Annotation (die sind auch ohne Zugriff auf die Log-Dateien sichtbar).
#
#   scripts/ci-step.sh NAME BEFEHL...
set -o pipefail
name=$1; shift
mkdir -p work/out
log="work/out/log-$name.txt"
"$@" 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}
if [ "$rc" != 0 ]; then
  # Zeilen mit Fehlern zuerst, dann das Ende der Ausgabe; je Annotation
  # hoechstens 15 Zeilen, hoechstens 8 Annotationen
  { grep -a -n -i -E "error|fehler|fatal|undefined|not found|No such|cannot" "$log" | tail -45
    echo "----- Ende der Ausgabe -----"
    tail -n 60 "$log"; } | tr -d '\r' | cut -c1-300 > "$log.tail"
  split -l 15 -a 1 "$log.tail" "$log.part."
  n=0
  for f in "$log.part."*; do
    n=$((n + 1)); [ $n -le 8 ] || break
    msg=$(sed -e 's/%/%25/g' "$f" | awk '{printf "%s%%0A", $0}')
    echo "::error title=$name ($n)::$msg"
  done
fi
exit "$rc"
