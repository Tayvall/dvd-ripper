# Configuration

## Setup Wizard

Running `setup.sh` generates your config automatically:

```bash
bash setup.sh
```

It will:
- Detect all optical drives on your system
- Detect large storage drives and their mount points
- Walk you through encoding quality selection
- Prompt for your TMDB API credentials

To reconfigure at any time, just re-run `setup.sh`.

---

## Config file location

```
~/.config/dvd-ripper/dvd_rip.conf
```

To edit manually:
```bash
nano ~/.config/dvd-ripper/dvd_rip.conf
```

See `dvd_rip.conf.example` in the repo root for a fully documented reference.

---

## Config options

### Device paths

```bash
DVD_DEVICE="/dev/sr0"
```

Your optical drive. Run `lsblk | grep rom` to find it. USB drives are usually `/dev/sr0`, internal drives may be `/dev/sr1` if a USB drive is also connected.

---

### Storage paths

```bash
MOVIES_DIR="/media/storage/Movies"
RIPS_DIR="/media/storage/rips"
LOG_DIR="/media/storage/logs"
```

All three should ideally be on the same drive. `RIPS_DIR` holds temporary raw MKV files during ripping (up to ~8GB per disc) and is cleaned up automatically after encoding. Keep `RIPS_DIR` and `LOG_DIR` off your main system drive.

---

### Tool paths

```bash
MAKEMKV="/usr/bin/makemkvcon"
HANDBRAKE="/usr/bin/HandBrakeCLI"
```

Set automatically by `install.sh`. Only change these if you built the tools to a custom location.

---

### Encoding

```bash
HB_PRESET="H.264 MKV 576p25"
MIN_TITLE_SECONDS=1200
```

**HB_PRESET** — the HandBrake encoding preset. Common options:

| Preset | Quality | File size | Speed |
|---|---|---|---|
| H.264 MKV 576p25 | Good | ~800MB | Fast |
| H.264 MKV 720p30 | Better | ~1.5GB | Fast |
| H.265 MKV 576p25 | Good | ~500MB | Slower |

Run `HandBrakeCLI --preset-list` to see all available presets.

**MIN_TITLE_SECONDS** — titles shorter than this are skipped. 1200 (20 minutes) skips most bonus features and trailers. Lower this if you want extras included, raise it if you're still getting short clips ripped.

---

### TMDB

```bash
TMDB_API_KEY="your_key_here"
TMDB_TOKEN="your_token_here"
```

Used for automatic movie name detection from disc metadata. Without these set, the script falls back to manual name entry for every disc.

#### Getting a TMDB API key

1. Create a free account at [themoviedb.org](https://www.themoviedb.org)
2. Go to **Settings > API**
3. Request an API key — approved instantly for personal use
4. Copy the **API Read Access Token** (long JWT string) into `TMDB_TOKEN`
5. Copy the **API Key (v3 auth)** (short string) into `TMDB_API_KEY`

Both values are needed. Enter them during `setup.sh` or paste them directly into your config file.
