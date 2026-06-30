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

This gives you: `lat`, `lon`, `address`, `timestamp`, `status`, `speed` (m/s), `track` (heading°), `alt` (meters), `eph` (accuracy meters). If `status` is `"active"`, the location is fresh (≤30s old). If `"unavailable"`, ask the user for their location.

### What "location-dependent" means

Any question that depends on the user's current position:
- "What's near me?" / "Find X nearby"
- "How far is X from me?"
- "Flights from my location to X"
- "Directions to X"
- "What's the weather here?"
- "Restaurants near me"
- "Live music near me" / "What's happening near me tonight?"
- "Events near me" / "What's going on around here?"
- Anything involving "here", "near me", "from my location", "close by", "around here", "tonight near me"

**For all of these: read `~/.hermes/location.json` FIRST — before any other tool call.** Don't rely on memory, don't ask the user, don't guess. Don't use `mcp_dashboard_find_service` or Mnemosyne/memory lookups as a substitute for reading the live GPS cache. The file `~/.hermes/location.json` is the single source of truth for the user's current position.

## Architecture

```
Phone (GPS AgentBridge) ──UDP:2948──► Desktop (gpsd) ──TCP:2947──► Clients
                                                              │
                                                     ┌────────┴────────┐
                                                     │  location.json   │  hot cache (30s)
                                                     │  location.db     │  tiered history
                                                     └─────────────────┘
```

## Phone Setup

| Platform | App | Protocol | Cost | Setup |
|----------|-----|----------|------|-------|
| **Android (recommended)** | [GPS AgentBridge](https://github.com/Madvulcan/GPS-AgentBridge-Android) | UDP | Free | Install APK, complete onboarding, add desktop IP:2948 as target |
| **Android (alt)** | [gpsdRelay](https://f-droid.org/packages/io.github.project_kaat.gpsdrelay/) | UDP | Free | Set Host IP, Port 2948, Protocol UDP |
| **iOS (free)** | [NMEA Send Location](https://apps.apple.com/us/app/nmea-send-location/id6749798097) | UDP | Free | Set Host IP, Port 2948, enable streaming |
| **iOS (alt)** | [GPS2IP](https://apps.apple.com/us/app/gps-2-ip/id408625926) | TCP/UDP push | ~$5 | Settings → UDP Push → set IP and Port 2948 |

**GPS AgentBridge** is the companion app built specifically for this project. It uses distance-based transmission (only sends when you move >X meters) instead of fixed-interval polling, dramatically reducing battery drain. As of v1.3.0, it features **deep sleep mode** with significant motion sensor wake-up — GPS polling follows four states: ACTIVE (30s) → SETTLING (2min) → IDLE (5min) → SLEEP (GPS off, hardware motion sensor armed at <0.01%/hr). When stationary + screen off >5min, GPS turns completely off. The significant motion sensor fires when the phone is physically moved, snapping back to active polling instantly. As of v1.3.1, the onboarding also requests the `POST_NOTIFICATIONS` permission (required on Android 13+ for the foreground service notification to appear). Download the APK from the [releases page](https://github.com/Madvulcan/GPS-AgentBridge-Android/releases).

Two builds are available:
- **Standard** (~2 MB) — uses Google Play Services for sensor fusion (better battery, faster indoor fixes). For most phones.
- **F-Droid** (~1.5 MB) — uses raw LocationManager, no Google dependencies. For de-Googled devices (LineageOS, GrapheneOS).

All apps push standard NMEA 0183 sentences. The desktop setup is identical regardless of phone OS.

### ⚠️ Transmission Interval / Battery Life

**For GPS AgentBridge users:** The app handles this automatically with distance-based triggers + deep sleep. Default settings (500m threshold, 10-min max interval, 20m accuracy gate) provide excellent battery life. As of v1.3.0, adaptive GPS polling + significant motion sensor further reduce battery drain. When stationary + screen off >5min, GPS turns **completely off** and the hardware motion sensor is armed (<0.01%/hr). No manual interval configuration needed. Note: in sleep mode, the first fix after waking may take ~30s.

**For gpsdRelay / other fixed-interval apps:** The default transmission interval is very frequent (~1 second), which drains battery in ~2 hours. Advise the user to increase it:

- **60 seconds (60000ms):** Good balance of accuracy and battery life (~10+ hours)
- **5-10 minutes (300000-600000ms):** Excellent battery life, sufficient for most "where am I?" use cases

## Key Commands

### Current location (ALWAYS FIRST)
```bash
cat ~/.hermes/location.json
```

### Full GPS data (for scripts)
```bash
gpsloc --tpv          # Raw TPV JSON (single line, for piping)
gpsloc                # Pretty-printed TPV JSON
gpsloc --human        # Human-readable: lat/lon/alt/speed/heading/accuracy/fix
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

The hot cache at `~/.hermes/location.json` is updated every 30 seconds. Check `status` field — if `"unavailable"`, the GPS stream is down. The cache also includes `speed` (m/s), `track` (heading in degrees), `alt` (altitude in meters), and `eph` (horizontal accuracy in meters) — useful for distinguishing driving from walking, detecting brief stops vs. true destinations. See "Interpreting Speed/Track Data" in Advanced Features for guidance on speed ranges and caveats.

## Location History (Tiered)

Stored in `~/.hermes/location-history.db` (SQLite). Raw pings in `~/.hermes/location-history.jsonl` are pruned to 48h rolling window. Total storage: ~3-3.5MB/year. History entries include `speed`, `track`, `alt`, and `eph` alongside coordinates and address.

**Deduplication note:** The JSONL may contain duplicate entries (same coordinates, sub-second apart) caused by service restarts. These are harmless — deduplicate when presenting to the user by matching on timestamp (to the second) + coordinates. The `location-compact` cron job handles this correctly when aggregating into tiers.

## Services & Cron Jobs

| Service/Job | Schedule | Purpose |
|-------------|----------|---------|
| `gpsd.service` | Running | Receives UDP NMEA on 2948, serves JSON on TCP 2947 |
| `gpsd-watcher.service` | Running | Persistent gpsd subscriber — caches latest TPV to `/tmp/gpsd-last-tpv.json`. **Required** for `gpsloc` to work with GPS AgentBridge's intermittent transmissions. Without it, `gpsloc` times out because gpsd only emits TPV when fresh NMEA arrives and a subscriber is active. |
| `gpsd-watcher.service` | Running | Persistent gpsd subscriber — caches latest TPV to `/tmp/gpsd-last-tpv.json`. **Required** for `gpsloc` to work with GPS AgentBridge's intermittent transmissions. Without it, `gpsloc` times out because gpsd only emits TPV when a subscriber is active and fresh NMEA arrives. Includes diagnostic logging and automatic stale-connection detection (reconnects if no valid TPV for >11 min). Restarted daily at 4 AM via `gpsd-watcher-restart.timer` to prevent long-running connections from going silent. See `references/gpsd-watcher-service.md` |
| `location-updater.service` | Running | Reads gpsd every 30s, writes cache + history (includes speed/track/alt/eph) |
| `location-landmark` | Every 5 min | Detect places user stays >5 min |
| `location-compact` | Daily 3:15 AM | Compact raw history into tiers |
| `location-prune` | Every 2 hours | Prune raw JSONL to 48h |
| `gpsd-watcher-restart.timer` | Daily 4:00 AM | Restart gpsd-watcher to prevent stale TCP connections |

## Important Rules

0. **Operational rules go in this skill, NOT in memory.** When the user corrects your workflow, format, or approach, update this skill immediately. Memory is for environment facts and user preferences. Skills capture "how to do this class of task." If you find yourself writing a lesson to memory that's about *how to do something*, it belongs here instead.

1. **ALWAYS read `~/.hermes/location.json` first** for any location-dependent question.
   - If `status` is `"active"`, use the coordinates and address as normal.
   - If `status` is `"unavailable"`, the phone's GPS stream is down (phone off, out of network, app killed, transmission interval too long, etc.). Handle gracefully:
     - Check if `DEFAULT_CITY` is set in `~/.hermes/config.json`. If so, say: "I can't see your live GPS right now. Are you still in [DEFAULT_CITY]?"
     - If no `DEFAULT_CITY`, ask: "I've lost connection to your phone's GPS. Where are you right now?"
     - Once the user confirms their location, you can still search for places near them using the city name, but note that distances/accuracy may be approximate.
     - If the `weather` key exists in location.json, you can still report cached weather data but note it may be stale.
   - If the file doesn't exist at all, the system isn't set up yet. Ask the user to run the install script.
2. **Always geocode via Nominatim** — never estimate coordinates. Use `gpsnear --address "..."` for precise haversine distance.
3. **OSM/Nominatim has two different uses — don't confuse them:**
   - **Reverse geocode** (coords → address): `https://nominatim.openstreetmap.org/reverse?lat=LAT&lon=LON` — This is how you turn coordinates into a human-readable address (e.g., "Deery Street, Knoxville"). This is reliable and should always be used when you need an address from coordinates.
   - **Category search** (find nearby X): `https://nominatim.openstreetmap.org/search?q=restaurants` — This is unreliable and often returns 0 results. Use the browser tool (Google Maps) instead for finding nearby businesses.
   - If Nominatim returns 429 (rate limit), skip category search but **still use reverse geocoding** — it's a different endpoint and usually still works.
4. **Check for closed businesses** — read snippets for "Permanently closed" markers.
5. **Zip-code bias** — businesses in adjacent zips can be closer than same-zip results.
6. **Always provide Google Maps links** — render as actual Markdown `[📍](url)` / `[🧭](url)`, NEVER in code blocks.
7. **Response time target**: under 2 minutes. If longer, simplify — use browser tool directly.

8. **NEVER use `mcp_dashboard_find_service` or memory/Mnemosyne lookups as a substitute for reading `~/.hermes/location.json`.** The dashboard tool searches for web services — it has nothing to do with GPS. Memory is stale; `location.json` is live. For any location-dependent question, `cat ~/.hermes/location.json` is always the first command.

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
3. **Save immediately** — don't wait for more info. Use the `places` CLI:
   ```bash
   places add --name "Place Name" --lat LAT --lon LON --address "Full Address" --notes "User's reason for saving" --tags tag1 tag2
   ```
   Note: the command is `places` (installed at `/usr/local/bin/places`), NOT `places.py`.
4. **Confirm to the user** — "✅ I've saved this location: [name/address]"
5. **Ask a polite follow-up** — "Do you want to add any notes or thoughts about this place?"
6. **If they provide notes**, update the entry:
   ```bash
   places update --id ID --notes "Additional notes"
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
   places search --query "restaurant milwaukee"
   places search --tags liked --near-lat LAT --near-lon LON --radius 50000
   places list
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

- **Timezone: Always report timestamps in the local timezone of where the user was at the time.** Convert each location history entry to its own local TZ (e.g. Knoxville → America/New_York/EST/EDT, Texas → America/Chicago/CST/CDT). If a single report spans multiple timezones, convert each entry individually. Never present UTC timestamps in user-facing location history — always convert first.
- **Speed data: when available, use it to add context.** Speed >2 m/s suggests driving; 0.8–2 m/s suggests walking; 0 m/s with no recent movement means stopped/parked. Mention this in natural language ("you were driving" / "you walked to") rather than raw numbers, unless the user asks for specifics. A brief stop at a business while driving (e.g., waiting to turn) should not be reported as "visited" — use speed + dwell time to distinguish stops from pauses.
- **List format** with explicit 📍 and 🧭 links — never tables or code blocks
- **Sort by distance** from user's current location
- **Group by distance tier** (walkable / short drive / further out)
- **Include rating** when available
- **Keep concise** — don't list every result if there are many
- **Trip interpretation** — The phone app uses a 500m distance threshold before sending the first movement ping. This means every trip has a "blind spot" between departure and the first recorded position. When presenting trip timelines, infer trip start as a window ("departed between X and Y") rather than a point ("departed at Y"), where X is the last stationary ping and Y is the first movement ping. Never state the first movement ping as the departure time — the user had already been traveling for some distance by then.

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
- **GPS status "unavailable" — diagnostic decision tree:**
  1. Check `cat /tmp/gpsd-last-tpv.json` — if it shows `lat: 0.0, lon: 0.0` and the cache is being updated recently, **the gpsd-watcher connection is stale**. Restart it: `sudo systemctl restart gpsd-watcher.service`. Then also restart location-updater: `sudo systemctl restart location-updater.service`.
  2. If the TPV cache is stale (not updating at all), check `sudo tcpdump -i any udp port 2948 -c 1` with a 20s timeout. If no packets arrive, the phone isn't sending — ask user to verify the app destination server config.
  3. If packets arrive but coords are 0,0, the phone's GPS hasn't acquired a satellite fix yet — normal after deep sleep or coming indoors.
  4. **Don't blame the phone first.** The most common cause of "unavailable" in practice is the watcher going stale, not the phone stopping.
- **Transmission interval**: For GPS AgentBridge users, this is handled automatically (distance-based + adaptive polling). For gpsdRelay / other fixed-interval apps, default ~1s drains battery in ~2h. Recommend 60s (good balance) or 5-10 min (maximum battery).

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

### Interpreting Speed/Track Data
The `speed` and `track` fields in `location.json` and history entries enable richer location reports:
- **speed ≈ 0 m/s + stationary**: User is at a destination (home, store, restaurant)
- **speed 0.5–2 m/s**: Walking pace (1–4.5 mph) — user is on foot
- **speed 3–15 m/s**: Driving (7–34 mph) — likely on city streets
- **speed 15–30+ m/s**: Highway driving
- **Brief stop with speed=0 between moving segments**: Traffic light, left turn, not a destination. Cross-reference with duration — if speed=0 for <2 minutes between movement, it's a pause, not a stop.
- **track field**: Heading in degrees (0=N, 90=E, 180=S, 270=W). Useful for direction of travel.

**Caveat**: Speed data is only as reliable as the GPS fix. `eph` (accuracy) >50m often means the speed reading is noisy. Take speed values with a grain of salt when accuracy is poor.

## Optimization Notes

**Timing benchmarks:**
- Browser tool (Google Maps): ~15s per query
- gmaps script: ~30s per query
- gpsnear-parallel: ~43s single query, ~68s for 3 queries

**Data quirks when reading historical JSONL:**
- **Pre-v1.0.5 entries are duplicated** — The old location-updater wrote each entry twice per cycle (cache write + history write). When reading old JSONL, deduplicate by timestamp before presenting to the user.
- **Pre-v1.0.5 entries lack speed/track/alt/eph** — These fields were added in v1.0.5. Older entries only have timestamp/lat/lon/address. Code that reads JSONL should handle both shapes.
- **Pre-v1.0.5 entries may contain 0,0 coordinates** — Null-island pings (phone GPS without satellite fix) were recorded as valid entries before v1.0.5 added filtering. Skip any entries with lat=0.0 and lon=0.0 when presenting history.

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
| GPS status "unavailable" | **First determine if this is normal deep sleep or a real problem.** If phone is stationary + screen off >5min, deep sleep is expected — `unavailable` is normal. If user is actively using phone, the streaming service may be killed (check: open app → tap START). Use `tcpdump udp port 2948` to verify if packets arrive. If phone says "sent" but no packets arrive, the destination server list may be empty (cleared by uninstall+reinstall). For gpsdRelay: increase transmission interval. See references/android-companion-app.md "Deep Sleep Diagnostic" for full decision tree. |
| Notification not appearing (Android 13+) | The `POST_NOTIFICATIONS` runtime permission must be granted. Without it, the foreground service notification is silently blocked. The v1.3.1+ onboarding requests this permission. On older versions: go to Android Settings → Apps → GPS AgentBridge → Notifications → enable. |
| location-updater writing to /root/ | Service missing `Environment=HOME=` — run `./install.sh` to re-template the service files, or check that `/usr/lib/systemd/system/location-updater.service` has `Environment=HOME=/home/USER` |
| gpsd-watcher writing to /root/ | Same fix as location-updater — `Environment=HOME=` in the service file |
| gpsd-watcher stale connection | If the watcher has been running for days, its TCP connection to gpsd may silently stop receiving fresh TPV data (no new writes to cache, cache goes stale). **Fix:** `systemctl restart gpsd-watcher`. Prevented by daily restart timer (`gpsd-watcher-restart.timer` at 4 AM) and auto-reconnect when no valid TPV for >11 min. Check logs: `journalctl -u gpsd-watcher --since "1h ago"` |
| gpsloc shows 0,0 but phone has a fix | The watcher may have written a null-island (0,0) TPV to `/tmp/gpsd-last-tpv.json`, overwriting the last valid position. As of v1.0.6 the watcher skips 0,0 writes, but older versions or stale cache files may still have this. **Fix:** (1) Update gpsd-watcher to v1.0.6+, (2) Seed the cache: read the last valid entry from `location-history.jsonl` and write it to `/tmp/gpsd-last-tpv.json` as a TPV-shaped JSON object. The cache will then hold until the next valid transmission. |
| gpsd-watcher feeds stale 0,0 data | The watcher keeps a single persistent TCP connection to gpsd. After running for days, that connection can go stale — the watcher still writes to the TPV cache, but with old or null-island (0,0) coordinates instead of real ones. `location-updater` then correctly filters these out (v1.0.5+), but `location.json` shows `status: unavailable`. **Fix: restart gpsd-watcher** (`sudo systemctl restart gpsd-watcher.service`). **Diagnostic:** if the phone app says it has a fix and is streaming, but `tcpdump udp port 2948` shows no packets arriving, first check the TPV cache age and coordinates (`cat /tmp/gpsd-last-tpv.json`). If the cache is being updated with 0,0 data, the watcher connection is stale — restarting it is the fix. Don't waste time troubleshooting the phone if the watcher is the problem. |
| Duplicate entries in JSONL | When location-updater restarts, `last_lat`/`last_lon` reset to None, so the first cycle always writes an entry — even at the same position as the last entry before restart. This produces near-duplicate entries (sub-second apart, same coords). Not a data problem — deduplicate when presenting reports. A real fix would seed `last_lat`/`last_lon` from the JSONL on startup, but the duplicates are cosmetic and don't affect storage or queries. |
| GPS streaming dies overnight (10+ hour gap) | **Two-layer fix required:** (1) systemd `User=` or `Environment=HOME=` (see Pitfalls), AND (2) Android OEM battery setting — go to Settings → Apps → GPS AgentBridge → Battery → select **"Unrestricted"** (not "Smart Mode"). The system-level `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is NOT sufficient on its own — OEM-specific "Smart Mode" throttles background activity independently. |
| places command not found | Run `places list` instead of `places.py list` — the .py extension is stripped on install |
| gpsd won't start (SHM error) | Shared memory conflict. Run: `sudo bash -c 'killall -9 gpsd; rm -f /run/gpsd.sock; for key in $(ipcs -m | grep root | awk "{print \$2}"); do ipcrm -m \$key 2>/dev/null; done; systemctl start gpsd.service'` |
| gpsd starts then exits | Ensure `-N` flag is present in systemd service (gpsd forks to background). Without `-N`, gpsd stays in foreground and systemd considers it "exited". |
| gpsd-watcher stale connection (full diagnostic) | See `references/gpsd-watcher-stale-connection.md` for symptoms, diagnostic procedure, manual recovery, and the location-updater user-path pitfall |

## Pitfalls

- **The `places` CLI is installed at `/usr/local/bin/places`**, not `~/.hermes/scripts/places.py`. Always use `places` directly.
- **`location-updater.service` must include `User=<username>`** (or `Environment=HOME=/home/<user>`). Without it, the service runs as root and `~/.hermes/` resolves to `/root/.hermes/` — data gets written but the agent reads from the wrong path and always sees `status: unavailable`. The `gpsd-watcher.service` is immune because it writes to `/tmp/`, not `~/.hermes/`.
- **Android OEM battery optimization kills GPS streaming** — Even with `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` granted, the per-app OEM "Smart Mode" setting (Settings → Apps → GPS AgentBridge → Battery) can throttle the streaming service. If GPS data shows large overnight gaps (10+ hours) despite correct systemd config, check this setting and switch to "Unrestricted."
- **GPS AgentBridge's distance-based transmission means long quiet periods** when stationary. If the user says "check again" or "I just sent a test", don't assume the data is missing — the TPV cache at `/tmp/gpsd-last-tpv.json` may have updated but `location.json` won't refresh until the next 30s updater cycle. Wait a few seconds and re-read.
