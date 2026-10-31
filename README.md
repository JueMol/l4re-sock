# l4re-sock

Zwei Linux-Gäste auf dem L4Re-Microkernel, jeder in seiner eigenen
virtuellen Maschine (`uvmm`), verbunden über das normale virtio-Netz von
L4Re. Ein kleines Programm (`sockpp`) spielt Ping-Pong über UDP und TCP.
Das Ganze läuft in QEMU, auch in einem GitHub Codespace ohne KVM.

```
 ┌──────────────────────┐                     ┌──────────────────────┐
 │ vm1   (uvmm + Linux) │                     │ vm2   (uvmm + Linux) │
 │ 192.168.1.1          │                     │ 192.168.1.2          │
 │ sockpp server        │                     │ sockpp server        │
 │ eth0  virtio         │                     │ eth0  virtio         │
 └──────────┬───────────┘                     └───────────┬──────────┘
            │              ┌──────────────────┐           │
            └──────────────┤  l4vio_net_p2p   ├───────────┘
                           │ beide Richtungen │
                           └──────────────────┘
        Fiasco-Microkernel (arm64, EL2)  ·  QEMU virt, ohne KVM
```

Das ist der Kern aus dem Projekt l4re-unidir, ohne Einbahnstraße,
ohne durchgereichte Karten und ohne Host-Netze: nur zwei Abteile und ein
Kabel dazwischen.

---

## Inhalt

- [Schnellstart im Codespace](#schnellstart-im-codespace)
- [Bedienung](#bedienung)
- [Was passiert beim Start](#was-passiert-beim-start)
- [Warum arm64](#warum-arm64)
- [Selbst bauen](#selbst-bauen)
- [Projektstruktur](#projektstruktur)
- [Stolpersteine](#stolpersteine)

---

## Schnellstart im Codespace

1. Auf GitHub: **Code → Codespaces → Create codespace on main**.
   Beim ersten Öffnen wird QEMU installiert (ca. 1 min).
2. Im Terminal des Codespace:

   ```
   scripts/run.sh
   ```

   Beim ersten Mal lädt das Skript das fertige Image aus dem Release
   `latest` (gebaut von GitHub Actions) und startet QEMU.

3. Warten, bis beide Gäste ihren Selbsttest melden:

   ```
   vm1     | [vm1] SELFTEST OK
   vm2     | [vm2] SELFTEST OK
   ```

   Ohne KVM bildet QEMU alles in Software nach, auch die Virtualisierung.
   In GitHub Actions dauert es trotzdem nur etwa 10 Sekunden bis
   `SELFTEST OK`; auf einem kleinen Codespace kann es etwas länger sein.

## Bedienung

| Tasten | Wirkung |
|---|---|
| Strg+E, dann 1 | Konsole von vm1 |
| Strg+E, dann 2 | Konsole von vm2 |
| Strg+E, dann 0 | Ausgaben aller Abteile gemischt (nur lesen) |
| Strg+A, dann X | QEMU beenden |

> **Strg+E in VS Code:** VS Code benutzt Strg+E selbst („Gehe zu Datei“)
> und gibt die Taste sonst nicht an das Terminal weiter. Einmalig
> einstellen: Zahnrad unten links → *Settings* → nach
> `sendKeybindingsToShell` suchen → Häkchen setzen. Gilt sofort.
>
> Im **Browser** schnappt sich manchmal der Browser selbst Strg+E (Chrome:
> Suche in der Adressleiste). Dann den Codespace in der VS-Code-Desktop-App
> öffnen (GitHub → Code → Codespaces → „…“ → *Open in Visual Studio Code*)
> oder ohne Strg+E arbeiten: Enter drücken und am Prompt `cons>`
> `connect vm1` bzw. `connect vm2` eingeben (`help` zeigt alle Befehle).

In einem Gast (z. B. vm1):

```
sockpp ping 192.168.1.2              # 5 x UDP, 5 x TCP, je 64 Bytes
sockpp ping 192.168.1.2 -n 20 -s 1400
```

Ausgabe, Beispiel:

```
Ping-Pong mit 192.168.1.2 Port 7777: 5 x UDP, 5 x TCP, je 64 Bytes
UDP  #1       64 Bytes     4.650 ms
UDP  #2       64 Bytes     8.367 ms
...
TCP  verbunden              21.642 ms
TCP  #1       64 Bytes    27.144 ms
...
Ergebnis: UDP 5/5, TCP 5/5 ok
```

Die Zeiten sind in QEMU ohne KVM natürlich keine echten Messwerte, sie
zeigen nur, dass der Weg funktioniert.

`sockpp` im Überblick:

| Aufruf | Was es tut |
|---|---|
| `sockpp server` | Echo-Dienst auf UDP und TCP Port 7777 (läuft in beiden Gästen schon) |
| `sockpp ping HOST [-n ANZAHL] [-s BYTES] [-p PORT]` | Nachrichten hin und zurück, prüft den Inhalt, misst die Zeit |
| `sockpp selftest HOST [-w SEKUNDEN]` | wartet auf den anderen Gast, dann kurzer Ping, meldet `SELFTEST OK` |

Auch Busybox-Werkzeuge gehen: `ping 192.168.1.2`, `ip addr`, `nc`.

## Was passiert beim Start

| Schritt | Wer | Was |
|---|---|---|
| 1 | QEMU | lädt `bootstrap_sock.elf`: Fiasco, L4Re und alle Module in einer Datei |
| 2 | Fiasco | startet `moe` (Speicher) und `ned` mit `conf/sock.ned` |
| 3 | ned | startet `cons` (Konsole), `l4vio_net_p2p` (Netz) und zweimal `uvmm` |
| 4 | uvmm | bootet je einen Linux-Kernel (`Image`) mit der Ramdisk |
| 5 | `/init` im Gast | liest `sock_id` aus der Kernel-Kommandozeile, setzt 192.168.1.1 bzw. .2, startet `sockpp server` und den Selbsttest, öffnet eine Shell |

Jeder Gast bekommt genau eine CPU: vm1 läuft auf CPU 0, vm2 auf CPU 1
(`cpus` in `conf/sock.ned`, QEMU mit `-smp 2`). Mit mehreren virtuellen
CPUs pro Gast blieb unter QEMU ohne KVM eine davon hängen.

Die Verbindung zwischen den Gästen ist ein **virtio-Kabel** mit zwei Enden:
`l4vio_net_p2p` kopiert Pakete zwischen den Ringpuffern der beiden Gäste,
in beide Richtungen. Andere Wege gibt es nicht: Der Microkernel trennt die
Adressräume, und `ned` gibt jedem Gast nur seinen Kabelanschluss.

## Warum arm64

Ein Codespace hat kein KVM. QEMU muss also den Prozessor in Software
nachbilden. Für x86 kann QEMU dabei keine Hardware-Virtualisierung (VT-x)
anbieten, und ohne die läuft `uvmm` nicht. Für arm64 bildet QEMU die
Virtualisierung (EL2) auch in Software nach
(`-M virt,virtualization=true`). Deshalb ist hier alles für arm64 gebaut:
Fiasco, L4Re, die Gast-Kernel und die Programme in der Ramdisk.

## Selbst bauen

GitHub Actions baut bei jedem Push alles neu (`.github/workflows/build.yml`)
und startet das Image einmal in QEMU. Nur wenn beide Gäste `SELFTEST OK`
melden, ist der Build grün. Auf `main` landet das Image im Release
`latest`.

Selbst bauen geht auch, im Codespace oder auf Ubuntu 24.04:

```
scripts/deps.sh            # Cross-Compiler, QEMU und Werkzeuge
scripts/build.sh           # alles; erstes Mal 30-60 min
scripts/run.sh --lokal     # das selbst gebaute Image starten
scripts/selftest.sh        # ohne Bedienung: wartet auf SELFTEST OK
```

`build.sh` kann auch einzelne Schritte: `fetch fiasco l4re linux busybox
ramdisk image`, z. B. nach einer Änderung an `tools/sockpp.c` nur
`scripts/build.sh ramdisk image`.

Alle Quellen kommen in festen Versionen von GitHub (`scripts/versions.sh`):

| Was | Woher | Version |
|---|---|---|
| Fiasco, L4Re | github.com/kernkonzept | Wochenstand `r-2026-W43` |
| Gast-Kernel | github.com/torvalds/linux | `v6.12`, `tinyconfig` + `linux/sock-guest.config` |
| Ramdisk | github.com/mirror/busybox | `1_36_1`, statisch |

## Projektstruktur

```
l4re-sock/
├── conf/
│   ├── sock.ned              Start: cons, l4vio_net_p2p, zwei uvmm
│   └── modules.list          Inhalt des Images (Eintrag "sock")
├── tools/
│   ├── sockpp.c              Ping-Pong UDP/TCP
│   └── init                  Start im Gast: Adresse, Echo-Dienst, Selbsttest, Shell
├── linux/
│   └── sock-guest.config     Kernel-Optionen für die Gäste
├── scripts/
│   ├── versions.sh           feste Versionen aller Quellen
│   ├── deps.sh               Pakete installieren
│   ├── build.sh              alles bauen
│   ├── run.sh                Image holen und starten (Codespace)
│   ├── qemu.sh               QEMU-Aufruf
│   └── selftest.sh           Start ohne Bedienung, wartet auf SELFTEST OK
├── .devcontainer/            Codespace: Ubuntu 24.04 + QEMU + gh
└── .github/workflows/        Bauen, testen, Release
```

## Stolpersteine

| Symptom | Ursache | Lösung |
|---|---|---|
| `run.sh`: Download fehlgeschlagen | noch kein grüner Build auf `main` | in GitHub unter *Actions* nachsehen |
| Nach dem Start lange nichts | ohne KVM ist QEMU langsam, kleiner Codespace | etwas warten; bleibt es stehen, `QEMU_SMP=2` prüfen (jeder Gast braucht eine eigene CPU) |
| Tastatur reagiert nicht | Konsole „alle“ (Strg+E 0) nimmt keine Eingabe | Strg+E 1 oder 2 |
| QEMU lässt sich nicht beenden | Strg+C geht an den Gast | Strg+A, dann X; hilft nichts: Terminal schließen (Mülleimer) |
| Strg+E öffnet ein Menü in VS Code | VS Code fängt die Taste ab | `sendKeybindingsToShell` einschalten (siehe [Bedienung](#bedienung)) |
| Nach Strg+E passiert nichts, keine Taste kommt an | Image ohne Tastatureingabe (vor dem 31.10.) | `scripts/run.sh --neu` lädt das aktuelle Image |

---

Lernprojekt. Fiasco und L4Re: © Kernkonzept GmbH und andere, siehe deren
Lizenzen. Eigener Code hier: MIT.
