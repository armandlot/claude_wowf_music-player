"""Settings of the companion, with defaults that need no configuration file.

An optional `config.toml` next to `run.bat` can override them; see
`config.example.toml`.
"""

from __future__ import annotations

import tomllib
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Platform:
    name: str
    # Lower-case fragments looked for in the id Windows gives to an app's
    # media session ("Spotify.exe", "AppleInc.AppleMusicWin_...!App", ...).
    apps: list[str]
    # Program names in the Windows volume mixer, for the volume slider.
    processes: list[str]
    # What to open when the platform is asked to play but is not running:
    # a link or an app address such as "spotify:". Empty: never open anything.
    launch: str = ""


def _default_platforms() -> dict[str, Platform]:
    return {
        "spotify": Platform("Spotify", ["spotify"], ["Spotify.exe"], "spotify:"),
        "deezer": Platform("Deezer", ["deezer"], ["Deezer.exe"], "https://www.deezer.com/"),
        "apple": Platform(
            "Apple Music", ["applemusic", "apple music", "itunes"],
            ["AppleMusic.exe", "iTunes.exe"], "https://music.apple.com/",
        ),
        "youtube": Platform(
            "YouTube Music", ["youtube music", "youtubemusic", "ytmusic", "cinhimbnkkaeohfgghhklpknlkffjgod"],
            ["YouTube Music.exe"], "https://music.youtube.com/",
        ),
    }


@dataclass
class Config:
    platforms: dict[str, Platform] = field(default_factory=_default_platforms)
    # Web browsers: used when a platform runs as a web page instead of an app.
    browsers: list[str] = field(default_factory=lambda: [
        "chrome", "msedge", "firefox", "308046b0af4a39cb", "brave", "opera", "vivaldi",
    ])
    browser_processes: list[str] = field(default_factory=lambda: [
        "chrome.exe", "msedge.exe", "firefox.exe", "brave.exe", "opera.exe", "vivaldi.exe",
    ])
    # Open the platform when play is pressed in game and it is not running.
    auto_launch: bool = True
    # Seconds between two screen captures while the beacon is in sight.
    interval: float = 0.05


def load(path: Path | None) -> Config:
    """Defaults, overridden by the TOML file at `path` if it exists."""
    config = Config()
    if path is None or not path.is_file():
        return config

    with path.open("rb") as handle:
        data = tomllib.load(handle)

    for key in ("auto_launch", "interval", "browsers", "browser_processes"):
        if key in data:
            setattr(config, key, data[key])
    config.browsers = [name.lower() for name in config.browsers]

    for key, values in data.get("platforms", {}).items():
        platform = config.platforms.get(key)
        if platform is None:
            raise ValueError(f"config: unknown platform {key!r} (known: {', '.join(config.platforms)})")
        for name in ("apps", "processes", "launch"):
            if name in values:
                setattr(platform, name, values[name])
        platform.apps = [app.lower() for app in platform.apps]
    return config
