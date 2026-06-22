# Search Workflow: Finding Nearby Places

## Step 1: Read Current Location

**Always start by reading `~/.hermes/location.json`** to get the user's current lat/lon. Don't rely on memory or ask the user.

## Step 2: Search

**Preferred: Browser tool (Google Maps)**
1. `browser_navigate` to `https://www.google.com/maps/search/QUERY/@LAT,LON,14z`
2. `browser_snapshot full=true` — extracts all results with ratings, addresses, hours
3. Present with 📍 and 🧭 links

**Fallback: gmaps script**
```bash
~/.hermes/scripts/gmaps "QUERY" --lat LAT --lon LON
```

## Step 3: Present

- List format with 📍 pin and 🧭 directions links
- Sort by distance
- Include ratings when available
- Group by distance tier (walkable / short drive / further out)

## ⚠️ Check for Closed Businesses

Web search results can be stale. Before including a result:
1. Read the search snippet for "Permanently closed" or "Closed"
2. Check review dates — if most recent is old, the place may be closed
3. Prefer sources with recent reviews
4. When in doubt, note it

## Distance Rule

NEVER estimate distances from addresses or zip codes. Always use coordinate-based haversine calculation via `gpsnear --address`.
