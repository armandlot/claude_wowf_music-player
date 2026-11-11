"""Fake screens for the tests: draw a beacon the way the game would."""

from __future__ import annotations

import numpy as np

from fmp_companion import protocol
from fmp_companion.protocol import BeaconMessage


def noise(height: int, width: int, seed: int = 0) -> np.ndarray:
    """A screen full of random pixels (BGRA)."""
    rng = np.random.default_rng(seed)
    frame = rng.integers(0, 256, size=(height, width, 4), dtype=np.uint8)
    frame[:, :, 3] = 255
    return frame


def flat(height: int, width: int, colour=(40, 40, 40)) -> np.ndarray:
    frame = np.empty((height, width, 4), dtype=np.uint8)
    frame[:, :, :3] = colour
    frame[:, :, 3] = 255
    return frame


def draw_cells(frame: np.ndarray, cells: list[int], x: int, y: int, cell: int) -> None:
    for index, value in enumerate(cells):
        red, green, blue = (value >> 2) & 1, (value >> 1) & 1, value & 1
        frame[y:y + cell, x + index * cell:x + (index + 1) * cell, :3] = (blue * 255, green * 255, red * 255)


def draw_beacon(frame: np.ndarray, message: BeaconMessage, x: int, y: int, cell: int = 4) -> None:
    draw_cells(frame, protocol.encode(message), x, y, cell)


class FakeGrabber:
    """Monitors side by side, backed by one big array."""

    def __init__(self, screen: np.ndarray, monitors: list[dict[str, int]] | None = None) -> None:
        self.screen = screen
        height, width = screen.shape[:2]
        self._monitors = monitors or [{"left": 0, "top": 0, "width": width, "height": height}]
        self.grabs: list[tuple[int, int]] = []  # (width, height) of every capture

    def monitors(self) -> list[dict[str, int]]:
        return self._monitors

    def grab(self, region: dict[str, int]) -> np.ndarray:
        left, top, width, height = region["left"], region["top"], region["width"], region["height"]
        screen_height, screen_width = self.screen.shape[:2]
        if left < 0 or top < 0 or left + width > screen_width or top + height > screen_height:
            raise ValueError("capture outside the screen")
        self.grabs.append((width, height))
        return self.screen[top:top + height, left:left + width].copy()
