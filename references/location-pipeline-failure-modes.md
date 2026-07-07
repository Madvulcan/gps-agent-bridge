# Location Pipeline Failure Modes & Recovery

## The two-writer architecture (and its failure states)

`location-updater` runs as a systemd **user** service (managed by systemd, runs as the installing user). Separately, a manually-started copy may be running (orphan). Both write to the same `~/.hermes/location-history.jsonl` and `location.json`.

**Always check BOTH before acting:**

```bash
systemctl --user is-active location-updater                  # service state
ps -eo pid,user,etime,cmd | grep [l]ocation-updater          # any process(es)
```

| Service | Process(es) | Meaning | Action |
|---|---|---|---|
| active | exactly 1 (systemd-managed) | Normal | none |
| active | 2+ (systemd + orphan) | Duplicate writers -> exact-duplicate JSONL entries every cycle | `kill <PID>` the NON-systemd orphan (kill by PID, not `pkill` blindly). Keep the systemd one. |
| **inactive (dead)** | 1+ (orphan, often as **root**, PPID 1/init) | Service was killed (TERM) but an orphan is the SOLE writer. Data still flows but the supervised path is broken. | Kill the orphan, ensure `/usr/local/bin/location-updater` is the canonical (newer) version, then `systemctl --user restart location-updater`. |
| inactive (dead) | none | No writer at all -> history frozen, cache stale | `systemctl --user restart location-updater` |

**Real-world example:** `location-updater.service` showed `inactive (dead)` (killed by TERM days prior), yet a root-owned orphan (PPID 1/init) kept `location.json` and `location-history.jsonl` updating. Without checking both signals, you'd wrongly conclude GPS is "working normally."

**Ownership gotcha:** an orphan started as `root` still writes to the user's `~/.hermes/` (root can write there), so data files stay user-owned. Don't infer "service is healthy" from file ownership alone.

## Compact / DB sync fragility

`location-query --today` reads from `~/.hermes/location-history.db` (SQLite tiers), NOT the raw JSONL. That DB is refreshed by the `location-compact` cron job (`15 3,7,11,15,19,23 * * *`, 6×/day). Two failure modes (item 1 partially resolved in v1.0.8, item 2 fully resolved):

1. **Machine asleep at all 6 compact times -> DB silently stale.** (Mitigated v1.0.8.) Compact now runs 6×/day so a single missed window is caught at the next run. If ALL 6 are missed (machine offline all day), `location-query --today` returns `{"error":"No location data..."}` even though the raw JSONL has today's points. **Manual fix:** `python3 ~/.hermes/scripts/location-compact`.

2. **Data loss from rewrite-based history (FIXED v1.0.8).** Previously, `location-updater` kept a **48h rolling window** by rewriting the entire JSONL file every 30s tick, dropping older entries. Combined with compact only running once daily, anything older than 48h was unrecoverable — e.g. July 6 2026 was permanently lost when compact was skipped. **Fix (v1.0.8):** `location-updater` now uses **append-only** writes (`append_history()`); `location-prune` (every 2h via cron) is the sole process that removes old entries. This guarantees no data is lost between compaction runs.

## Version drift: /usr/local/bin vs ~/.hermes/scripts

There are TWO copies of `location-updater` (kept in sync as of v1.0.8):
- `/usr/local/bin/location-updater` — **canonical/live**. The systemd unit's `ExecStart` points here.
- `~/.hermes/scripts/location-updater` — **git-tracked copy** (symlinked to `skills/gps-agent-bridge/scripts/`).

**As of v1.0.8:** Both copies are identical. The `scripts/` copy was upgraded to match `/usr/local/bin/` (gaining: geocode cache, weather, TPV fields, append-only history). `config.py` was also added to `scripts/`. When making changes, update `scripts/` first then copy to `/usr/local/bin/`, or update both. The git repo at `skills/gps-agent-bridge/scripts/` is the source of truth for propagation.

## Recovery procedure (updated v1.0.8, 2026-07-07)

```bash
# 1. Confirm state
systemctl --user is-active location-updater
ps -eo pid,user,etime,cmd | grep [l]ocation-updater

# 2. If an orphan (esp. root) is the sole writer, kill it
kill <ORPHAN_PID>      # confirm service is dead first

# 3. Ensure /usr/local/bin/location-updater is the newer canonical version
diff ~/.hermes/scripts/location-updater /usr/local/bin/location-updater

# 4. Restart the supervised service as the user
systemctl --user restart location-updater
systemctl --user is-active location-updater    # expect: active

# 5. Refresh the compacted DB so --today works immediately
python3 /usr/local/bin/location-compact
```

## The "missing data" diagnostic flow

1. `location-query --today` empty? -> check raw JSONL: `python3 -c "import json;print(len([1 for l in open(os.path.expanduser('~/.hermes/location-history.jsonl')) if l.strip()]))"`. If JSONL has today's points but DB doesn't -> compact cron was skipped (machine asleep at 3:15). Run compact manually.
2. DB newest row older than expected AND a whole day missing? -> 48h rolling-window cap + prune. Data is gone; not retroactively recoverable.
3. Service dead but data still flowing? -> root orphan sole writer (see matrix above).
4. No data at all and no process? -> restart service; check phone streaming (see android-companion-app.md deep-sleep diagnostic).
