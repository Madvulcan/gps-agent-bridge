# Google Maps Scraping

## Overview

Google Maps can be scraped using `invisible_playwright` (stealth Firefox 150) — no API key needed. This gives the same data you'd see searching manually: names, ratings, review counts, addresses, hours.

## Tools

### gmaps (standalone scraper)
```bash
~/.hermes/scripts/gmaps "bookstores" --lat LAT --lon LON
~/.hermes/scripts/gmaps "restaurants" --lat LAT --lon LON --radius 5000 --scroll 6
```

### gpsnear --source gmaps (integrated)
```bash
gpsnear "bookstores" --source gmaps --radius 3000
```

## Performance
- Each gmaps search takes ~30s (browser startup + page load + scrolling)
- For broad queries, run 2-3 targeted searches and merge

## Google Maps Link Formats (no API key)
```
Pin:         https://www.google.com/maps/search/?api=1&query=LAT,LON
Directions:  https://www.google.com/maps/dir/?api=1&origin=LAT,LON&destination=LAT,LON
```

## OSM vs Google Maps

| | OSM | Google Maps |
|---|---|---|
| Speed | ~2s | ~30s |
| Ratings | No | Yes |
| Current listings | Sometimes stale | Real-time |
| Category search | Unreliable | Works well |

Use OSM for quick lookups and geocoding. Use Google Maps for discovery with ratings.
