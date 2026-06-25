# Changelog

All notable changes to this project will be documented in this file.

## [1.0.2] - 2026-06-25

### Fixed
- **gpsloc timeout with intermittent UDP sources** — gpsd only emits TPV when a fresh NMEA sentence arrives and a client is actively subscribed. With the phone app transmitting every ~10 min (max interval timer), `gpsloc` almost always timed out (5s). Now reads from a persistent TPV cache first, falling back to live connection only if cache is stale.
- **install.sh missed non-.py scripts** — Install script only copied `*.py` files, skipping `gpsloc`, `location-updater`, `gmaps`, `gpsnear`, etc. Now copies all scripts regardless of extension.
- **install.sh hardcoded service list** — Only deployed `gpsd.service` and `location-updater.service`. Now dynamically copies all `systemd/*.service` files.
- **NMEA lat/lon format string** — `NmeaGenerator` used `%09.4f` producing `350058.6680` instead of `3558.6680`. Fixed to `%07.4f` per NMEA 0183 spec (ddmm.mmmm not dd0mm.mmmm).
- **NMEA test checksum** — Unit test expected checksum `"47"` but actual XOR of reference body is `"67"`. Test was wrong, code was correct.
- **TransmissionEngine unmockable distance** — `distanceMeters()` used `Location.distanceBetween()` (Android API, unmockable in unit tests). Replaced with pure-Kotlin haversine formula, making the engine fully unit-testable.
- **GpsStreamingService crash** — `TransmissionEngine` was initialized at field-declaration time before Hilt had injected `UdpSender`. Moved engine creation to `onCreate()`. Fixes `lateinit property udpSender has not been initialized` crash.
- **Battery optimization onboarding broken** — Manifest was missing `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission. Without it, `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` intent silently failed on Android 6+.
- **StreamingViewModel shadow engine clobbering** — `sendTestPacket()` published the test engine's state to `StreamingStateHolder`, overwriting the service engine's live state in the UI. Removed the publish call; test send now just fires the UDP packet without clobbering UI state.
- **Icons.Filled.Send deprecation** — Replaced with `Icons.AutoMirrored.Filled.Send` for RTL layout support.

### Added
- **gpsd-watcher service** — Persistent gpsd subscriber that caches the latest TPV to `/tmp/gpsd-last-tpv.json` and updates `~/.hermes/location.json`. Keeps gpsd "warm" so `gpsloc` and `location-updater` work instantly instead of waiting for the next phone transmission.
- **GPS AgentBridge Android app** — End-to-end verified: phone (OnePlus 12) streams real GPS data via NMEA over UDP→Tailscale→desktop gpsd. App includes onboarding flow, Compose UI, Hilt DI, foreground service with wake lock, and configurable distance/interval/accuracy thresholds.

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
