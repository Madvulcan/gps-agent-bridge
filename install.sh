#!/usr/bin/env bash
# gps-agent-bridge install script
# Sets up GPS relay from mobile phone to Linux desktop via gpsd.
# Supports Android (GPS AgentBridge, gpsdRelay) and iOS (NMEA Send Location, GPS2IP).
#
# Usage:
#   ./install.sh              # Full install (requires sudo)
#   ./install.sh --headless   # For servers without a display
#   ./install.sh --check      # Check prerequisites without installing
#
# This script is designed to be runnable by an AI agent with terminal access.
# It auto-detects the OS and adapts accordingly.
# If you don't have sudo, the script will tell you which commands need root.

set -euo pipefail

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# === Detect environment ===
HEADLESS=false
[[ "${1:-}" == "--headless" ]] && HEADLESS=true

OS="unknown"
if [[ -f /etc/os-release ]]; then
# shellcheck source=/dev/null
    . /etc/os-release
    OS="${ID}"
fi

ARCH=$(uname -m)
PYTHON_CMD=""
INVISIBLE_PYTHON=""

info "Detected OS: ${OS} (${ARCH})"
info "Headless mode: ${HEADLESS}"

# === Handle --check mode ===
if [[ "${1:-}" == "--check" ]]; then
    echo ""
    echo "=== Prerequisite Check ==="
    echo "OS: ${OS} (${ARCH})"
    echo "Python: $(${PYTHON_CMD} --version 2>/dev/null || echo 'NOT FOUND')"
    echo "gpsd: $(command -v gpsd 2>/dev/null && echo 'installed' || echo 'NOT INSTALLED')"
    echo "xvfb-run: $(command -v xvfb-run 2>/dev/null && echo 'installed' || echo 'not installed')"
    echo "pipx: $(command -v pipx 2>/dev/null && echo 'installed' || echo 'NOT INSTALLED')"
    echo "sudo: $(command -v sudo 2>/dev/null && echo 'available' || echo 'NOT AVAILABLE')"
    echo ""
    echo "IP addresses:"
    hostname -I 2>/dev/null || echo "  Could not detect"
    echo ""
    echo "Ports in use on 2948/udp:"
    ss -ulnp 2>/dev/null | grep 2948 || echo "  (none)"
    exit 0
fi

# === Find or install Python ===
find_python() {
    for cmd in python3.12 python3.11 python3.10 python3; do
        if command -v "$cmd" &>/dev/null; then
            PYTHON_CMD="$cmd"
            return
        fi
    done
    error "Python 3.10+ is required but not found. Please install it first."
}
find_python
info "Python: $(${PYTHON_CMD} --version)"

# === Install system dependencies ===
install_system_deps() {
    info "Installing system dependencies..."
    
    case "$OS" in
        ubuntu|debian|linuxmint|pop)
            sudo apt-get update -qq
            sudo apt-get install -y -qq gpsd gpsd-clients python3-pip python3-venv xvfb python3-pipx 2>/dev/null || \
                warn "Some packages may have failed. Continuing..."
            ;;
        arch|manjaro)
            sudo pacman -Sy --noconfirm gpsd python-pip xvfb python-pipx 2>/dev/null || \
                warn "Some packages may have failed. Continuing..."
            ;;
        fedora)
            sudo dnf install -y gpsd python3-pip xorg-x11-server-Xvfb python3-pipx 2>/dev/null || \
                warn "Some packages may have failed. Continuing..."
            ;;
        darwin)
            if command -v brew &>/dev/null; then
                brew install gpsd 2>/dev/null || warn "gpsd install via brew failed. Continuing..."
            else
                warn "Homebrew not found. You may need to install gpsd manually."
            fi
            ;;
        *)
            warn "Unknown OS '${OS}'. You may need to manually install: gpsd, python3-pip, xvfb, pipx"
            ;;
    esac
}

install_system_deps

# === Install invisible_playwright ===
install_invisible_playwright() {
    info "Setting up invisible_playwright (stealth browser for Google Maps)..."
    
    if command -v pipx &>/dev/null; then
        pipx install git+https://github.com/feder-cr/invisible_playwright.git 2>/dev/null || \
            warn "pipx install failed. Trying pip..."
    fi
    
    # Find the installed python path
    INVISIBLE_PYTHON=""
    for candidate_dir in \
        "${HOME}/.local/share/pipx/venvs/invisible-playwright" \
        "${HOME}/.local/pipx/venvs/invisible-playwright" \
        "${HOME}/.venvs/invisible-playwright" \
        "${HOME}/.conda/envs/invisible-playwright"; do
        candidate="${candidate_dir}/bin/python"
        if [[ -x "$candidate" ]]; then
            INVISIBLE_PYTHON="$candidate"
            break
        fi
    done
    
    if [[ -n "$INVISIBLE_PYTHON" ]]; then
        info "Found invisible_playwright Python: ${INVISIBLE_PYTHON}"
        # Fetch the Firefox binary
        info "Fetching Firefox binary for invisible_playwright..."
        "$INVISIBLE_PYTHON" -m invisible_playwright fetch 2>/dev/null || \
            warn "Firefox fetch failed. You may need to run manually: ${INVISIBLE_PYTHON} -m invisible_playwright fetch"
    else
        warn "invisible_playwright not found. Google Maps scraping will not work."
        warn "Install with: pipx install git+https://github.com/feder-cr/invisible_playwright.git"
        warn "Then run: <python> -m invisible_playwright fetch"
    fi
}

install_invisible_playwright

# === Create config file ===
setup_config() {
    # Write config to the real user's home, even under sudo
    local real_home
    if [[ -n "${SUDO_USER:-}" ]]; then
        real_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    else
        real_home="$HOME"
    fi
    local config_dir="${real_home}/.hermes"
    local config_file="${config_dir}/config.json"
    
    mkdir -p "$config_dir"
    
    if [[ -f "$config_file" ]]; then
        info "Config file already exists: ${config_file}"
        return
    fi
    
    info "Creating configuration file..."
    
    # Detect primary network interface IP (for phone app to connect to)
    local default_ip
    default_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "192.168.1.100")
    
    # Detect timezone
    local default_tz
    default_tz=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}' || echo "America/New_York")
    
    # Create config.json
    # Note: GPSD_HOST is always 127.0.0.1 for the agent's local gpsd connection.
    # PHONE_TARGET_HOST is the IP the phone app should send NMEA data to.
    cat > "$config_file" << EOF
{
  "GPSD_HOST": "127.0.0.1",
  "GPSD_UDP_PORT": 2948,
  "GPSD_TCP_PORT": 2947,
  "PHONE_TARGET_HOST": "${default_ip}",
  "LOCATION_CACHE_PATH": "${real_home}/.hermes/location.json",
  "LOCATION_HISTORY_PATH": "${real_home}/.hermes/location-history.db",
  "LOCATION_RAW_PATH": "${real_home}/.hermes/location-history.jsonl",
  "PLACES_PATH": "${real_home}/.hermes/places.json",
  "DEFAULT_CITY": "",
  "INVISIBLE_PYTHON_PATH": "${INVISIBLE_PYTHON:-}",
  "GPSD_SERVICE_NAME": "gpsd",
  "UPDATER_SERVICE_NAME": "location-updater",
  "TZ": "${default_tz}"
}
EOF
    
    # Fix ownership if running under sudo
    if [[ -n "${SUDO_USER:-}" ]]; then
        sudo chown -R "${SUDO_USER}:${SUDO_USER}" "$config_dir"
    fi
    
    info "Config created: ${config_file}"
    warn "PHONE_TARGET_HOST is set to ${default_ip} — configure your phone app to send NMEA to this IP"
    warn "If using Tailscale, change PHONE_TARGET_HOST to your Tailscale IP: tailscale ip -4"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup_config

# === Install scripts ===
install_scripts() {
    info "Installing scripts to /usr/local/bin..."
    
    # Copy all scripts from scripts/ dir (both .py and extensionless)
    for script_path in "${SCRIPT_DIR}/scripts"/*; do
        # Skip service files, directories, and config helper
        local script_name
        script_name=$(basename "$script_path")
        [[ -d "$script_path" ]] && continue
        [[ "$script_name" == *.service ]] && continue
        [[ "$script_name" == config.py ]] && continue
        sudo cp "$script_path" "/usr/local/bin/${script_name}"
        sudo chmod +x "/usr/local/bin/${script_name}"
        info "  Installed: ${script_name}"
    done
    
    # Copy config.py as well (needed by scripts via sys.path)
    if [[ -f "${SCRIPT_DIR}/scripts/config.py" ]]; then
        sudo cp "${SCRIPT_DIR}/scripts/config.py" "/usr/local/bin/config.py"
        info "  Installed: config.py"
    fi
}

install_scripts

# === Configure and start gpsd ===
setup_gpsd() {
    # macOS doesn't use systemd
    if [[ "$OS" == "darwin" ]]; then
        info "macOS detected — skipping systemd setup"
        info "To start gpsd on macOS, run:"
        info "  brew services start gpsd"
        info "Or manually:"
        info "  gpsd -G -n -F /tmp/gpsd.sock udp://*:2948"
        return
    fi
    
    # Linux: systemd setup
    if ! command -v systemctl &>/dev/null; then
        warn "systemd not found. You may need to start gpsd manually:"
        warn "  gpsd -G -n -F /run/gpsd.sock udp://*:2948"
        return
    fi
    
    info "Configuring gpsd..."
    
    # Read port from config.json if it exists, otherwise default
    local udp_port=2948
    local config_file="${SCRIPT_DIR}/config.json"
    if [[ -f "$config_file" ]]; then
        udp_port=$(python3 -c "import json; print(json.load(open('${config_file}')).get('GPSD_UDP_PORT', 2948))" 2>/dev/null || echo 2948)
    fi
    
    # Create a gpsd config that listens on all interfaces
    local gpsd_config="/etc/default/gpsd"
    
    # Backup existing config
    if [[ -f "$gpsd_config" ]]; then
        sudo cp "$gpsd_config" "${gpsd_config}.bak.$(date +%s)"
    fi
    
    sudo tee "$gpsd_config" > /dev/null << EOF
# gpsd configuration for gps-agent-bridge
# Listen on all interfaces for remote GPS sources
DEVICES=""
GPSD_OPTIONS="-G -n -F /run/gpsd.sock"
EOF

    # Create systemd override
    sudo mkdir -p /etc/systemd/system/gpsd.service.d
    sudo tee /etc/systemd/system/gpsd.service.d/override.conf > /dev/null << EOF
[Service]
ExecStart=
ExecStart=/usr/sbin/gpsd -G -n -F /run/gpsd.sock udp://*:${udp_port}
Restart=on-failure
RestartSec=5
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable gpsd.service 2>/dev/null || true
    sudo systemctl restart gpsd.service 2>/dev/null || true
    
    # Verify
    if systemctl is-active --quiet gpsd.service 2>/dev/null; then
        info "gpsd service is running"
    else
        warn "gpsd service may not be running. Check: systemctl status gpsd"
    fi
}

setup_gpsd

# === Configure firewall ===
setup_firewall() {
    # Read port from config.json if it exists, otherwise default
    local udp_port=2948
    local config_file="${SCRIPT_DIR}/config.json"
    if [[ -f "$config_file" ]]; then
        udp_port=$(python3 -c "import json; print(json.load(open('${config_file}')).get('GPSD_UDP_PORT', 2948))" 2>/dev/null || echo 2948)
    fi
    
    info "Configuring firewall..."
    
    if command -v ufw &>/dev/null; then
        sudo ufw allow "${udp_port}/udp" comment "gps-agent-bridge GPS data" 2>/dev/null || true
        info "UFW rule added for UDP ${udp_port}"
    elif command -v firewall-cmd &>/dev/null; then
        sudo firewall-cmd --permanent --add-port="${udp_port}/udp" 2>/dev/null || true
        sudo firewall-cmd --reload 2>/dev/null || true
        info "firewalld rule added for UDP ${udp_port}"
    else
        warn "No firewall manager found. Manually open UDP port ${udp_port}"
    fi
}

setup_firewall

# === Install systemd services ===
install_services() {
    # Skip on macOS
    if [[ "$OS" == "darwin" ]]; then
        info "macOS detected — skipping systemd service setup"
        return
    fi
    
    if ! command -v systemctl &>/dev/null; then
        warn "systemd not found — skipping service setup"
        return
    fi
    
    info "Installing systemd services..."
    
    # Determine real home directory (handles sudo)
    local real_home
    if [[ -n "${SUDO_USER:-}" ]]; then
        real_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    else
        real_home="$HOME"
    fi
    
    # Copy service files from systemd/ dir, templating __HOME__ placeholder
    for svc_path in "${SCRIPT_DIR}/systemd"/*.service; do
        local svc_name
        svc_name=$(basename "$svc_path")
        # Replace __HOME__ placeholder with the actual home directory
        sed "s|__HOME__|${real_home}|g" "$svc_path" | sudo tee "/usr/lib/systemd/system/${svc_name}" > /dev/null
        info "  Installed: ${svc_name} (HOME=${real_home})"
    done
    
    # Reload and enable
    sudo systemctl daemon-reload
    sudo systemctl enable gpsd.service 2>/dev/null || true
    sudo systemctl enable gpsd-watcher.service 2>/dev/null || true
    sudo systemctl enable location-updater.service 2>/dev/null || true
    
    # Start services
    sudo systemctl start gpsd.service 2>/dev/null || true
    sudo systemctl start gpsd-watcher.service 2>/dev/null || true
    sudo systemctl start location-updater.service 2>/dev/null || true
    
    info "Services installed and enabled"
}

install_services

# === Create data directories ===
setup_dirs() {
    mkdir -p "${HOME}/.hermes"
    mkdir -p "${HOME}/.hermes/scripts"
    info "Data directory: ${HOME}/.hermes"
}

setup_dirs

# === Summary ===
echo ""
echo "============================================"
echo "  gps-agent-bridge installation complete"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Edit ~/.hermes/config.json to set PHONE_TARGET_HOST to your desktop's IP"
echo "     For Tailscale: tailscale ip -4"
echo "     For local network: hostname -I"
echo "     (GPSD_HOST should stay as 127.0.0.1)"
echo ""
echo "  2. On your phone, install the GPS relay app:"
echo "     Android (recommended): GPS AgentBridge"
echo "       Download APK: https://github.com/Madvulcan/GPS-AgentBridge-Android/releases"
echo "       Install via: adb install gps-agent-bridge-v1.0.0-release.apk"
echo "     Android (alternative): gpsdRelay (F-Droid)"
echo "     iOS: NMEA Send Location (App Store, free)"
echo ""
echo "  3. Configure the app to send NMEA to:"
echo "     IP: (your PHONE_TARGET_HOST from step 1)"
echo "     Port: 2948"
echo "     Protocol: UDP"
echo ""
echo "  4. Start streaming on your phone, then verify:"
echo "     gpsloc --human"
echo ""
echo "Config file: ~/.hermes/config.json"
echo "Docs: ${SCRIPT_DIR}/README.md"
