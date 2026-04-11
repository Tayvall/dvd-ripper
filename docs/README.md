# 📀 dvd-ripper

A command-line DVD ripping and encoding tool for Linux. Rips your DVD collection to MKV files, automatically names them using TMDB metadata, and outputs a Kodi-compatible library structure.

---

## Features

- Automatic movie name detection via TMDB API
- Continuous disc feeding — insert and go
- Background HandBrake encoding while you rip the next disc
- Live encode monitor with progress bars, ETA, and fps (`hb_monitor.sh`)
- Kodi-compatible file naming (`Movie Name (Year)/Movie Name (Year).mkv`)
- Per-session and per-film logs
- Works natively or inside a Distrobox container

---

## Quick Start

```bash
git clone https://github.com/yourusername/dvd-ripper.git
cd dvd-ripper
bash install.sh    # install dependencies
bash setup.sh      # configure drives and preferences
bash dvd_rip.sh    # start ripping
```

To monitor encoding progress in a separate terminal while ripping:

```bash
bash hb_monitor.sh
```

---

## Repository Structure

```
dvd-ripper/
├── install.sh           # installs all dependencies (Arch, Ubuntu, Fedora)
├── uninstall.sh         # removes all installed tools and config
├── setup.sh             # first-run config wizard — auto-detects drives
├── dvd_rip.sh           # main ripping and encoding script
├── hb_monitor.sh        # live HandBrake progress monitor
├── dvd_rip.conf.example # documented config reference
└── docs/
    ├── INSTALLATION.md
    ├── DISTROBOX.md
    ├── CONFIGURATION.md
    ├── KODI.md
    └── TROUBLESHOOTING.md
```

---

## Requirements

| Tool | Purpose |
|---|---|
| MakeMKV | Rips raw DVD data to MKV |
| HandBrakeCLI | Compresses MKV to final file |
| libdvdcss | Decrypts CSS-encrypted DVDs |
| curl + jq | TMDB API lookup |

`install.sh` handles all of these automatically and supports Arch/CachyOS, Ubuntu/Debian, and Fedora.

---

## Further Reading

| Guide | Description |
|---|---|
| [Installation](./INSTALLATION.md) | Manual install, build from source, distro-specific steps |
| [Distrobox](./DISTROBOX.md) | Running inside a container — recommended for source builds |
| [Configuration](./CONFIGURATION.md) | Config file reference, TMDB API setup, encoding presets |
| [Kodi Setup](./KODI.md) | Adding your library to Kodi |
| [Troubleshooting](./TROUBLESHOOTING.md) | Common issues and fixes |

---

## Roadmap

- [ ] GUI frontend
- [ ] ~~Jellyfin library support~~
- [x] Blu-ray support
- [ ] NVENC/GPU encoding preset in setup wizard
- [ ] Resume interrupted encodes
- [ ] Simplify the look of setup script

---

## Licence

MIT
