# Troubleshooting

## MakeMKV can't find the drive

```bash
ls -la /dev/sr0
groups
```

Check that your user is in the `optical` (or `cdrom`) group. If not:

```bash
sudo usermod -a -G optical $USER
```

Log out and back in, then try again. You can also load the SCSI generic kernel module which some USB drives require:

```bash
sudo modprobe sg
```

To make this persistent across reboots:

```bash
echo "sg" | sudo tee /etc/modules-load.d/sg.conf
```

---

## libdvdcss errors on encrypted discs

```bash
ldconfig -p | grep dvdcss
```

If nothing is returned, libdvdcss is not installed. See the [Installation guide](./INSTALLATION.md) for distro-specific install steps or build from source.

---

## Disc not detected (dd fails)

```bash
dd if=/dev/sr0 of=/dev/null bs=2048 count=1
```

If this fails, the drive is either not mounted correctly or the disc is unreadable. Try:

- Ejecting and reinserting the disc
- Cleaning the disc
- Checking `dmesg | grep -i sr` for drive errors

---

## TMDB auto-naming not working / falling back to manual

Inside a Distrobox container, the disc label is read via `distrobox-host-exec sudo blkid`. This requires passwordless sudo access for `blkid` on the host.

See the [Distrobox guide](./DISTROBOX.md#allowing-passwordless-blkid-required) for setup instructions for your distro.

To test manually inside the container:

```bash
distrobox-host-exec sudo blkid 2>/dev/null | grep '/dev/sr'
```

If this returns nothing with a disc inserted, the sudoers rule is either missing or pointing to the wrong `blkid` path. Check which path is correct on your host:

```bash
distrobox-host-exec which blkid
```

---

## TMDB returns wrong movie

The script shows the top TMDB result and lets you press Enter to accept or type a correction. If the disc label is ambiguous (e.g. `DISC_1`), type a more specific search term when prompted and the script will re-query TMDB.

---

## HandBrake encoding is slow

Check how many CPU cores HandBrake is using:

```bash
top
```

HandBrakeCLI should show near-maximum CPU usage. If it's single-threaded, check your preset — some presets limit thread count.

If you have an NVIDIA GPU, NVENC hardware encoding is significantly faster. Change your preset in the config to use an NVENC variant:

```bash
HB_PRESET="H.264 MKV 576p25"
```

And add `--encoder nvenc_h264` to the HandBrake flags in `dvd_rip.sh`. GPU encoding typically reduces a DVD encode from 15–20 minutes to under 2 minutes.

---

## File names have a leading newline (`\nMovie Name`)

A bare `echo ""` inside the `resolve_movie_name` function was going to stdout and getting captured into the filename. Make sure all `echo ""` lines inside that function have `>&2` appended. This is fixed in the current version of the script.

If you have existing files with this issue, rename them:

```bash
for dir in /path/to/Movies/$'\n'*; do
    newname="${dir/$'\n'/}"
    mv "$dir" "$newname"
done
```

---

## Rip fails with "file name too long"

This means log output leaked into the `movie_name` variable. All `log_info`, `log_warn`, and `echo` display lines inside `resolve_movie_name` and `get_disc_title` must redirect to stderr with `>&2`. This is fixed in the current version of the script.

---

## Script exits but HandBrake is still running

This is intentional — HandBrake encodes in the background and the script exits cleanly without killing it. Check if it's still running:

```bash
ps aux | grep HandBrake
```

Watch encode progress:

```bash
tail -f ~/logs/*handbrake.log | grep "%"
```

Do not power off until encoding is complete.

---

## Ubuntu libdvd-pkg terminal error

```
Error opening terminal: alacritty
```

The `libdvd-pkg` post-install script uses `dialog` which doesn't support non-standard terminals. Fix with:

```bash
sudo DEBIAN_FRONTEND=noninteractive TERM=xterm-256color dpkg-reconfigure libdvd-pkg
```

If it still fails, build libdvdcss from source — see the [Installation guide](./INSTALLATION.md).
