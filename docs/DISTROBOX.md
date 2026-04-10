# Distrobox Usage

If you want to keep your build environment isolated from your host system — or if you're having trouble getting MakeMKV to access your optical drive natively — Distrobox is the recommended approach for source builds.

Distrobox runs a full Linux distribution inside a container while sharing your home directory and hardware devices with the host. Unlike Docker, it requires no daemon and gives you seamless access to `/dev/sr0` and your storage drives without complex configuration.

---

## Setup

**1. Install Distrobox on your host**

Arch / CachyOS:
```bash
sudo pacman -S distrobox
```

Ubuntu / Debian:
```bash
sudo apt install distrobox
```

Fedora:
```bash
sudo dnf install distrobox
```

**2. Create the container**

```bash
distrobox create --name media-rip --image ubuntu:24.04 --additional-flags "--privileged"
```

The `--privileged` flag gives the container full access to host devices including your optical drive and docked storage drives.

**3. Enter the container**

```bash
distrobox enter media-rip
```

**4. Install dependencies inside the container**

```bash
bash install.sh
```

**5. Run setup and start ripping**

```bash
bash setup.sh
bash dvd_rip.sh
```

---

## How disc detection works inside Distrobox

The script uses `distrobox-host-exec` to read the disc volume label from the host rather than from inside the container, since the container's `/dev/sr0` may not expose the label correctly.

This command runs on the host:
```bash
distrobox-host-exec sudo blkid
```

Because this invokes `sudo` on the host, **you need to allow passwordless `blkid` execution** for your user. Without this, the disc title lookup will silently fail and fall back to manual name entry.

---

## Allowing passwordless blkid (required)

This is a one-time setup on your **host machine**, not inside the container.

### Arch / CachyOS / Manjaro

```bash
sudo EDITOR=nano visudo -f /etc/sudoers.d/dvdrip
```

Add:
```
yourusername ALL=(ALL) NOPASSWD: /usr/bin/blkid
```

Save with `Ctrl+O`, then `Ctrl+X`.

### Ubuntu / Debian / Linux Mint / Pop!_OS

```bash
sudo EDITOR=nano visudo -f /etc/sudoers.d/dvdrip
```

Add:
```
yourusername ALL=(ALL) NOPASSWD: /usr/bin/blkid, /usr/sbin/blkid
```

> **Note:** Ubuntu/Debian systems sometimes have `blkid` at `/usr/sbin/blkid` rather than `/usr/bin/blkid`. Both paths are included above to cover both cases.

### Fedora / RHEL / Rocky

```bash
sudo EDITOR=nano visudo -f /etc/sudoers.d/dvdrip
```

Add:
```
yourusername ALL=(ALL) NOPASSWD: /usr/sbin/blkid
```

---

## Verify the setup

Inside the container, test that disc detection works:

```bash
distrobox-host-exec sudo blkid 2>/dev/null | grep '/dev/sr'
```

With a disc inserted this should return something like:
```
/dev/sr0: UUID="..." LABEL="THE_LION_KING" BLOCK_SIZE="2048" TYPE="udf"
```

If it returns nothing, double check:
- The sudoers rule was saved correctly (`sudo cat /etc/sudoers.d/dvdrip`)
- The correct `blkid` path is in the rule (`which blkid` on the host)
- A disc is actually inserted and readable (`dd if=/dev/sr0 of=/dev/null bs=2048 count=1`)

---

## Notes

- The container persists between sessions — you only need to run `install.sh` once
- Re-enter at any time with `distrobox enter media-rip`
- Your home directory and `/mnt` paths are shared between host and container
- If you delete the container with `distrobox rm`, all installed packages inside it are lost and you will need to re-run `install.sh`
