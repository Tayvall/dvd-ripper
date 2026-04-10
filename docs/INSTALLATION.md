# Installation

## Automatic (recommended)

```bash
bash install.sh
```

Supports:
- **Arch / CachyOS / Manjaro** — uses pacman and AUR (yay)
- **Ubuntu / Debian / Linux Mint / Pop!_OS** — uses apt
- **Fedora / RHEL / Rocky** — uses dnf

MakeMKV is built from source automatically if no AUR package is available.

---

## Manual / Build from Source

If you prefer to keep everything contained and isolated, see the [Distrobox guide](DISTROBOX.md) first — it is the recommended approach for source builds.

### 1. Install build dependencies

**Arch / CachyOS / Manjaro:**
```bash
sudo pacman -S base-devel openssl expat ffmpeg mesa qt5-base zlib curl jq handbrake-cli libdvdcss eject python
```

**Ubuntu / Debian / Linux Mint / Pop!_OS:**
```bash
sudo apt install build-essential pkg-config libssl-dev libexpat1-dev libavcodec-dev \
    libgl1-mesa-dev qtbase5-dev zlib1g-dev curl jq handbrake-cli eject python3 wget
```

**Fedora / RHEL / Rocky:**
```bash
sudo dnf install gcc gcc-c++ make openssl-devel expat-devel ffmpeg-devel \
    mesa-libGL-devel qt5-qtbase-devel zlib-devel curl jq HandBrake-cli eject python3 wget
```

---

### 2. Build MakeMKV from source

```bash
wget https://www.makemkv.com/download/makemkv-oss-1.18.3.tar.gz
wget https://www.makemkv.com/download/makemkv-bin-1.18.3.tar.gz

tar -xzf makemkv-oss-1.18.3.tar.gz
cd makemkv-oss-1.18.3 && ./configure && make && sudo make install && cd ..

tar -xzf makemkv-bin-1.18.3.tar.gz
cd makemkv-bin-1.18.3 && make && sudo make install && cd ..
```

---

### 3. Install libdvdcss

**Arch / CachyOS:**
```bash
sudo pacman -S libdvdcss
```

**Ubuntu / Debian:**
```bash
sudo apt install libdvd-pkg
sudo DEBIAN_FRONTEND=noninteractive TERM=xterm-256color dpkg-reconfigure libdvd-pkg
```

> **Note:** The Ubuntu `libdvd-pkg` post-install script is known to fail with non-standard terminals (e.g. Alacritty). If it errors, build from source instead:

**From source (any distro):**
```bash
wget https://download.videolan.org/pub/libdvdcss/1.4.3/libdvdcss-1.4.3.tar.bz2
tar -xjf libdvdcss-1.4.3.tar.bz2
cd libdvdcss-1.4.3 && ./configure && make && sudo make install && sudo ldconfig
```

---

### 4. Add yourself to the optical group

```bash
sudo usermod -a -G optical $USER
```

Log out and back in for the group change to take effect. On some distros the group may be named `cdrom` instead:

```bash
sudo usermod -a -G cdrom $USER
```

---

### 5. Run setup

```bash
bash setup.sh
```

---

## Verify installation

```bash
which makemkvcon
which HandBrakeCLI
ldconfig -p | grep dvdcss
```

All three should return paths. If anything is missing, re-run `install.sh` or check the [Troubleshooting guide](TROUBLESHOOTING.md).
