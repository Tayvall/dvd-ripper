# Kodi Setup

## Adding your library

1. Open Kodi and go to **Settings > Media > Library**
2. Under **Video**, select **Add video source**
3. Browse to your `Movies` folder (e.g. `/media/storage/Movies`)
4. Set the content type to **Movies**
5. Set the scraper to **The Movie Database**
6. Select **OK** and allow Kodi to scan

Files named `Movie Title (Year).mkv` will scrape metadata, posters, and descriptions automatically.

---

## File naming

The script outputs files in the format Kodi expects:

```
Movies/
└── The Lion King (1994)/
    └── The Lion King (1994).mkv
```

The year in brackets is important — without it Kodi may match the wrong film for titles that have remakes or multiple versions.

---

## Audio output

If you are running Kodi on a headless Ubuntu Server machine connected via HDMI, you may need to set the audio output manually.

1. Go to **Settings > System > Audio**
2. Set **Audio output device** to your HDMI output
3. On ALSA systems this is typically `ALSA: HDA Intel MID HDMI 0`

To set this at the system level, add to `/etc/asound.conf`:
```
defaults.pcm.card 1
defaults.pcm.device 7
defaults.ctl.card 1
```

Run `aplay -l` to find the correct card and device numbers for your system.

---

## Offline use

Once metadata has been scraped while connected to the internet, Kodi stores it locally. The library will work fully offline after the initial scan — useful if the media PC is not permanently networked.

---

## Jellyfin (future)

Jellyfin is a self-hosted alternative to Kodi that supports streaming to other devices on your network. The same file naming convention works with Jellyfin. See the [Roadmap](../README.md#roadmap) for planned support.
