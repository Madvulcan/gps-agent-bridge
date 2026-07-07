# Changelog

## v1.0.8 (2026-07-07)

### Location Pipeline Reliability Overhaul

**location-updater** (the GPS caching daemon):
- **Append-only history** — replaced `load_history()` / `save_history()` (which rewrote the entire JSONL with a 48h cutoff every 30s) with `append_history()` that only appends. Pruning is now solely `location-prune`'s job via cron. This eliminates data loss between compaction runs.
- **Consolidated code** — the `~/.hermes/scripts/` copy was an older version (4.9 KB, no geocode cache, `gpsloc --latlon`) while `/usr/local/bin/` had the newer version (9.5 KB, geocode cache, weather, `gpsloc --tpv`). Both copies are now identical and synced to the git repo at `skills/gps-agent-bridge/scripts/`.
- **ImportError guard** — `config.py` import now wrapped in try/except so the script degrades gracefully if config is missing.
- **Root-run warning** — logs uid and HOME on startup; warns if running as root without proper HOME (catches orphaned processes).
- **Added `config.py`** to `scripts/` directory (was only in `/usr/local/bin/`).

**location-prune**:
- Now the **sole pruner** of `location-history.jsonl` (documented in docstring).
- Added pruned-entry counting and log output (`[prune] Removed N entries...`).

**location-compact** (cron schedule):
- Changed from `15 3 * * *` (once daily, 3:15 AM) to `15 3,7,11,15,19,23 * * *` (6× daily). A single missed cron window no longer loses a whole day of compaction.

**Systemd unit** (`location-updater.service`):
- Added `Environment=HOME=<user home>` — prevents the service from writing to `/root/.hermes/` if the unit is accidentally run as root.
- Added `Environment=PATH=...` — ensures `gpsloc` is found on cron's minimal PATH.
- Changed `Restart=on-failure` → `Restart=always` — service restarts on any exit, not just non-zero.
- Added `WatchdogSec=300` — systemd restarts the service if it goes silent for 5 minutes.
- Added `SyslogIdentifier=location-updater` for clean journal filtering.
- Removed `User=`/`Group=` directives (user systemd already runs as the user; these caused exit code 216/GROUP).

**Crontab**:
- Added `PATH` at the top so all cron scripts find their binaries.

**Documentation updates**:
- `references/location-pipeline-failure-modes.md` — updated to reflect v1.0.8 fixes (compact 6×/day, append-only history, version drift resolved).
- `README.md` — raw tier description updated to note "pruned by cron" and "append-only".
