"""Finding and reading the beacon in screen captures."""

import numpy as np
import pytest

from fmp_companion import protocol
from fmp_companion.locator import Geometry, find_beacon, read_cells, read_message
from fmp_companion.protocol import BeaconMessage, Command

from screen import draw_beacon, draw_cells, flat, noise

MESSAGE = BeaconMessage(active=True, playing=True, platform=1, volume=65, nonce=42, seq=7, cmd=Command.NEXT)


@pytest.mark.parametrize("cell", range(2, 13))
def test_found_at_every_cell_size(cell):
    frame = noise(300, 900, seed=cell)
    draw_beacon(frame, MESSAGE, x=123, y=77, cell=cell)
    assert find_beacon(frame) == (Geometry(123, 77, cell), MESSAGE)


@pytest.mark.parametrize("corner", ["topleft", "topright", "bottomleft", "bottomright"])
def test_found_in_every_corner(corner):
    height, width, cell = 400, 1000, 4
    x = 0 if "left" in corner else width - cell * protocol.CELL_COUNT
    y = 0 if "top" in corner else height - cell
    frame = noise(height, width, seed=5)
    draw_beacon(frame, MESSAGE, x, y, cell)
    assert find_beacon(frame) == (Geometry(x, y, cell), MESSAGE)


def test_found_on_a_dark_scene_and_on_a_white_one():
    for colour in [(0, 0, 0), (255, 255, 255), (20, 30, 200), (240, 240, 240)]:
        frame = flat(200, 600, colour)
        draw_beacon(frame, MESSAGE, 40, 60, 4)
        assert find_beacon(frame) == (Geometry(40, 60, 4), MESSAGE), colour


def test_every_message_field_survives():
    rng = np.random.default_rng(3)
    for _ in range(150):
        message = BeaconMessage(
            active=bool(rng.integers(2)), playing=bool(rng.integers(2)), platform=int(rng.integers(5)),
            volume=None if rng.integers(4) == 0 else int(rng.integers(101)),
            nonce=int(rng.integers(64)), seq=int(rng.integers(64)), cmd=int(rng.integers(5)),
        )
        frame = flat(40, 400, (15, 15, 15))
        draw_beacon(frame, message, 10, 10, 4)
        assert find_beacon(frame) == (Geometry(10, 10, 4), message)


def test_survives_brightness_contrast_and_gamma():
    base = flat(120, 500, (30, 30, 30))
    draw_beacon(base, MESSAGE, 8, 8, 4)
    rgb = base[:, :, :3].astype(np.float64)

    dimmed = base.copy()
    dimmed[:, :, :3] = (rgb * 0.7).astype(np.uint8)            # white becomes 178
    washed = base.copy()
    washed[:, :, :3] = (40 + rgb * 0.75).astype(np.uint8)      # black 40, white 231
    gamma = base.copy()
    gamma[:, :, :3] = (255 * (rgb / 255) ** 2.2).astype(np.uint8)

    for frame in (dimmed, washed, gamma):
        assert find_beacon(frame) == (Geometry(8, 8, 4), MESSAGE)


def test_read_uses_the_beacons_own_white_and_black():
    """A capture too dark for the search can still be read where the beacon is known to be."""
    frame = flat(20, 200, (0, 0, 0))
    draw_beacon(frame, MESSAGE, 0, 0, 4)
    frame[:, :, :3] = (frame[:, :, :3].astype(np.float64) * 0.4).astype(np.uint8)  # white is 102
    assert find_beacon(frame) is None
    assert read_message(frame, Geometry(0, 0, 4)) == MESSAGE


def test_nothing_found_without_a_beacon():
    assert find_beacon(noise(1080, 1920, seed=11)) is None
    assert find_beacon(flat(300, 300, (0, 0, 0))) is None
    assert find_beacon(flat(300, 300, (255, 255, 255))) is None


def test_sync_pattern_alone_is_not_a_beacon():
    frame = flat(100, 600, (60, 60, 60))
    cells = list(protocol.SYNC) + [3] * 16  # right start, garbage after it
    draw_cells(frame, cells, 50, 20, 4)
    assert find_beacon(frame) is None


def test_decoy_before_the_real_beacon():
    frame = flat(200, 800, (60, 60, 60))
    draw_cells(frame, list(protocol.SYNC) + [5] * 16, 20, 10, 4)
    draw_beacon(frame, MESSAGE, 300, 120, 6)
    assert find_beacon(frame) == (Geometry(300, 120, 6), MESSAGE)


def test_white_window_border_on_the_left():
    """In windowed mode the pixels left of the beacon belong to the window frame."""
    frame = flat(100, 600, (255, 255, 255))
    frame[:, 200:] = (10, 10, 10, 255)
    draw_beacon(frame, MESSAGE, 200, 30, 4)
    assert find_beacon(frame) == (Geometry(200, 30, 4), MESSAGE)


def test_covered_beacon_is_not_read():
    frame = flat(40, 400, (15, 15, 15))
    draw_beacon(frame, MESSAGE, 10, 10, 4)
    frame[8:20, 60:80] = (200, 200, 200, 255)  # a tooltip over a few cells
    assert find_beacon(frame) is None
    assert read_message(frame, Geometry(10, 10, 4)) is None


def test_read_cells_outside_the_capture():
    frame = flat(10, 50)
    assert read_cells(frame, Geometry(0, 0, 4)) is None      # strip wider than the capture
    assert read_cells(frame, Geometry(-4, 0, 2)) is None
    assert read_cells(frame, Geometry(0, 9, 2)) is None       # sample row below the capture


def test_read_cells_needs_contrast():
    assert read_cells(flat(8, 200, (128, 128, 128)), Geometry(0, 0, 4)) is None
