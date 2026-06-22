---
name: gps-agent-bridge
description: Location awareness system via GPS. Always know where the user is, then answer location-dependent questions including finding nearby places, calculating distances, providing directions, and searching with origin/destination. Phone streams NMEA over UDP to gpsd; location is cached at ~/.hermes/location.json.
---

# gps-agent-bridge

## Core Principle: Always Know Where the User Is

**Before answering ANY location-dependent question, read `~/.hermes/location.json`.** This is the single most important rule in this skill.

The user's phone streams GPS NMEA data over UDP to **gpsd** on the desktop. A background updater caches the location every 30 seconds.

```bash
# ALWAYS do this first for any location-dependent question:
cat ~/.hermes/location.json
```

This gives you: `lat`, `lon`, `address`, `timestamp`, `status`. If `status` is `"active"`, the location is fresh (≤30s old). If `"unavailable"`, ask the user for their location.

### What "location-dependent" means

Any question that depends on the user's current position:
- "What's near me?" / "Find X nearby"
- "How far is X from me?"
- "Flights from my location to X"
- "Directions to X"
- "What's the weather here?"
- "Restaurants near me"
- Anything involving "here", "near me", "from my location", "close by"

**For all of these: read `~/.hermes/location.json` first.** Don't rely on memory, don't ask the user, don't guess.

## Architecture

```
Phone (GPS relay app) ──UDP:2948──► Desktop (gpsd) ──TCP:2947──► Clients
                                                          │
                                                 ┌────────┴────────┐
                                                 │  location.json   │  hot cache (30s)
                                                 │  location.db     │  tiered history
                                                 └─────────────────┘
```

## Phone Setup

| Platform | App | Protocol | Cost | Setup |
|----------|-----|----------|------|-------|
| **Android** | [gpsdRelay](https://f-droid.org/packages/io.github.project_kaat.gpsdrelay/) | UDP | Free | Set Host IP, Port 2948, Protocol UDP |
| **iOS** | [GPS2IP](https://apps.apple.com/us/app/gps-2-ip/id408625926) | TCP/UDP push | ~$5 | Settings → UDP Push → set IP and Port 2948 |

Both apps push standard NMEA 0183 sentences. The desktop setup is identical regardless of phone OS.

## Key Commands

### Current location (ALWAYS FIRST)
```bash
cat ~/.hermes/location.json
```

### Find nearby places
```bash
# Preferred: browser tool for Google Maps (see Search Strategy below)
gpsnear --address "FULL ADDRESS"          # Geocode + distance

# Scripted searches:
gpsnear-parallel "QUERY" --lat LAT --lon LON [--min-rating N] [--queries "q1,q2,q3"]
gpsnear "QUERY" --source gmaps --radius 3000
```

### Location history
```bash
location-query --now
location-query --date YYYY-MM-DD
location-query --recent 2h
```

## Location Cache

The hot cache at `~/.hermes/location.json` is updated every 30 seconds. Check `status` field — if `"unavailable"`, the GPS stream is down.

## Location History (Tiered)

Stored in `~/.hermes/location-history.db` (SQLite). Raw pings in `~/.hermes/location-history.jsonl` are pruned to 48h rolling window. Total storage: ~2-3MB/year.

## Services & Cron Jobs

| Service/Job | Schedule | Purpose |
|-------------|----------|---------|
| `gpsd.service` | Running | Receives UDP NMEA on 2948, serves JSON on TCP 2947 |
| `location-updater.service` | Running | Reads gpsd every 30s, writes cache + history |
| `location-landmark` | Every 5 min | Detect places user stays >5 min |
| `location-compact` | Daily 3:15 AM | Compact raw history into tiers |
| `location-prune` | Every 2 hours | Prune raw JSONL to 48h |

## Important Rules

0. **Operational rules go in this skill, NOT in memory.** When the user corrects your workflow, format, or approach, update this skill immediately. Memory is for environment facts and user preferences. Skills capture "how to do this class of task." If you find yourself writing a lesson to memory that's about *how to do something*, it belongs here instead.

1. **ALWAYS read `~/.hermes/location.json` first** for any location-dependent question.
   - If `status` is `"active"`, use the coordinates and address as normal.
   - If `status` is `"unavailable"`, the phone's GPS stream is down (phone off, out of network, app killed, etc.). Handle gracefully:
     - If the `DEFAULT_CITY` config value is set, say something like: "I can't see your live GPS right now, but based on your last known location, you're in [last known address]. Are you still in [DEFAULT_CITY]?"
     - If no `DEFAULT_CITY` is set, ask: "I've lost connection to your phone's GPS. Where are you right now?"
     - Once the user confirms their location, you can still search for places near them using the city name, but note that distances/accuracy may be approximate.
   - If the file doesn't exist at all, the system isn't set up yet. Ask the user to run the install script.
2. **Always geocode via Nominatim** — never estimate coordinates. Use `gpsnear --address "..."` for precise haversine distance.
3. **OSM/Nominatim has two different uses — don't confuse them:**
   - **Reverse geocode** (coords → address): `https://nominatim.openstreetmap.org/reverse?lat=LAT&lon=LON` — This is how you turn coordinates into a human-readable address (e.g., "123 Main St, Springfield, IL"). This is reliable and should always be used when you need an address from coordinates.
   - **Category search** (find nearby X): `https://nominatim.openstreetmap.org/search?q=restaurants` — This is unreliable and often returns 0 results. Use the browser tool (Google Maps) instead for finding nearby businesses.
   - If Nominatim returns 429 (rate limit), skip category search but **still use reverse geocoding** — it's a different endpoint and usually still works.
4. **Check for closed businesses** — read snippets for "Permanently closed" markers.
5. **Zip-code bias** — businesses in adjacent zips can be closer than same-zip results.
6. **Always provide Google Maps links** — render as actual Markdown `[📍](url)` / `[🧭](url)`, NEVER in code blocks.
7. **Response time target**: under 2 minutes. If longer, simplify — use browser tool directly.

## Search Strategy

**Step 1: Read current location from `~/.hermes/location.json`**

**Step 2: Use the browser tool for Google Maps (preferred):**
1. `browser_navigate` to `https://www.google.com/maps/search/QUERY/@LAT,LON,14z`
2. `browser_snapshot full=true` — extracts all results with ratings, addresses, hours in one shot
3. Present results with 📍 pin and 🧭 directions links

**Why browser tool over scripts:** The `gmaps` invisible_playwright scraper is unreliable (often returns 0 results due to bot detection). The built-in browser tool is more reliable and faster (~15s vs ~30s).

**For scripted/automated searches** (when browser tool unavailable):
```bash
~/.hermes/scripts/gmaps "QUERY" --lat LAT --lon LON
```

**Do NOT cascade through multiple fallback layers.** Pick one tool and use it.

## Place Memory — Remembering Locations

Users can ask you to remember places they like, want to avoid, or want to note for any reason. Store these in `~/.hermes/places.json`.

### When the user asks to remember a place

**Trigger phrases:**
- "Remember this spot"
- "Save this location"
- "I like this place"
- "Remember this for me"
- "Don't forget about this"
- "I want to come back here"
- "Avoid this place"
- "This was terrible, remember it"

**Flow:**
1. **Read current location** from `~/.hermes/location.json`
2. **Reverse geocode** to get the address (via Nominatim)
3. **Save immediately** — don't wait for more info. Use the `places.py` script:
   ```bash
   python3 ~/.hermes/scripts/places.py add \
     --name "Place Name" --lat LAT --lon LON \
     --address "Full Address" \
     --notes "User's reason for saving"
   ```
4. **Confirm to the user** — "✅ I've saved this location: [name/address]"
5. **Ask a polite follow-up** — "Do you want to add any notes or thoughts about this place?"
6. **If they provide notes**, update the entry:
   ```bash
   python3 ~/.hermes/scripts/places.py update --id ID --notes "Additional notes"
   ```

**Auto-extract tags** from the user's description:
- Positive sentiment → tag `liked`
- Negative sentiment → tag `avoid`
- Business type → tag `restaurant`, `bar`, `coffee`, `grocery`, `park`, `shop`, `hotel`, `service`
- Location cues → tag city/region names

### When the user asks about remembered places

**Trigger phrases:**
- "What was that restaurant I liked in [city]?"
- "Show me places I've saved"
- "Where did I say I wanted to go back to?"
- "List my remembered places"
- "Places I liked in [location]"
- "Places to avoid"

**Flow:**
1. **Try structured search first:**
   ```bash
   python3 ~/.hermes/scripts/places.py search --query "restaurant milwaukee"
   python3 ~/.hermes/scripts/places.py search --tags liked --near-lat LAT --near-lon LON --radius 50000
   python3 ~/.hermes/scripts/places.py list
   ```
2. **If structured search returns results**, present them.
3. **If structured search returns nothing**, load the entire `places.json` file into your context and do a manual search:
   ```bash
   cat ~/.hermes/places.json
   ```
   Then reason across all the data — names, addresses, notes, tags, timestamps — to find matches. The script's fallback search handles basic keyword matching, but you can do better: understand intent, match partial names, connect related concepts, filter by time ("earlier this year"), etc.
4. **Present results** with name, address, notes, tags, when saved, and 📍 Google Maps link
5. **If no results after both searches**, say so honestly — "I don't have any saved places matching that."

### Place data structure

Each saved place has:
- `id`: Sequential ID
- `name`: Place name (from geocode or user)
- `lat`, `lon`: Coordinates
- `address`: Human-readable address
- `timestamp`: When saved
- `notes`: Why the user saved it
- `tags`: Auto-extracted keywords (liked, avoid, restaurant, bar, city name, etc.)

### Storage

Places are stored in `~/.hermes/places.json` — a simple JSON file. This is separate from the location history database (which tracks where the user has been). Places are intentionally curated by the user.

## Presentation Format

- **List format** with explicit 📍 and 🧭 links — never tables or code blocks
- **Sort by distance** from user's current location
- **Group by distance tier** (walkable / short drive / further out)
- **Include rating** when available
- **Keep concise** — don't list every result if there are many

## Google Maps Link Formats

```
Pin:        https://www.google.com/maps/search/?api=1&query=LAT,LON
Directions: https://www.google.com/maps/dir/?api=1&origin=LAT,LON&destination=LAT,LON
```

No API key needed. Works on mobile (opens Maps app) and desktop. **Never wrap in code blocks.**

## ⚠️ Quality & Limitations

- **SEO noise**: Standard chains appear in specialized searches. Post-filter.
- **Stale listings**: Closed businesses appear. Check for "Permanently closed".
- **Coverage gaps**: Small/new businesses may not appear.
- **Response time creep**: If >2 minutes, something went wrong.
- **Nominatim rate limits**: The system uses a local SQLite geocoding cache (`~/.hermes/geocode-cache.db`) to avoid hitting OSM's rate limits. If the user moves less than 50m, the cached address is reused.
- **Weather data**: Fetched from Open-Meteo (free, no API key) every 10 minutes and cached in `location.json`. May be slightly stale.

## Advanced Features

### Weather & AQI
The location-updater periodically fetches weather data from Open-Meteo and stores it in `location.json` under the `weather` key. The agent can answer weather questions instantly without live API calls:
- "How's the weather outside right now?"
- "What's the temperature?"
- "Is it raining?"

### GPX/KML Export
Export location history for use in Google Earth, mapping tools, or fitness apps:
```bash
location-query --export gpx --date 2026-01-08      # Single day
location-query --export kml --today                 # Today's track
location-query --export gpx --range "2026-01-01 to 2026-01-08"  # Date range
```
Output files go to `~/hermes/location-export-DATE.gpx` (or `.kml`).

### Geofenced Actions (Advanced)
Users can set up location-triggered automations using the `location-landmark` tool and shell hooks. For example:
- Turn on lights when arriving home (coordinate + radius trigger)
- Start a backup daemon when leaving work
- Change audio profile based on location

This requires user configuration — the system provides the location detection; users define the actions via their agent.

### Reverse-Geocoding Cache
A local SQLite cache (`~/.hermes/geocode-cache.db`) stores Nominatim results. When the user moves less than 50m from a previously geocoded location, the cached address is reused instead of making another API call. This prevents rate limiting during frequent movement.

## Optimization Notes

**Timing benchmarks:**
- Browser tool (Google Maps): ~15s per query
- gmaps script: ~30s per query
- gpsnear-parallel: ~43s single query, ~68s for 3 queries

**Anti-patterns to avoid:**
- Cascading through multiple fallback layers
- Using code blocks for output (kills Markdown link rendering)
- Relying on memory for user location instead of reading location.json
- Running many sequential searches instead of targeted ones
- Writing operational lessons to memory instead of updating this skill

## Troubleshooting

| Problem | Check |
|---------|-------|
| No location data | `systemctl status gpsd.service` |
| Stale cache | `gpsloc --human` to test gpsd directly |
| No UDP from phone | `ss -ulnp \| grep 2948` |
| Firewall blocking | `sudo ufw status` |
| OSM category search rate limit | Use browser tool (Google Maps) for finding nearby businesses. Reverse geocoding (coords → address) uses a different endpoint and usually still works. |
| location.json address empty | Use lat/lon directly or run `gpsloc --human` |
