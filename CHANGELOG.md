# Changelog

All notable changes to this project will be documented in this file.

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
