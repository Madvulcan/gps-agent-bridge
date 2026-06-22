# Search Pitfalls — Real Examples

## Problem: Zip code bias misses nearby businesses

**Scenario:** User asked for Italian restaurants near a specific zip code with 4.5+ ratings.

**Initial approach:** Yelp search scoped to that zip code.

**Result:** Found some restaurants but missed others in adjacent zip codes that were physically closer.

**Root cause:** Zip-scoped searches deprioritize results from adjacent zip codes, even when they're physically closer.

**Solution:**
1. Search by city/region name, not zip code
2. Use `gpsnear --address` to calculate precise haversine distance for each candidate
3. Always verify with coordinates, never trust listed zip code proximity

## Problem: Closed businesses in search results

**Scenario:** A vintage shop appeared in search results for "bookstores" but had been closed for years.

**Root cause:** Undated blog posts and stale Yelp listings.

**Solution:** Check for "Permanently closed" markers in snippets. Prefer sources with recent reviews.
