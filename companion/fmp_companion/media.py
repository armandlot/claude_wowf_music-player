"""What the companion needs from the operating system's media controls.

`media_windows.py` implements these two interfaces on Windows; the tests use
a fake. The functions below hold the rules that do not depend on Windows:
which media session belongs to which platform.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Protocol

from .config import Config, Platform


class MediaSession(Protocol):
    """One app that is playing, or ready to play, music."""

    app_id: str

    def is_playing(self) -> bool: ...
    async def play(self) -> bool: ...
    async def pause(self) -> bool: ...
    async def next(self) -> bool: ...
    async def previous(self) -> bool: ...
    async def toggle_shuffle(self) -> bool: ...
    async def cycle_repeat(self) -> bool: ...
    async def now_playing(self) -> tuple[str, str] | None:
        """(artist, title) of the current track, if the app tells."""
        ...


class MediaBackend(Protocol):
    async def find_session(self, platform: str) -> MediaSession | None:
        """The session to control for a platform key ("auto", "spotify", ...)."""
        ...

    def set_volume(self, session: MediaSession, percent: int) -> bool:
        """Sets the app's volume in the system mixer. False if it could not."""
        ...

    def launch(self, platform: str) -> bool:
        """Opens the platform's app or web page. False if nothing was opened."""
        ...


def is_browser(app_id: str, config: Config) -> bool:
    lowered = app_id.lower()
    return any(browser in lowered for browser in config.browsers)


def matches(app_id: str, platform: Platform) -> bool:
    lowered = app_id.lower()
    return any(fragment in lowered for fragment in platform.apps)


def pick_session(app_ids: Sequence[str], playing: Sequence[bool], platform: Platform, config: Config) -> int | None:
    """Index of the session to control for `platform`, or None.

    The platform's own app wins. Failing that, a web browser is assumed to
    hold the platform's web player. Among several candidates, one that is
    already playing wins.
    """
    own = [i for i, app_id in enumerate(app_ids) if matches(app_id, platform)]
    browsers = [i for i, app_id in enumerate(app_ids) if is_browser(app_id, config)]
    for candidates in (own, browsers):
        for i in candidates:
            if playing[i]:
                return i
        if candidates:
            return candidates[0]
    return None


def mixer_names(app_id: str, config: Config) -> set[str]:
    """Lower-case program names whose mixer volume belongs to this session."""
    lowered = app_id.lower()
    names: set[str] = set()
    if lowered.endswith(".exe"):
        names.add(lowered.rsplit("\\", 1)[-1])
    if is_browser(app_id, config):
        names.update(p.lower() for p in config.browser_processes if p.lower().removesuffix(".exe") in lowered)
    for platform in config.platforms.values():
        if matches(app_id, platform):
            names.update(p.lower() for p in platform.processes)
    return names
