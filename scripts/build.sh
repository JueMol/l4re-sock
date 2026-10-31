#!/bin/bash
# Baut alles fuer l4re-sock (arm64) und legt das fertige Image unter
# work/out/bootstrap_sock.elf ab.
#
#   scripts/build.sh            alle Schritte (fertige werden uebersprungen)
#   scripts/build.sh linux      nur einen Schritt: fetch fiasco l4re linux
#                               busybox ramdisk image
#
# Laeuft in GitHub Actions; geht aber auch im Codespace oder auf einem
# Ubuntu-Rechner (Pakete: siehe scripts/deps.sh). Erstes Mal ca. 30-60 min.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/scripts/versions.sh"

WORK="${WORK:-$REPO/work}"
SRC="$WORK/src"
OBJ="$WORK/obj"
OUT="$WORK/out"
JOBS="${JOBS:-$(nproc)}"
export CROSS_COMPILE
mkdir -p "$SRC" "$OBJ" "$OUT"

say() { echo; echo "=== $* ==="; }

clone() {   # URL TAG ZIEL
  if [ -d "$3/.git" ]; then return; fi
  rm -rf "$3"
  git clone -q --depth 1 --branch "$2" "$1" "$3"
}

step_fetch() {
  say "Quellen holen ($L4RE_TAG, Linux $LINUX_TAG, Busybox $BUSYBOX_TAG)"
  clone https://github.com/kernkonzept/fiasco "$L4RE_TAG" "$SRC/fiasco"
  clone https://github.com/kernkonzept/mk     "$L4RE_TAG" "$SRC/l4"
  for p in $L4RE_PKGS; do
    clone "https://github.com/kernkonzept/$p" "$L4RE_TAG" "$SRC/l4/pkg/$p"
  done
  clone https://github.com/torvalds/linux "$LINUX_TAG"   "$SRC/linux"
  clone https://github.com/mirror/busybox "$BUSYBOX_TAG" "$SRC/busybox"
}

step_fiasco() {
  say "Fiasco (arm64, QEMU virt, EL2)"
  if [ ! -f "$OBJ/fiasco/globalconfig.out" ]; then
    rm -rf "$OBJ/fiasco"
    make -C "$SRC/fiasco" BUILDDIR="$OBJ/fiasco" T=arm64-virt-el2
  fi
  make -C "$OBJ/fiasco" -j"$JOBS"
}

step_l4re() {
  say "L4Re (arm64, Plattform arm_virt)"
  if [ ! -f "$OBJ/l4/.kconfig" ]; then
    rm -rf "$OBJ/l4"
    make -C "$SRC/l4" B="$OBJ/l4" DEFCONFIG=mk/defconfig/config.arm64-virt-v8a \
         PLATFORM_TYPE=arm_virt
  fi
  make -C "$OBJ/l4" -j"$JOBS"
}

step_linux() {
  say "Linux $LINUX_TAG fuer die Gaeste"
  local o="$OBJ/linux"
  mkdir -p "$o"
  make -C "$SRC/linux" O="$o" ARCH=arm64 tinyconfig >/dev/null
  "$SRC/linux/scripts/kconfig/merge_config.sh" -m -O "$o" \
      "$o/.config" "$REPO/linux/sock-guest.config" >/dev/null
  make -C "$SRC/linux" O="$o" ARCH=arm64 olddefconfig >/dev/null
  # Pruefen, dass jede gewuenschte Option wirklich gesetzt ist
  local bad=0
  while IFS= read -r l; do
    case "$l" in
      CONFIG_*=*) grep -qx "$l" "$o/.config" || { echo "FEHLT: $l"; bad=1; } ;;
    esac
  done < "$REPO/linux/sock-guest.config"
  [ $bad = 0 ] || { echo "Kernel-Konfiguration unvollstaendig"; exit 1; }
  make -C "$SRC/linux" O="$o" ARCH=arm64 -j"$JOBS" Image
  cp "$o/arch/arm64/boot/Image" "$OUT/Image"
}

step_busybox() {
  say "Busybox $BUSYBOX_TAG (statisch)"
  local o="$OBJ/busybox"
  mkdir -p "$o"
  if [ ! -f "$o/.config" ]; then
    make -C "$SRC/busybox" O="$o" defconfig >/dev/null
    # statisch; tc baut mit neuen Kernel-Headern nicht mehr
    sed -i -e 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' \
           -e 's/^CONFIG_TC=y/# CONFIG_TC is not set/' "$o/.config"
    yes "" | make -C "$o" oldconfig >/dev/null
  fi
  make -C "$o" -j"$JOBS"
  rm -rf "$o/_install"
  make -C "$o" install >/dev/null
}

step_ramdisk() {
  say "Ramdisk (busybox, init, sockpp)"
  local r="$OBJ/rootfs"
  rm -rf "$r"
  mkdir -p "$r"/{bin,sbin,usr/bin,usr/sbin,proc,sys,dev,tmp,etc}
  cp -a "$OBJ/busybox/_install/." "$r/"
  "${CROSS_COMPILE}gcc" -static -O2 -Wall -o "$r/bin/sockpp" "$REPO/tools/sockpp.c"
  install -m 755 "$REPO/tools/init" "$r/init"
  ( cd "$r" && find . | cpio -o -H newc --owner=0:0 2>/dev/null | gzip -9 ) \
      > "$OUT/sock-rd.cpio.gz"
  ls -l "$OUT/sock-rd.cpio.gz"
}

step_image() {
  say "Image bootstrap_sock.elf"
  local dtb
  dtb=$(find "$OBJ/l4" -name virt-arm_virt-64.dtb | head -1)
  [ -n "$dtb" ] || { echo "virt-arm_virt-64.dtb nicht gefunden"; exit 1; }
  local msp="$OBJ/fiasco:$REPO/conf:$SRC/l4/pkg/uvmm/configs:$(dirname "$dtb"):$OUT"
  make -C "$OBJ/l4" E=sock PLATFORM_TYPE=arm_virt \
       MODULES_LIST="$REPO/conf/modules.list" MODULE_SEARCH_PATH="$msp" elfimage
  cp -L "$OBJ/l4/images/bootstrap_sock.elf" "$OUT/bootstrap_sock.elf"
  ls -l "$OUT/bootstrap_sock.elf"
}

ALL="fetch fiasco l4re linux busybox ramdisk image"
for s in ${@:-$ALL}; do
  case " $ALL " in *" $s "*) "step_$s" ;; *) echo "Unbekannter Schritt: $s"; exit 1 ;; esac
done
say "fertig: $OUT/bootstrap_sock.elf"
