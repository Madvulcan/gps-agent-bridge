# Changelog

All notable changes to this project will be documented in this file.

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
