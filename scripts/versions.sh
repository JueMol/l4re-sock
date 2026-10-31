# Feste Versionen aller Quellen. Wer hier etwas aendert, baut alles neu.

# L4Re und Fiasco: Wochenstand aus github.com/kernkonzept (Tag im manifest)
L4RE_TAG=r-2026-W43

# L4Re-Pakete, die gebraucht werden (Rest des manifests bleibt weg)
L4RE_PKGS="l4re-core bootstrap cons drivers-frst io l4virtio libfdt libvcpu
           readline uvmm virtio-net zlib"

# Gast-Kernel und Busybox fuer die Ramdisk
LINUX_TAG=v6.12
BUSYBOX_TAG=1_36_1

CROSS_COMPILE=aarch64-linux-gnu-
