# Changelog

All notable changes to this project will be documented in this file.

## [1.0.6] - 2026-06-30

### Added
- **gpsd-watcher diagnostic logging** — The watcher now logs structured messages to the systemd journal: startup/shutdown events, connection status (`[gpsd-watcher] Connected, WATCH sent`), periodic status every 10 minutes (uptime, valid TPV count, null-island count, seconds since last valid TPV), and stale-data warnings. Check logs with `journalctl -u gpsd-watcher --since "1h ago"`.
- **gpsd-watcher auto-reconnect** — If no valid (non-0,0) TPV is received for >11 minutes (STALE_THRESHOLD), the watcher closes its TCP connection and reconnects with a fresh `?WATCH` subscription. Also reconnects on socket errors, connection resets, or empty recv. Waits 10s between reconnection attempts.
- **gpsd-watcher daily restart timer** — `gpsd-watcher-restart.timer` fires at 4:00 AM daily, triggering `gpsd-watcher-restart.service` (oneshot) which restarts the watcher. Prevents long-running TCP connections from silently going stale. Enabled and started automatically by install.sh.

### Changed
- **gpsd-watcher rewritten with reconnection loop** — Original script had a single flat connection with no recovery; if the socket died or went stale, the process would exit and systemd would restart it (losing a few seconds of coverage). New version has an outer `while True` loop: `connect_and_watch()` runs until disconnection/stale/error, then sleeps and reconnects. No coverage gap.

### Fixed
- **gpsd-watcher stale connection** — After running for multiple days, the watcher's persistent TCP connection to gpsd could silently stop receiving fresh TPV data, causing the TPV cache to return 0,0 coordinates (null island) while the phone was still transmitting correctly. Root cause unclear (possibly gpsd internal client management, TCP zombie state, or phone battery optimization causing gpsd to emit 0,0 pings that the watcher cached and never refreshed). Fixed by: (1) auto-reconnect when no valid TPV for >11 min, (2) daily restart timer at 4 AM, (3) diagnostic logging to detect recurrence.
- **gpsd-watcher overwrites cache with 0,0** — The watcher wrote null-island (0,0) TPV reports to `/tmp/gpsd-last-tpv.json`, overwriting the last known good position. This caused `gpsloc` and `location-updater` to report 0,0 instead of the last valid location during gaps between phone transmissions. Now the watcher only updates the cache when it receives a valid (non-0,0) TPV, preserving the last good position until fresh data arrives.

## [1.0.5] - 2026-06-27

### Added
- **gpsloc `--tpv` flag** — Outputs raw TPV JSON from gpsd as a single line (for programmatic consumers like location-updater). Existing flags (`--latlon`, `--human`, `--lat`, `--lon`, default JSON) unchanged.
- **Speed, heading, altitude, accuracy in location cache and history** — `location.json` and `location-history.jsonl` now include `speed` (m/s), `track` (heading in degrees), `alt` (altitude in meters), and `eph` (horizontal accuracy in meters) alongside the existing lat/lon/address/timestamp fields. Enables distinguishing driving from walking, detecting brief stops vs. destinations, and richer location reports.
- **gpsloc `--human` now shows heading and accuracy** — Previously only showed lat/lon/alt/speed/fix.

### Changed
- **location-updater uses `gpsloc --tpv` instead of `gpsloc --latlon`** — Gets full TPV data in one call instead of just coordinates. New `get_tpv()` function replaces `get_latlon()`.
- **location-updater filters out 0,0 coordinates** — Skips null-island pings (phone GPS without satellite fix) instead of recording them as valid entries.
- **location-updater history window extended to 48h** — Was 24h, now matches the `location-prune` cron interval for consistency.

## [1.0.4] - 2026-06-25

### Fixed
- **location-updater wrote to /root/ instead of user home** — Service ran as root with no `User=` directive, so `~/.hermes/` resolved to `/root/.hermes/`. Fixed by adding `Environment=HOME=__HOME__` to the service template, which install.sh replaces with the actual home directory at install time. No hardcoded usernames.
- **gpsd-watcher had the same bug** — Also writes to `~/.hermes/location.json`. Same fix applied.
- **install.sh now templates service files** — Replaces `__HOME__` placeholder in `.service` files with the detected home directory (handles `sudo` via `SUDO_USER`).

## [1.0.3] - 2026-06-25

### Changed
- **GPS AgentBridge now recommended as primary Android app** — All documentation updated to recommend [GPS AgentBridge](https://github.com/Madvulcan/GPS-AgentBridge-Android) (our companion app with distance-based transmission) over gpsdRelay. gpsdRelay remains as an alternative for users who prefer F-Droid.
- **SKILL.md** — Architecture diagram, phone setup table, transmission interval guidance, and troubleshooting updated to reflect GPS AgentBridge as primary.
- **AgentInstructions.md** — Phase 3 now has a full GPS AgentBridge walkthrough (APK install, onboarding flow, destination server setup) with gpsdRelay as alternative.
- **README.md** — Platform table, architecture diagram, and manual setup steps updated.
- **install.sh** — Summary output now shows GPS AgentBridge with download URL and install command.

## [1.0.2] - 2026-06-25

### Fixed
- **gpsloc timeout with intermittent UDP sources** — gpsd only emits TPV when a fresh NMEA sentence arrives and a client is actively subscribed. With the phone app transmitting every ~10 min (max interval timer), `gpsloc` almost always timed out (5s). Now reads from a persistent TPV cache first, falling back to live connection only if cache is stale.
- **install.sh missed non-.py scripts** — Install script only copied `*.py` files, skipping `gpsloc`, `location-updater`, `gmaps`, `gpsnear`, etc. Now copies all scripts regardless of extension.
- **install.sh hardcoded service list** — Only deployed `gpsd.service` and `location-updater.service`. Now dynamically copies all `systemd/*.service` files.

### Added
- **gpsd-watcher service** — Persistent gpsd subscriber that caches the latest TPV to `/tmp/gpsd-last-tpv.json` and updates `~/.hermes/location.json`. Keeps gpsd "warm" so `gpsloc` and `location-updater` work instantly instead of waiting for the next phone transmission.

### Changed
- **gpsloc** — Now checks persistent TPV cache before connecting to gpsd. Falls back to live connection only if cache is stale (>11 min). Makes `gpsloc --human` instant instead of timing out.
- **install.sh** — Refactored script and service deployment to be dynamic instead of hardcoded.

## [1.0.1] - 2026-06-22

### Fixed
- **GPSD_HOST semantics** — Split into `GPSD_HOST` (agent→gpsd connection, always `127.0.0.1`) and `PHONE_TARGET_HOST` (phone app destination IP). Previously both uses shared the same config key, causing agent scripts to fail when the phone needed a different IP.
- **location-updater.service missing** — Added `systemd/location-updater.service` to the repo. Install script now auto-copies and enables it.
- **config.py import error** — Scripts installed to `/usr/local/bin/` couldn't find `config.py`. Install script now copies all `.py` scripts and `config.py` to `/usr/local/bin/`.
- **places vs places.py mismatch** — Install script's hardcoded script list didn't match actual filenames. Now auto-detects all `.py` files in `scripts/` directory.
- **Config path under sudo** — Running install script with `sudo` created config in `/root/.hermes/` instead of the user's home. Now detects `SUDO_USER` and writes to the correct home directory.
- **pipx not installed** — Added `python3-pipx` to system package dependencies so `invisible_playwright` can be installed.
- **Python 3.12 compatibility** — Fixed `addsubparsers` → `add_subparsers` in `places.py`.
- **gpsd systemd service** — Fixed `-N` flag (no-wait, forks to background) for proper systemd integration. Without `-N`, gpsd stays in foreground and systemd considers it "exited".
- **gpsd shared memory conflicts** — Documented SHM cleanup procedure for when stale shared memory segments prevent gpsd from starting.
- **SKILL.md duplicates** — Removed duplicate "Advanced Features" section and fixed missing file reference.

### Added
- **Reverse-geocoding cache** — SQLite cache (`~/.hermes/geocode-cache.db`) stores Nominatim results. If user moves less than 50m, cached address is reused, preventing OSM rate limits.
- **Weather/AQI enrichment** — Location-updater fetches current weather from Open-Meteo (free, no API key) every 10 minutes and appends to `location.json`.
- **GPX/KML export** — `location-query --export gpx|kml` exports location history as standard GPX 1.1 or KML 2.2 files for use in Google Earth, mapping tools, and fitness apps.
- **macOS compatibility** — Install script detects macOS and skips systemd setup. Users start gpsd manually or via `brew services`.
- **Geofenced actions** — Documented as an advanced use case for location-triggered home automation (user-configured).
- **Troubleshooting entries** — Added SHM error fix, gpsd exit fix, and places command fix to SKILL.md and AgentInstructions.md.

## [1.0.0] - 2026-06-22

### Initial Release
- GPS forwarding from smartphone to desktop via gpsd (Android + iOS)
- Location-aware search (restaurants, bookstores, etc.) via Google Maps scraping
- Place memory with auto-tagging and natural language retrieval
- Location history with tiered retention (SQLite)
- Google Maps integration with pin and directions links
- Agent-guided setup walkthrough (AgentInstructions.md)
- Automated install script with OS detection
- Support for Linux (Ubuntu, Debian, Mint, Arch, Fedora) and macOS
- Support for Android (gpsdRelay) and iOS (NMEA Send Location, GPS2IP)
