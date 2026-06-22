#!/usr/bin/env python3
"""
places.py - Remembered places storage for gps-agent-bridge.

Stores notable places the user wants to remember, with metadata for retrieval:
- name, lat, lon, address
- timestamp (when saved)
- notes (why the user saved it)
- tags/keywords (auto-extracted + user-provided): "restaurant", "italian", "liked", "avoid", etc.

Storage: ~/.hermes/places.json (JSON file, human-readable)
"""

import json
import os
import sys
from datetime import datetime, timezone
from math import radians, sin, cos, sqrt, atan2

# Add scripts dir to path so we can import config
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from config import get_config

# Tag vocabulary for auto-extraction
POSITIVE_TAGS = ["liked", "love", "favorite", "great", "good", "nice", "cool", "awesome", "enjoy"]
NEGATIVE_TAGS = ["avoid", "hate", "bad", "terrible", "dislike", "skip", "don't go", "never again"]
TYPE_TAGS = {
    "restaurant": ["restaurant", "food", "eat", "dining", "lunch", "dinner", "breakfast"],
    "bar": ["bar", "pub", "drinks", "cocktail", "beer", "wine"],
    "coffee": ["coffee", "cafe", "espresso", "latte"],
    "grocery": ["grocery", "supermarket", "market", "food store"],
    "park": ["park", "trail", "hike", "outdoor"],
    "shop": ["shop", "store", "boutique", "mall"],
    "hotel": ["hotel", "motel", "lodging", "airbnb"],
    "service": ["mechanic", "groomer", "salon", "cleaner", "repair"],
}


def _get_places_path():
    """Get the places file path from config or default."""
    config = get_config()
    return config.get("PLACES_PATH", os.path.expanduser("~/.hermes/places.json"))


def load_places():
    """Load all remembered places."""
    places_path = _get_places_path()
    if not os.path.exists(places_path):
        return []
    with open(places_path) as f:
        return json.load(f)


def save_places(places):
    """Save all remembered places."""
    places_path = _get_places_path()
    os.makedirs(os.path.dirname(places_path), exist_ok=True)
    with open(places_path, "w") as f:
        json.dump(places, f, indent=2)


def extract_tags(text):
    """Extract tags from user's description text."""
    text_lower = text.lower()
    tags = set()
    
    for word in POSITIVE_TAGS:
        if word in text_lower:
            tags.add("liked")
            break
    for word in NEGATIVE_TAGS:
        if word in text_lower:
            tags.add("avoid")
            break
    for tag, keywords in TYPE_TAGS.items():
        for kw in keywords:
            if kw in text_lower:
                tags.add(tag)
                break
    
    return list(tags)


def add_place(name, lat, lon, address="", notes="", tags=None):
    """Add a remembered place."""
    places = load_places()
    
    if tags is None:
        tags = []
    auto_tags = extract_tags(notes)
    all_tags = list(set(tags + auto_tags))
    
    place = {
        "id": len(places) + 1,
        "name": name,
        "lat": lat,
        "lon": lon,
        "address": address,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "notes": notes,
        "tags": all_tags,
    }
    
    places.append(place)
    save_places(places)
    return place


def update_place(place_id, **kwargs):
    """Update a remembered place by ID."""
    places = load_places()
    for p in places:
        if p["id"] == place_id:
            p.update(kwargs)
            p["updated"] = datetime.now(timezone.utc).isoformat()
            save_places(places)
            return p
    return None


def search_places(query="", tags=None, near_lat=None, near_lon=None, radius_m=None):
    """
    Search remembered places with two-phase approach:
    1. Structured search with scoring
    2. Fallback: word-by-word matching with related term expansion
    """
    places = load_places()
    
    if not places:
        return []
    
    # Phase 1: Structured search with scoring
    results = []
    
    for p in places:
        score = 0
        
        if query:
            query_lower = query.lower()
            if query_lower in p.get("name", "").lower():
                score += 10
            if query_lower in p.get("notes", "").lower():
                score += 5
            if query_lower in p.get("address", "").lower():
                score += 3
            for tag in p.get("tags", []):
                if query_lower in tag.lower():
                    score += 7
        else:
            score = 1
        
        if tags:
            place_tags = set(p.get("tags", []))
            if not set(tags).intersection(place_tags):
                continue
        
        if near_lat is not None and near_lon is not None:
            dist = haversine(near_lat, near_lon, p["lat"], p["lon"])
            if radius_m and dist > radius_m:
                continue
            if radius_m:
                score += max(0, 10 - (dist / radius_m) * 10)
        
        if score > 0:
            results.append((score, p))
    
    results.sort(key=lambda x: (-x[0], x[1]["timestamp"]))
    scored_results = [r[1] for r in results]
    
    # Phase 2: Fallback search if structured search found nothing
    if not scored_results and query:
        fallback_results = _fallback_search(places, query)
        if fallback_results:
            return fallback_results
    
    return scored_results


def _fallback_search(places, query):
    """Fallback: word-by-word matching with related term expansion."""
    query_words = query.lower().split()
    results = []
    
    related_terms = {
        "restaurant": ["restaurant", "food", "eat", "dining", "cafe", "eatery", "kitchen"],
        "bar": ["bar", "pub", "drinks", "cocktail", "beer", "wine", "tavern"],
        "coffee": ["coffee", "cafe", "espresso", "latte", "coffeehouse"],
        "grocery": ["grocery", "supermarket", "market", "food store", "shop"],
        "park": ["park", "trail", "hike", "outdoor", "garden", "playground"],
        "shop": ["shop", "store", "boutique", "mall", "retail"],
        "hotel": ["hotel", "motel", "lodging", "airbnb", "inn"],
        "liked": ["liked", "love", "favorite", "great", "good", "nice", "enjoy"],
        "avoid": ["avoid", "hate", "bad", "terrible", "dislike", "skip"],
    }
    
    for p in places:
        score = 0
        searchable_text = " ".join([
            p.get("name", ""),
            p.get("address", ""),
            p.get("notes", ""),
            " ".join(p.get("tags", [])),
        ]).lower()
        
        for word in query_words:
            if word in searchable_text:
                score += 5
                continue
            
            for term, related in related_terms.items():
                if word in term or term in word:
                    for related_term in related:
                        if related_term in searchable_text:
                            score += 3
                            break
            
            for field in [p.get("name", ""), p.get("address", ""), p.get("notes", "")]:
                if word in field.lower() or field.lower() in word:
                    score += 2
                    break
        
        if score > 0:
            results.append((score, p))
    
    results.sort(key=lambda x: (-x[0], x[1]["timestamp"]))
    return [r[1] for r in results]


def delete_place(place_id):
    """Delete a remembered place by ID."""
    places = load_places()
    places = [p for p in places if p["id"] != place_id]
    for i, p in enumerate(places, 1):
        p["id"] = i
    save_places(places)
    return True


def haversine(lat1, lon1, lat2, lon2):
    """Distance in meters between two lat/lon points."""
    R = 6371000
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    return R * 2 * atan2(sqrt(a), sqrt(1 - a))


def format_place(place, show_distance=False, from_lat=None, from_lon=None):
    """Format a place for display."""
    lines = []
    lines.append(f"📍 {place['name']}")
    if place.get("address"):
        lines.append(f"   {place['address']}")
    if place.get("notes"):
        lines.append(f"   \"{place['notes']}\"")
    if place.get("tags"):
        lines.append(f"   Tags: {', '.join(place['tags'])}")
    
    ts = place.get("timestamp", "")
    if ts:
        dt = datetime.fromisoformat(ts)
        lines.append(f"   Saved: {dt.strftime('%Y-%m-%d %H:%M')}")
    
    if show_distance and from_lat is not None and from_lon is not None:
        dist = haversine(from_lat, from_lon, place["lat"], place["lon"])
        if dist < 1000:
            lines.append(f"   Distance: {dist:.0f}m")
        else:
            lines.append(f"   Distance: {dist/1000:.1f}km")
    
    lines.append(f"   📍 https://www.google.com/maps/search/?api=1&query={place['lat']},{place['lon']}")
    
    return "\n".join(lines)


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Manage remembered places")
    sub = parser.add_subparsers(dest="command")
    
    add_parser = sub.add_parser("add", help="Remember a place")
    add_parser.add_argument("--name", required=True)
    add_parser.add_argument("--lat", type=float, required=True)
    add_parser.add_argument("--lon", type=float, required=True)
    add_parser.add_argument("--address", default="")
    add_parser.add_argument("--notes", default="")
    add_parser.add_argument("--tags", nargs="*", default=[])
    
    search_parser = sub.add_parser("search", help="Search remembered places")
    search_parser.add_argument("--query", default="")
    search_parser.add_argument("--tags", nargs="*")
    search_parser.add_argument("--near-lat", type=float)
    search_parser.add_argument("--near-lon", type=float)
    search_parser.add_argument("--radius", type=int, help="Radius in meters")
    
    sub.add_parser("list", help="List all remembered places")
    
    delete_parser = sub.add_parser("delete", help="Delete a remembered place")
    delete_parser.add_argument("--id", type=int, required=True)
    
    update_parser = sub.add_parser("update", help="Update a remembered place")
    update_parser.add_argument("--id", type=int, required=True)
    update_parser.add_argument("--notes")
    update_parser.add_argument("--tags", nargs="*")
    
    args = parser.parse_args()
    
    if args.command == "add":
        place = add_place(args.name, args.lat, args.lon, args.address, args.notes, args.tags)
        print(f"✅ Saved: {place['name']} (ID: {place['id']})")
    
    elif args.command == "search":
        results = search_places(args.query, args.tags, args.near_lat, args.near_lon, args.radius)
        if not results:
            print("No matching places found.")
        for p in results:
            print(format_place(p, show_distance=args.near_lat is not None,
                              from_lat=args.near_lat, from_lon=args.near_lon))
            print()
    
    elif args.command == "list":
        places = load_places()
        if not places:
            print("No remembered places yet.")
        for p in places:
            print(format_place(p))
            print()
    
    elif args.command == "delete":
        delete_place(args.id)
        print(f"✅ Deleted place {args.id}")
    
    elif args.command == "update":
        kwargs = {}
        if args.notes:
            kwargs["notes"] = args.notes
        if args.tags:
            kwargs["tags"] = args.tags
        place = update_place(args.id, **kwargs)
        if place:
            print(f"✅ Updated: {place['name']}")
        else:
            print(f"❌ Place {args.id} not found")
