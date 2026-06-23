# gps-agent-bridge

**Give your AI agent eyes on the world.**

gps-agent-bridge turns your smartphone into a remote GPS receiver for your Linux desktop. Your phone's live GPS location gets streamed to your desktop over your local network, so your AI agent always knows where you are — and can act on it.

## What It Enables

Once set up, your agent can answer questions that depend on your real-time location:

- **"What restaurants near me have good ratings?"** — Search with your exact coordinates
- **"Flights from my location to Chicago next weekend"** — Use your nearest airport automatically
- **"How far is [place] from here?"** — Calculate precise distances from your current position
- **"What's the weather like right now?"** — Get weather for your actual location
- **"Directions to [address]"** — Generate turn-by-turn from where you are
- **"Find a coffee shop within walking distance"** — Search radius centered on you
- **"Where was I last Tuesday?"** — Query your location history
- **"What's the best route to avoid traffic right now?"** — Real-time routing from your position
- **"Remember this spot, I like the food here"** — Save a place with notes and tags
- **"What was that restaurant I liked in Milwaukee?"** — Search your remembered places
- **"Show me all the places I've saved"** — List your curated place collection
- **"Places to avoid near me"** — Filter remembered places by "avoid" tag
- **"Export my location history as GPX for yesterday"** — Export travel history for mapping tools
- **"How's the weather outside right now?"** — Instant weather from cached location data
- **"Set up a geofence so my lights turn on when I get home"** — Use location triggers for home automation

Instead of asking "Where are you?" or guessing based on old context, your agent reads your live GPS position and responds with accurate, location-aware answers. You can also build a personal collection of remembered places — restaurants you liked, spots to avoid, places you want to return to — all searchable by name, location, tags, or time. Export your travel history as GPX/KML to visualize your routes in Google Earth or mapping tools. The system also caches local weather and air quality data so your agent can answer "how's the weather?" instantly without external API calls. For advanced users, the location daemon can trigger geofenced actions — execute scripts when arriving at or leaving defined zones (home, work, etc.) for home automation integrations.

## How It Works

```
┌─────────────────┐     UDP NMEA     ┌─────────────────┐     JSON      ┌──────────┐
│  Smartphone      │ ──────────────► │  Linux Desktop   │ ──────────► │  Agent    │
│  (GPS relay app) │   port 2948     │  (gpsd daemon)   │   port 2947  │          │
└─────────────────┘                  └─────────────────┘              └──────────┘
```

1. **Phone app** reads GPS and streams NMEA sentences via UDP to your desktop on port 2948
2. **gpsd** receives the NMEA data, parses it, and serves it as JSON on port 2947
3. **Your agent** reads the live position from `~/.hermes/location.json` and uses it to answer questions

The entire pipeline runs in the background. Once set up, your agent always knows where you are — no asking, no guessing.

## Supported Platforms

| Platform | App | Protocol | Cost |
|----------|-----|----------|------|
| **Android** | [gpsdRelay](https://f-droid.org/packages/io.github.project_kaat.gpsdrelay/) | UDP | Free |
| **iOS (free)** | [NMEA Send Location](https://apps.apple.com/us/app/nmea-send-location/id6749798097) | UDP | Free |
| **iOS (alt)** | [GPS2IP](https://apps.apple.com/us/app/gps-2-ip/id408625926) | TCP/UDP push | ~$5 |

Both apps push standard NMEA 0183 sentences to your desktop — the setup is identical regardless of phone OS.

## Prerequisites

- **Desktop:** Linux (Ubuntu, Debian, Mint, Arch, Fedora, etc.) or macOS (partial support, untested)
- **Phone:** Android or iOS
- **Network:** Both devices on the same network (Tailscale, Wireguard, or similar recommended)
- **Python:** 3.10+ (stdlib only — no pip packages required for core functionality)
- **Optional:** `invisible_playwright` for Google Maps scraping (requires separate install + Firefox fetch)

## Quick Start

### For AI Agents (Preferred)

**If you're an AI agent setting this up for a user, read [AgentInstructions.md](AgentInstructions.md) for a complete guided setup walkthrough.** It covers:
- Assessing the user's phone platform and network setup
- Installing and configuring the desktop software
- Walking the user through phone app setup (Android + iOS)
- Verifying the pipeline end-to-end
- Troubleshooting common issues

The goal: the user tells you "set up my phone as a GPS receiver," you read the agent instructions, and guide them through the entire process conversationally.

### For Humans (Manual Setup)

1. Clone this repo
2. Run `./install.sh` (or `./install.sh --headless` for servers)
3. Edit `config.json` to set your desktop's IP address
4. Install the phone app (Android: gpsdRelay, iOS: NMEA Send Location)
5. Configure the app with your desktop's IP and port 2948
6. Verify: `gpsloc --human`

## Tools

### gpsloc — Current location

```bash
gpsloc              # Full JSON TPV report
gpsloc --human      # Human-readable output
gpsloc --lat        # Latitude only
gpsloc --lon        # Longitude only
gpsloc --latlon     # "lat,lon" for maps URLs
```

### gpsnear — Find nearby places

```bash
gpsnear "restaurants"                    # Search near you
gpsnear "coffee shops" --min-rating 4.5  # Filter by rating
gpsnear "libraries" --radius 3000        # Custom radius (meters)
gpsnear --address "123 Main St, City"    # Geocode + distance
```

### gmaps — Google Maps scraper

```bash
gmaps "bookstores" --lat 35.97 --lon -83.92
gmaps "Italian restaurants" --lat 35.97 --lon -83.92 --min-rating 4.5
```

### location-query — Location history

```bash
location-query --now                              # Current location (live)
location-query --today                            # Where did I go today?
location-query --date 2026-01-08                   # Where was I on this date?
location-query --recent 2h                         # Last N hours
location-query --range "2026-01-01 to 2026-01-08"  # Date range
location-query --export gpx --date 2026-01-08      # Export as GPX (Google Earth, etc.)
location-query --export kml --date 2026-01-08      # Export as KML
location-query --export gpx --today                # Export today's track
```

### places — Remembered places

```bash
places add --name "Restaurant Name" --lat 35.97 --lon -83.92 --notes "Great pizza"
places search --query "restaurant milwaukee"       # Search by name/location
places search --tags liked                         # All liked places
places search --tags avoid --near-lat 35.97 --near-lon -83.92 --radius 50000
places list                                        # All remembered places
places update --id 1 --notes "Updated notes"
places delete --id 1
```

## Location History

Location data is stored in a tiered retention system:

| Tier | Age | Granularity | Storage |
|------|-----|-------------|---------|
| Hot cache | Real-time | Latest ping | `~/.hermes/location.json` (30s refresh) |
| Raw | 48 hours | Every 30s | `~/.hermes/location-history.jsonl` |
| Tier 1 | 0–24h | 5-min averages | SQLite |
| Tier 2 | 1–30 days | Hourly centroids | SQLite |
| Tier 3 | 31d–1yr | 4-hour blocks | SQLite |
| Tier 4 | 1yr+ | Daily summary | SQLite |

Total storage: ~2-3MB per year.

## Network Configuration

### Tailscale (Recommended)

Both devices on the same Tailscale network. Find your desktop's IP:

```bash
tailscale ip -4
```

Use this IP in your phone app. No firewall changes needed — Tailscale handles routing.

### Local Network

Ensure port 2948/UDP is open on the desktop's firewall:

```bash
sudo ufw allow 2948/udp
```

## Architecture Notes

- **gpsd** runs as a systemd service with `udp://*:2948` as the GPS data source
- **Port 2948/UDP** receives NMEA sentences from the phone
- **Port 2947/TCP** serves JSON GPS data to local clients
- No local GPS device needed — the phone is the GPS source
- The `-F /run/gpsd.sock` flag provides a control socket so gpsd can start without a physical device
- The `-G` flag allows gpsd to listen on all interfaces
- **Reverse geocoding** uses OpenStreetMap Nominatim with a local SQLite cache to avoid rate limits (50m radius cache hit)
- **Weather/AQI** data is fetched from Open-Meteo (free, no API key) and cached in `location.json` — refreshed every 10 minutes
- **Geocoding cache** stores Nominatim results in `~/.hermes/geocode-cache.db` — if the user moves less than 50m, the cached address is reused instead of calling Nominatim again
- **Place memory** is stored in `~/.hermes/places.json` — a user-curated collection of notable locations with auto-extracted tags (liked, avoid, restaurant, bar, etc.)
- **GPX/KML export** converts location history tracks for use in Google Earth, mapping tools, and fitness apps
- **macOS support**: The install script detects macOS and skips systemd setup. Users start gpsd manually or via `brew services`.

## Google Maps Integration

All location results can include Google Maps links for one-tap navigation (no API key needed):

```
Pin:        https://www.google.com/maps/search/?api=1&query=LAT,LON
Directions: https://www.google.com/maps/dir/?api=1&origin=LAT,LON&destination=LAT,LON
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `gpsloc` times out | gpsd isn't running: `systemctl status gpsd` |
| gpsd won't start | Check journal: `journalctl -u gpsd` |
| No GPS fix | Go outside or near a window; cold start takes ~30s |
| Connection refused | Check firewall; verify network connectivity |
| Phone can't connect | Verify the desktop's IP and that gpsd is listening: `ss -ulnp \| grep 2948` |
| OSM rate limit | Normal during heavy use; results still work from other sources |

## License

MIT
