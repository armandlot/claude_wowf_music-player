"""Watches the screen for the beacon.

Only pixels are read, through the same screen-capture service a screenshot
tool uses. Once the beacon is found, just its small rectangle is captured;
the whole screen is searched only while the beacon is out of sight.
"""

from __future__ import annotations

import time
from collections.abc import Callable
from typing import Any, Protocol

import numpy as np

from .locator import Geometry, find_beacon, read_message
from .protocol import BeaconMessage

CORNER_SIZE = (640, 96)     # the game draws the beacon in a corner: look there first
CORNER_SCAN_EVERY = 1.0     # seconds between two looks at the screen corners
FULL_SCAN_EVERY = 5.0       # seconds between two searches of the whole screen
MISSES_BEFORE_LOST = 6      # unreadable captures tolerated before giving up the lock

Region = dict[str, int]     # left, top, width, height in screen pixels


class Grabber(Protocol):
    def monitors(self) -> list[Region]: ...
    def grab(self, region: Region) -> np.ndarray:
        """Pixels of a screen rectangle, as (height, width, 4) BGRA."""
        ...


class MssGrabber:
    """Screen capture with the `mss` library."""

    def __init__(self) -> None:
        import mss

        self._sct: Any = mss.mss()

    def monitors(self) -> list[Region]:
        return list(self._sct.monitors[1:])  # entry 0 is all monitors together

    def grab(self, region: Region) -> np.ndarray:
        shot = self._sct.grab(region)
        return np.frombuffer(shot.bgra, dtype=np.uint8).reshape(shot.height, shot.width, 4)

    def close(self) -> None:
        self._sct.close()


class ScreenReader:
    def __init__(self, grabber: Grabber, log: Callable[[str], None] = print,
                 clock: Callable[[], float] = time.monotonic) -> None:
        self.grabber = grabber
        self.log = log
        self.clock = clock
        self.geometry: Geometry | None = None  # last known place, in screen coordinates
        self.locked = False                    # is the beacon being read there right now?
        self._misses = 0
        self._next_corner_scan = 0.0
        self._next_full_scan = 0.0

    def read(self) -> BeaconMessage | None:
        """The beacon's current message, or None while it is out of sight."""
        if self.geometry is not None:
            message = self._read_known(self.geometry)
            if message is not None:
                if not self.locked:
                    self._lock(self.geometry)
                self._misses = 0
                return message
            if self.locked:
                self._misses += 1
                if self._misses < MISSES_BEFORE_LOST:
                    return None
                self.locked = False
                self.log("Balise hors de vue (lecteur arrêté, écran de chargement ou jeu masqué). En attente...")
        return self._search()

    def _lock(self, geometry: Geometry) -> None:
        self.geometry = geometry
        self.locked = True
        self._misses = 0
        self.log(f"Balise trouvée en ({geometry.x}, {geometry.y}), cellules de {geometry.cell} px.")

    def _grab(self, region: Region) -> np.ndarray | None:
        try:
            return self.grabber.grab(region)
        except Exception:  # a monitor was unplugged, the desktop is locked...
            return None

    def _read_known(self, geometry: Geometry) -> BeaconMessage | None:
        frame = self._grab({"left": geometry.x, "top": geometry.y,
                            "width": geometry.width, "height": geometry.height})
        if frame is None:
            return None
        return read_message(frame, Geometry(0, 0, geometry.cell))

    def _search_region(self, region: Region) -> BeaconMessage | None:
        frame = self._grab(region)
        if frame is None:
            return None
        found = find_beacon(frame)
        if found is None:
            return None
        geometry, message = found
        self._lock(Geometry(region["left"] + geometry.x, region["top"] + geometry.y, geometry.cell))
        return message

    def _search(self) -> BeaconMessage | None:
        now = self.clock()
        if now >= self._next_corner_scan:
            self._next_corner_scan = now + CORNER_SCAN_EVERY
            for monitor in self.grabber.monitors():
                width = min(CORNER_SIZE[0], monitor["width"])
                height = min(CORNER_SIZE[1], monitor["height"])
                for left in (monitor["left"], monitor["left"] + monitor["width"] - width):
                    for top in (monitor["top"], monitor["top"] + monitor["height"] - height):
                        message = self._search_region({"left": left, "top": top, "width": width, "height": height})
                        if message is not None:
                            return message
        if now >= self._next_full_scan:
            self._next_full_scan = now + FULL_SCAN_EVERY
            for monitor in self.grabber.monitors():
                message = self._search_region(dict(monitor))
                if message is not None:
                    return message
        return None
