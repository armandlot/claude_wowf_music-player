"""Finds and reads the pixel beacon in a screen capture.

A capture is a NumPy array of shape (height, width, 4) in BGRA order, which is
what the `mss` library returns. Nothing here knows about the game: the beacon
is recognised purely by its sync pattern and checksum, wherever it is on
screen and whatever its cell size.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from . import protocol

MIN_CELL = 2    # cell sizes accepted, in screen pixels
MAX_CELL = 16
MIN_CONTRAST = 60  # least white-to-black difference, per channel, to trust a read


@dataclass(frozen=True)
class Geometry:
    """Where the beacon is: top-left pixel of its first cell, and the cell size."""
    x: int
    y: int
    cell: int

    @property
    def width(self) -> int:
        return self.cell * protocol.CELL_COUNT

    @property
    def height(self) -> int:
        return self.cell


def classify(frame: np.ndarray, threshold: int = 128) -> np.ndarray:
    """The 3-bit colour code of every pixel (red = 4, green = 2, blue = 1)."""
    blue = frame[:, :, 0] > threshold
    green = frame[:, :, 1] > threshold
    red = frame[:, :, 2] > threshold
    return (red.astype(np.uint8) << 2) | (green.astype(np.uint8) << 1) | blue.astype(np.uint8)


def read_cells(frame: np.ndarray, geometry: Geometry) -> list[int] | None:
    """The colour codes of the 24 cells at `geometry`, or None if unreadable.

    Each cell is sampled at its centre. The first two cells of the sync
    pattern are white and black: they set the threshold between "channel on"
    and "channel off", so brightness, gamma or contrast settings do not matter.
    """
    height, width = frame.shape[:2]
    cell = geometry.cell
    row = geometry.y + cell // 2
    if geometry.x < 0 or geometry.y < 0 or row >= height or geometry.x + geometry.width > width:
        return None

    columns = geometry.x + cell // 2 + cell * np.arange(protocol.CELL_COUNT)
    samples = frame[row, columns, :3].astype(np.int16)  # one BGR pixel per cell

    white, black = samples[0], samples[1]
    if np.any(white - black < MIN_CONTRAST):
        return None
    on = samples > (white + black) // 2
    codes = on[:, 2] * 4 + on[:, 1] * 2 + on[:, 0]
    return [int(code) for code in codes]


def read_message(frame: np.ndarray, geometry: Geometry) -> protocol.BeaconMessage | None:
    cells = read_cells(frame, geometry)
    return protocol.decode(cells) if cells else None


def find_beacon(frame: np.ndarray) -> tuple[Geometry, protocol.BeaconMessage] | None:
    """Searches a whole capture for the beacon.

    The sync pattern starts white, black, red. Every place where a black run
    of 2 to 16 pixels sits between a white pixel and a red pixel is a
    candidate: the run length gives the cell size. Candidates must then show
    the rest of the sync pattern and decode with a valid checksum.
    """
    codes = classify(frame)
    height, width = codes.shape
    white, black, red = protocol.SYNC[0], protocol.SYNC[1], protocol.SYNC[2]

    # (row, column) of every red pixel whose left neighbour is black.
    rows, cols = np.nonzero((codes[:, 1:] == red) & (codes[:, :-1] == black))
    cols = cols + 1
    if rows.size == 0:
        return None

    black_run = np.ones(rows.size, dtype=bool)  # are the `cell` pixels to the left all black?
    for cell in range(1, MAX_CELL + 1):
        left = cols - cell
        inside = left >= 0
        black_run &= inside
        black_run[inside] &= codes[rows[inside], left[inside]] == black
        if cell < MIN_CELL:
            continue

        # The first cell starts `2 * cell` pixels left of the red one, and the
        # whole strip must fit in the capture.
        start = cols - 2 * cell
        fits = black_run & (start >= 0) & (start + cell * protocol.CELL_COUNT <= width)
        fits &= rows + cell // 2 < height
        if not fits.any():
            continue
        # The pixel just before the black run must be white, so that the run
        # is exactly one cell long.
        fits[fits] &= codes[rows[fits], cols[fits] - cell - 1] == white
        # Then every sync cell must show its colour at its centre.
        for index, expected in enumerate(protocol.SYNC):
            if not fits.any():
                break
            centre = start[fits] + cell * index + cell // 2
            fits[fits] &= codes[rows[fits], centre] == expected

        # Candidates come sorted by row, so the first hit on a strip is its top row.
        for i in np.flatnonzero(fits):
            geometry = Geometry(int(start[i]), int(rows[i]), cell)
            message = read_message(frame, geometry)
            if message:
                return geometry, message
    return None
