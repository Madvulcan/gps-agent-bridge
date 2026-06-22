#!/usr/bin/env python3
"""
config.py - Shared configuration loader for gps-agent-bridge tools.

Loads configuration from ~/.config/gps-agent-bridge/config.json
Fallback: <project_dir>/config.json (for development)

The agent has full read/write access to the global config path.
"""

import json
import os
import sys

# Default configuration
DEFAULTS = {
    "GPSD_HOST": "127.0.0.1",
    "GPSD_UDP_PORT": 2948,
    "GPSD_TCP_PORT": 2947,
    "LOCATION_CACHE_PATH": os.path.expanduser("~/.hermes/location.json"),
    "LOCATION_HISTORY_PATH": os.path.expanduser("~/.hermes/location-history.db"),
    "LOCATION_RAW_PATH": os.path.expanduser("~/.hermes/location-history.jsonl"),
    "DEFAULT_CITY": "",
    "INVISIBLE_PYTHON_PATH": "",
    "GPSD_SERVICE_NAME": "gpsd",
    "UPDATER_SERVICE_NAME": "location-updater",
}


def _get_config_path():
    """Get the path to the config file.
    
    Priority:
    1. ~/.hermes/config.json (global, agent-writable, persistent)
    2. <project_dir>/config.json (development fallback)
    """
    # Global config path (preferred)
    global_path = os.path.expanduser("~/.hermes/config.json")
    if os.path.exists(global_path):
        return global_path
    
    # Fallback: project directory
    project_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    project_path = os.path.join(project_dir, "config.json")
    if os.path.exists(project_path):
        return project_path
    
    # Return global path as default (will be created on first save)
    return global_path


def load_config():
    """Load configuration from config.json."""
    config = dict(DEFAULTS)
    
    config_path = _get_config_path()
    if os.path.exists(config_path):
        try:
            with open(config_path) as f:
                user_config = json.load(f)
            config.update(user_config)
        except (json.JSONDecodeError, IOError):
            pass
    
    return config


def save_config(config):
    """Save configuration to the global config path."""
    config_path = os.path.expanduser("~/.hermes/config.json")
    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)
    return config_path


def update_config(updates):
    """Update specific config values and save."""
    config = load_config()
    config.update(updates)
    return save_config(config)


# Singleton
_CONFIG = None

def get_config():
    """Get the current config (cached)."""
    global _CONFIG
    if _CONFIG is None:
        _CONFIG = load_config()
    return _CONFIG


def refresh_config():
    """Force reload config from disk."""
    global _CONFIG
    _CONFIG = load_config()
    return _CONFIG
