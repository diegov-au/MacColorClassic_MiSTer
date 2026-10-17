# Macintosh Color Classic core for MiSTer

An FPGA implementation of the **Apple Macintosh Color Classic** (1993) for the
[MiSTer](https://github.com/MiSTer-devel/Main_MiSTer/wiki) platform: the
compact Mac with a 10" Trinitron, a **68030** with its PMMU, a 512 × 384 colour
screen, ADB keyboard and mouse, SCSI, and an internal **1.44 MB SuperDrive**.

The core runs the **Color Classic's own 1 MB ROM** and the **real firmware of
its Cuda system controller**, so it starts like the real machine: Cuda brings
the 68030 out of reset, then the start-up chime, the happy Mac and System 7.1.
It boots from hard disk images, reads and writes 800K and 1.44 MB floppies,
and keeps its PRAM and clock between sessions.

![Macintosh Color Classic ](1-maccolorclassic.png)

---

## The machine model

**Macintosh Color Classic (M1600), 1993.** Built on the **Macintosh
Classic** core (the method, the SCSI, the floppy drive, PRAM and the SDRAM),
with the Color Classic's **Spice**, **Cuda**, and **68030** with its PMMU and caches.

| | |
|---|---|
| **CPU** | Motorola 68030 at 15.6672 MHz, with its PMMU and 256-byte instruction and data caches ([TG68K](https://github.com/TobiFlex/TG68K.C), 68030 fork). No FPU, as on a stock Color Classic |
| **ROM** | The Color Classic's 1 MB ROM (version `$067C`, checksum `ECD99DC0`) |
| **System controller** | **Cuda** (68HC05) running Apple's own firmware (`341S0417`): ADB, the clock, PRAM, resets |
| **Memory** | 4 MB (stock), 6, 8 or 10 MB (a memory SIMM of 2, 4 or 8 MB) |
| **Display** | 512 × 384 in 1, 2, 4, 8 and 16 bits per pixel (512K of VRAM, the upgraded machine); optional 640 × 480 (see below) |
| **Floppy** | One internal SuperDrive on a SWIM2: 400K/800K GCR and 720K/1.44 MB MFM, read and write |
| **Hard disk** | SCSI (53C80): internal disk at ID 0, external at ID 5 |
| **Keyboard / mouse** | ADB, from the MiSTer's USB keyboard and mouse |
| **Sound** | Spice's Apple Sound Chip, through the DFAC II's volume steps |
| **Clock / PRAM** | Cuda's clock and 256 bytes of PRAM, saved to a file |
| **Software** | Tested: System 7.1 with System Enabler 401 (not included) |

Runs equivalant to a real Color Classic's speed: Speedometer gives about
the real machine's figures (CPU 112%, Graphics 115% of the original).

### Color Classic QOL changes

- **640 × 480 mode.** A Color Classic's screen is fixed at 512 × 384, but its
  Spice chip also drives 640 × 480 (Apple's own upgraded analog board). The
  optional **640x480** resolution tells the ROM a 640 × 480 monitor is attached
  and the stock ROM sets the mode up itself. With 512K of VRAM it tops out at
  **256 colours**, as on a real machine.

---

## Core features

### Processor and system

- **The real ROM and the real Cuda firmware**, unmodified, including the
  ROM's start-up tests and the chime.
- **The 68030's PMMU and caches**, so **24-bit and 32-bit addressing** both
  work (Memory control panel).
- **4, 6, 8 or 10 MB** of RAM.

### Video

- **Original** is the Color Classic's 512 × 384, in Black & White up to
  Thousands of colours (Monitors control panel).
- **640x480** gives a larger desktop at up to 256 colours (see above).

### Sound

- The start-up chime, alert sounds and application sound through Spice's
  Apple Sound Chip. The **Sound control panel's volume** works.
- **Mono**, as the Color Classic's speaker: system sounds are mono, and both
  outputs carry the same sound.

### Floppy

- One internal **SuperDrive**: **400K and 800K GCR, 720K and 1.44 MB MFM**,
  read **and write**. Copying to and from 800K and 1.44 MB disks works, and
  the files survive eject and remount. Erasing a disk has not been tested yet.
- Write-protected by default (**Floppy Write Protect**), so a disk is not
  changed until you choose. Changes are written back to the `.dsk` on the SD
  card sector by sector; the **user LED** stays on until they all are.

### Hard disks

- **Internal** (SCSI ID 0) and **external** (SCSI ID 5) `.vhd` images up to
  2 GB, read/write. Main remembers both.

### PRAM and clock

- **Mount PRAM** keeps the control panel settings, the startup disk and the
  Chooser in a 512-byte `.nvr` file. Changes are saved back automatically.
- The clock is set from the MiSTer's time, daylight saving included.

---

## OSD options

| Option | What it does |
|---|---|
| **Mount Floppy** | The internal SuperDrive: `.dsk`, raw images (see *Disk images*) |
| **Floppy Write Protect** | On (default) / Off - Off lets the Mac write to the floppy |
| **Mount Internal HDD** | The internal hard disk, SCSI ID 0, `.vhd`; remembered at the next start |
| **Mount External SCSI** | An external hard disk, SCSI ID 5, `.vhd`; remembered at the next start |
| **Mount PRAM** | The `.nvr` PRAM file; remembered and loaded at every start |
| **Resolution** | Original (512 × 384) / 640x480 - takes effect on **Reset** |
| **Aspect ratio** | Original / Full Screen / two custom ratios |
| **Scale** | Normal / V-Integer / Narrower HV-Integer / Wider HV-Integer |
| **Memory** | 4MB / 6MB / 8MB / 10MB - takes effect on **Reset** |
| **Reset** | Restarts the Mac; also the MiSTer's reset button |

### About PRAM

**Mount PRAM** takes a 512-byte `.nvr` file; an empty one is in `releases/`
(`MacColorClassic.nvr`). Main remembers it and loads it at every start.
Changes the Mac makes - in the control panels, the Chooser or Startup Disk -
are saved back to the file about 2 s after the last change, and whenever the
OSD is opened.

At start-up Cuda waits until the PRAM file is loaded, so the settings are
always the file's. Without a PRAM file, PRAM starts blank at each power-on, as
on a Color Classic whose battery has run down; the Mac still boots, and
System 7 sets its defaults.

Mounting a PRAM file while the Mac is running does not restart it: the file's
settings take effect at the next **Reset**, and nothing is saved to the file
until then.

---

## Installing on MiSTer

The core name is **`MacColorClassic`**, which is what MiSTer uses to find
everything.

```
/media/fat/_Computer/MacColorClassic_YYYYMMDD.rbf
/media/fat/games/MacColorClassic/
        boot0.rom
        boot1.rom
        *.dsk  *.vhd  *.nvr
```

- **`boot0.rom` is your Macintosh Color Classic ROM** (1 MB, checksum
  `ECD99DC0`, version `$067C`).
- **`boot1.rom` is the Cuda firmware**, `341S0417` (4,352 bytes).

Neither is supplied. The core loads them at start-up; nothing of either is in
the bitstream.

---

## Disk images

| Kind | Extension | Notes |
|---|---|---|
| **Floppy** | `.dsk` | Raw sector images (DiskDup). **Read/write** unless Floppy Write Protect is on or the file is read-only |
| **Hard disk** | `.vhd` | Raw SCSI disk images with a partition map and driver, up to 2 GB (HFS). **Read/write** |
| **PRAM** | `.nvr` | 512 bytes |

### Floppy images

The SuperDrive reads raw images of exactly these sizes:

| Disk | Format | Image size |
|---|---|---|
| 400K | GCR | 409,600 bytes |
| 800K | GCR | 819,200 bytes |
| 720K | MFM | 737,280 bytes |
| 1.44 MB | MFM | 1,474,560 bytes |

**DiskCopy 4.2 images** (an 84-byte header and tag data) must be converted to
raw first. **Eject a disk from within the Mac** before mounting another, and
wait for the user LED to go out: an image may be in the middle of being
written.

### Hard disk images

A raw `.img` disk image is the same format as `.vhd`: rename it.
[Disk Jockey](https://diskjockey.onegeekarmy.eu/) makes suitable images, with
the partition map and SCSI driver the Mac needs.

**The System must be one made for a Color Classic:** System 7.1 with
**System Enabler 401**, or 7.1.1 Pro / 7.5.x installed for this model. A 7.1
disk installed for another Mac (with another enabler) is read, but the ROM
goes back to the flashing ?-disk without a message, as a real Color Classic
does.

---

## Known limitations

- **640x480 is not a stock Color Classic.** It is the screen of Apple's
  upgraded analog board; 256 colours at most.
- **No FPU:** the FPU (the socket is empty on a stock board), sound input
  (the microphone), the serial ports (the SCC answers, nothing is connected),
  the front-panel volume buttons, the keyboard's **Power** key, and stereo
  through the headphone jack.
- **Real-machine quirks, not core bugs** (each checked against MAME):
  - **MacWrite 2.2 and MacPaint 2.0** are not 32-bit clean: turn 32-bit
    addressing off for them.
  - **Microsoft Works 2.0** in 256 colours with 24-bit addressing writes over
    memory it does not own and crashes; with 32-bit addressing it reports
    not enough memory.
  - In 24-bit addressing, with an external SCSI disk mounted, the System heap
    can run short and alert sounds go quiet (the menu bar flashes instead).

---

## Keyboard reference

The keys follow the way macOS maps a PC keyboard. Left and right modifiers both
work, and the numeric keypad is the Mac's.

| PC key | Mac key |
|---|---|
| `Windows` | Command (⌘) |
| `Alt` | Option (⌥) |
| `Ctrl` | Control |
| `Caps Lock` | Caps Lock |

**F12** stays the MiSTer's OSD key.

**Mouse:** set the pointer speed in the **Mouse** control panel as usual.

---

## Credits and attributions

### Core development

- **Diego Viso** ([@diegov-au](https://github.com/diegov-au)) - core development, hardware testing and verification.

### Built on

- The **Macintosh Classic** MiSTer core by **Diego Viso** - the starting point
  of this tree: the SCSI, the SuperDrive and its floppy loader and writer,
  PRAM persistence, the clock and the SDRAM.
- The **Mac LC** MiSTer core by **danifunker** - the machine: the V8 glue,
  video and pseudo-VIA assited with development of Spice, Cuda,
  the Apple Sound Chip and the ADB devices.
- **[TG68K](https://github.com/TobiFlex/TG68K.C)** by **Tobias Gubener**,
  through **apolkosnik**'s 68030 fork with its PMMU (Minimig-AGA MiSTer,
  `030_mmu`) - the CPU, with this core's fixes.
- **68HC05 core** by **Ulrich Riedel** (UR6805) - runs Cuda's firmware.
- **VIA 6522** by **Gideon Zweijtzer**.
- **NCR 5380 SCSI**, based on **minimigmac** by **Benjamin Herrenschmidt**.

### Special thanks

- **[MAME](https://www.mamedev.org/)** and its Mac drivers (`maccclas`) - the
  only emulator of the Color Classic, and this core's reference for Spice,
  Cuda, SWIM2 and the Sound Chip.
- **[Snow](https://github.com/twvd/snow)** by **twvd** - this core's
  reference for the 68030 and its PMMU.
- **[Musashi](https://github.com/kstenerud/Musashi)** by **Karl Stenerud** -
  its disassembler drives the simulation harness's traces.

### Framework

- **[MiSTer](https://github.com/MiSTer-devel/Main_MiSTer)** framework (`sys/`) by
  **Alexey Melnikov (Sorgelig)**, **Till Harbaum** and the MiSTer-devel community -
  HPS interface, video scaling, audio output and the OSD.

---

## Licence

**GPL-3.0**, as the components it is built from (TG68K is LGPL-3.0; the SDRAM
controller is GPL-3.0; the MiSTer framework is GPL-2.0 or later). Apple's ROM,
Cuda firmware and system software are not part of this core.

---

This core was developed with the assistance of AI. The RTL changes, the
simulation harness and the documentation were written collaboratively with AI,
with every behaviour checked against the Color Classic's ROM, MAME, the Snow
emulator, Apple's documentation and a real DE10-Nano.
