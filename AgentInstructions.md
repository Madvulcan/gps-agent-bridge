# Agent Instructions — gps-agent-bridge Setup

**Read this file if a user asks you to set up gps-agent-bridge, or if they say "set up my phone as a GPS receiver" or similar.**

Your goal: guide the user through the entire setup conversationally. Don't dump all the steps at once — ask questions, explain what you're doing and why, and adapt to their responses.

## Before You Start: Check Your Capabilities

**Can you write files on the user's desktop?** If you're running in a sandboxed Hermes environment, you may have limited file write access. The `config.json` file is in the project directory (which you control), so you can always write to it. System-level changes (installing packages, configuring systemd, opening firewall) require sudo — if you can't sudo, you'll need to ask the user to run those commands.

**Can you run shell commands?** You'll need terminal access to run the install script, check service status, and verify the setup. If you don't have terminal access, you'll need to walk the user through every command.

**Do you have access to the repo?** If the user cloned the repo for you, note the path — you'll need it for the install script and service files.

---

## Phase 1: Explain and Assess

Start by explaining what this does in one or two sentences:

> "This sets up your phone as a remote GPS receiver for your desktop. Your phone's GPS data gets streamed to your desktop over your local network, so I always know where you can answer questions like 'what's near me?' or 'flights from my location.' It works with both Android and iOS."

Then ask:

### 1. Phone platform

**"Are you using an Android phone or an iPhone?"**

- **Android (recommended)** → They'll install [GPS AgentBridge](https://github.com/Madvulcan/GPS-AgentBridge-Android) — our companion app with distance-based transmission for battery efficiency. Download the APK from the releases page and install via `adb install` or file manager.
- **Android (alternative)** → They can also use [gpsdRelay](https://f-droid.org/packages/io.github.project_kaat.gpsdrelay/) from F-Droid (free), but it uses fixed-interval polling which drains more battery.
- **iOS** → They'll install [NMEA Send Location](https://apps.apple.com/us/app/nmea-send-location/id6749798097) from the App Store (free), or [GPS2IP](https://apps.apple.com/us/app/gps-2-ip/id408625926) (~$5) as an alternative.

### 2. Network setup

**"Do you use Tailscale, or are your phone and desktop on the same local WiFi network?"**

- **Tailscale** → Great. You'll need the desktop's Tailscale IP. Ask them to run `tailscale ip -4` on the desktop, or look it up yourself if you have terminal access. It'll look like `100.x.x.x`.
- **Same WiFi** → You'll need the desktop's local IP. Ask them to run `hostname -I` on the desktop, or look it up yourself. It'll look like `192.168.x.x` or `10.x.x.x`.
- **Neither / not sure** → Explain that both devices need to be on the same network. If they don't have Tailscale, offer to help them set it up (it's free for personal use and makes this much easier), or guide them through finding their local IP.

### 3. Desktop OS

**"What operating system is your desktop running?"**

- **Linux (Ubuntu/Debian/Mint/Arch/Fedora)** → Full support via the install script
- **macOS** → Partial support. gpsd can be installed via Homebrew. Some scripts may need adjustments.
- **Windows** → Not directly supported. Suggest WSL2 or a Linux VM.

---

## Phase 2: Install on Desktop

### If you have terminal access with sudo:

Run the install script directly:

```bash
cd /path/to/gps-agent-bridge
./install.sh
```

For headless servers (no display):
```bash
./install.sh --headless
```

To check prerequisites without installing:
```bash
./install.sh --check
```

The script will:
1. Install system dependencies (`gpsd`, `xvfb`, etc.)
2. Configure and start the gpsd systemd service
3. Open the firewall for UDP port 2948
4. Install CLI tools to `/usr/local/bin/`
5. Create the data directory (`~/.hermes/`)
6. Generate a `config.json` config file with the detected IP

### If you have terminal access WITHOUT sudo:

Run the script — it will fail at sudo steps and tell you what needs root. Then ask the user to run those specific commands, or ask them to run `sudo ./install.sh` themselves.

### If you do NOT have terminal access:

Walk the user through each step manually. Ask them to:

1. Open a terminal
2. Install gpsd: `sudo apt install gpsd gpsd-clients` (or equivalent for their distro)
3. Clone the repo: `git clone <repo-url> && cd gps-agent-bridge`
4. Run: `sudo ./install.sh`
5. Tell you when it's done

**After the install script runs, the config file needs to be updated with the correct IP address.**

The config file is `config.json` in the project directory. Unlike the user's Hermes `.env` (which is write-protected), the agent has full read/write access to this file since it's in the repo.

### If you CAN edit files directly:

Update the config file with the correct IP:

```bash
cd /path/to/gps-agent-bridge
python3 -c "
import json, sys
with open('config.json') as f:
    config = json.load(f)
config['GPSD_HOST'] = 'THE_IP_ADDRESS'
with open('config.json', 'w') as f:
    json.dump(config, f, indent=2)
print('Config updated:', config['GPSD_HOST'])
"
```

Replace `THE_IP_ADDRESS` with the actual IP from Phase 1.

### If you CANNOT edit files directly (sandboxed agent):

Ask the user to create/edit the config file:

> "I need you to create a config file. Open a terminal and run:
>
> ```bash
> cd /path/to/gps-agent-bridge
> echo '{\"GPSD_HOST\": \"THE_IP_ADDRESS\"}' > config.json
> ```
>
> Replace `THE_IP_ADDRESS` with **[the IP from Phase 1]**.
>
> Let me know when you've done this."

**Do NOT proceed to Phase 3 until the config is set.** The entire setup depends on the correct IP address.

If the user is on macOS, explain that they'll need to:
1. Install Homebrew if they don't have it: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
2. Install gpsd: `brew install gpsd`
3. Start gpsd manually: `gpsd -G -n -F /tmp/gpsd.sock udp://*:2948`
4. Note: the gmaps scraper won't work on macOS without xvfb; the browser tool is the fallback

---

## Phase 3: Set Up the Phone

### ⚠️ Before You Start: Permissions & Background Execution

**This is the most common point of failure.** The GPS relay app needs specific permissions and settings to work reliably. Walk the user through ALL of these steps — don't skip any.

**Both Android and iOS require:**

1. **Location access** — The app needs "Always" or "All the time" location permission, not just "While using the app." Without this, GPS won't work when the app is in the background.
   - Android: Settings → Apps → [app name] → Permissions → Location → "Allow all the time"
   - iOS: Settings → Privacy & Security → Location Services → [app name] → "Always"

2. **Network access** — The app needs WiFi or mobile data access to send NMEA data to the desktop.
   - Android: Settings → Apps → [app name] → Permissions → make sure WiFi/data is not restricted
   - iOS: Settings → [app name] → make sure "Wireless Data" is enabled

3. **Background execution** — The app must be allowed to run in the background. If the OS kills it, GPS streaming stops.
   - Android: Settings → Apps → [app name] → Battery → "Unrestricted" or "Don't optimize"
   - iOS: Settings → [app name] → enable "Background App Refresh"

4. **Disable battery optimization** — Aggressive battery saving can kill the app.
   - Android: Settings → Battery → Battery optimization → [app name] → "Don't optimize"
   - iOS: Settings → Battery → make sure Low Power Mode is OFF while using the app

5. **Keep the app in the foreground initially** — Some Android ROMs (especially Xiaomi, Huawei, Samsung) aggressively kill background apps. Tell the user:
   - "Keep the app open on your screen for the first 30 seconds after starting streaming"
   - "If your phone has a 'lock' or 'pin' feature for recent apps, use it to prevent the OS from closing the app"
   - "If GPS stops working after a few minutes, check your phone's battery optimization settings"

**If the user's phone kills the app in the background, GPS streaming will stop and I won't be able to see their location.** This is the #1 issue users encounter.

---

### Android (GPS AgentBridge — recommended)

Walk the user through:

1. On their computer (or yours), download the APK from [GitHub releases](https://github.com/Madvulcan/GPS-AgentBridge-Android/releases)
2. Install it on the phone:
   - Via ADB: `adb install gps-agent-bridge-v1.0.0-release.apk`
   - Or transfer the APK file to the phone and install from the file manager
3. Open the app — it will launch the onboarding flow
4. **Grant location permission** — tap "Grant foreground location," then "Grant background location"
5. **Disable battery optimization** — tap "Disable battery optimization" (critical for reliable background streaming)
6. Go to **Settings → Destination servers** → add a new target:
   - **Host:** The IP address from Phase 1
   - **Port:** 2948
7. Return to the main screen and tap **START**
8. The app handles transmission intervals automatically — no manual configuration needed. It uses distance-based triggers (default: 500m threshold, 10-min max interval) for optimal battery life.

> 💡 **Battery tip:** GPS AgentBridge uses distance-based transmission — it only sends when you've moved >500m, with a 10-min max interval safety net. This provides <0.2%/hour battery drain when stationary, vs ~2-5%/hour with fixed-interval apps. Adjust thresholds in Settings if needed.

### Android (gpsdRelay — alternative)

If the user prefers F-Droid or can't sideload APKs:

1. Open F-Droid on their phone
2. Search for "gpsdRelay" and install it
3. Open the app
4. Set **Protocol:** UDP
5. Set **Host:** The IP address from Phase 1
6. Set **Port:** 2948
7. Set **NMEA source:** Auto (or Generated if Auto doesn't work)
8. Tap the play button (▶) to start streaming
9. **Configure transmission interval** — In gpsdRelay settings, look for "Interval" or "Update frequency." The default is very frequent (every ~1 second), which drains battery quickly. **Recommended:** Set to 60 seconds (60000ms) for good balance of accuracy and battery life.

> ⚠️ **Note:** gpsdRelay uses fixed-interval polling which drains significantly more battery than GPS AgentBridge's distance-based triggers. Recommend GPS AgentBridge if possible.

### iOS (GPS2IP)

Walk the user through:

**iOS (NMEA Send Location — free):**
1. Open the App Store on their iPhone
2. Search for "NMEA Send Location" and install it (free)
3. Open the app
4. Set **Host:** The IP address from Phase 1
5. Set **Port:** 2948
6. Enable streaming
7. **Configure transmission interval** — Look for "Interval" or "Update frequency" in the app settings. The default is very frequent (every ~1 second), which drains battery quickly. **Recommended:** Set to 60 seconds (60000ms) for good balance of accuracy and battery life. For even better battery savings, 5-10 minutes (300000-600000ms) works well if you don't need real-time precision.

> 💡 **Battery tip:** Increasing the transmission interval from 1s to 60s can extend battery life from ~2 hours to ~10+ hours. Even 5-10 minute intervals are sufficient for most "where am I?" use cases.

**iOS (GPS2IP — alternative, ~$5):**
1. Install GPS2IP from the App Store
2. Settings → UDP Push → set IP and Port 2948
3. Enable UDP Push
4. Return to main screen and enable GPS2IP

---

## Phase 4: Verify

Once the phone is streaming, verify the setup:

```bash
gpsloc --human
```

You should see the phone's live GPS coordinates. If you get an error:

- **"Connection refused"** → gpsd isn't running. Check: `systemctl status gpsd`
- **"No TPV data"** → gpsd is running but not receiving data from the phone. Check:
  - Is the phone app actively streaming (play button pressed)?
  - Is the IP address in `config.json` correct?
  - Is the firewall blocking UDP 2948? Check: `sudo ufw status`
  - Are both devices on the same network?

If the `address` field in `location.json` is empty, that's normal — reverse geocoding can fail. The lat/lon will still be correct.

---

## Phase 5: Install the Location Updater (Optional but Recommended)

For the agent to always have fresh location data, install the background updater:

```bash
sudo cp systemd/location-updater.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now location-updater.service
```

This writes the latest GPS position to `~/.hermes/location.json` every 30 seconds.

Verify it's working:

```bash
cat ~/.hermes/location.json
```

You should see `status: active` with fresh coordinates.

---

## Phase 6: Test the Full Pipeline

Run a quick test to make sure everything works end-to-end:

```bash
gpsloc --human
gpsnear "coffee shops" --source gmaps --radius 3000
```

If both return results, the setup is complete.

Tell the user:

> "All set! Your phone is now streaming GPS to your desktop. I can find places near you, calculate distances, look up where you've been, and use your location for things like flight searches. Just ask me things like 'what restaurants are near me?' or 'flights from here to Chicago.'"

---

## Troubleshooting Common Issues

### "gpsd won't start"
```bash
journalctl -u gpsd --no-pager -n 20
```
Common cause: port already in use. Check: `ss -ulnp | grep 2948`

### "gpsd won't start (SHM error)"
If you see `SHM: shmctl(...) for IPC_RMID failed, Operation not permitted`, there are stale shared memory segments from a previous gpsd instance. Fix:
```bash
sudo bash -c 'killall -9 gpsd 2>/dev/null; rm -f /run/gpsd.sock; for key in $(ipcs -m | grep root | awk "{print \$2}"); do ipcrm -m \$key 2>/dev/null; done; systemctl start gpsd.service'
```

### "gpsd starts then exits immediately"
The systemd service needs the `-N` flag (no-wait, forks to background). Without it, gpsd stays in the foreground and systemd considers it "exited successfully". Check `/usr/lib/systemd/system/gpsd.service` — the ExecStart should include `-N`.

### "Phone connects but no GPS fix"
- The phone needs a clear view of the sky for the first fix (cold start can take 30-60 seconds)
- Once it has a fix, it'll update continuously

### "location.json shows status: unavailable"
- The location updater service isn't running: `systemctl status location-updater`
- Or gpsd isn't receiving data from the phone

### "gpsnear returns no results"
- OSM rate limiting is normal — use `--source gmaps` instead
- If gmaps also returns 0, the invisible_playwright scraper may be blocked — use the browser tool directly

### "GPS streaming stops after a few minutes"
- The phone's OS is killing the app in the background. This is the #1 issue.
- Android: Check battery optimization settings. Set to "Unrestricted" or "Don't optimize." Some ROMs (Xiaomi, Huawei, Samsung) are especially aggressive.
- iOS: Enable "Background App Refresh" for the app. Make sure Low Power Mode is off.
- Tell the user to keep the app in the foreground for the first 30 seconds after starting.
- If the issue persists, the user may need to lock the app in their recent apps list or disable battery optimization entirely.

### "I moved and my location is stale"
- The phone needs to be streaming for the cache to update
- Run `gpsloc --human` to force a fresh read from gpsd

---

## What the User Can Do After Setup

Tell the user they can now ask things like:
- "What restaurants are near me?"
- "Find coffee shops within walking distance"
- "How far is [place] from here?"
- "Flights from my location to [city]"
- "What's the weather like here?"
- "Directions to [address]"
- "Where was I last Tuesday?"

---

## Files You May Need to Edit

| File | When | Agent can edit? |
|------|------|-----------------|
| `config.json` | Set GPSD_HOST IP after install | ✅ Yes — in project dir |
| `~/.hermes/location.json` | Manual override if GPS unavailable | ⚠️ May be sandboxed |

## Dependencies to Check

Before starting, verify these are available:
- `python3` (3.10+)
- `gpsd` package (installable via apt/pacman/dnf/brew)
- `xvfb` (for headless gmaps scraping)
- `pipx` (for invisible_playwright, optional)
- `tailscale` (optional, for remote access)
