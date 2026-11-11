"""Watching the screen: finding the beacon, following it, losing it, finding it again."""

from fmp_companion import protocol
from fmp_companion.capture import FULL_SCAN_EVERY, MISSES_BEFORE_LOST, ScreenReader
from fmp_companion.locator import Geometry
from fmp_companion.protocol import BeaconMessage, Command

from screen import FakeGrabber, draw_beacon, flat

PLAYING = BeaconMessage(active=True, playing=True, platform=1, volume=None, nonce=5, seq=0, cmd=Command.NONE)
PAUSED = BeaconMessage(active=True, playing=False, platform=1, volume=None, nonce=5, seq=0, cmd=Command.NONE)
STRIP = (4 * protocol.CELL_COUNT, 4)  # size of a capture of just the beacon


class Clock:
    def __init__(self):
        self.now = 100.0

    def __call__(self):
        return self.now


def make_reader(screen, monitors=None):
    grabber = FakeGrabber(screen, monitors)
    logs = []
    clock = Clock()
    return ScreenReader(grabber, log=logs.append, clock=clock), grabber, logs, clock


def erase(screen, x, y, cell=4):
    screen[y:y + cell, x:x + cell * protocol.CELL_COUNT, :3] = 40


def test_finds_a_fullscreen_beacon_then_reads_only_the_strip():
    screen = flat(1080, 1920)
    draw_beacon(screen, PLAYING, 0, 0)
    reader, grabber, logs, _ = make_reader(screen)

    assert reader.read() == PLAYING
    assert reader.locked
    assert reader.geometry == Geometry(0, 0, 4)
    assert (1920, 1080) not in grabber.grabs, "a corner capture is enough"
    assert any("Balise trouvée" in line for line in logs)

    grabber.grabs.clear()
    draw_beacon(screen, PAUSED, 0, 0)
    assert reader.read() == PAUSED
    assert grabber.grabs == [STRIP]


def test_finds_a_beacon_in_each_corner_of_a_second_monitor():
    monitors = [
        {"left": 0, "top": 0, "width": 1920, "height": 1080},
        {"left": 1920, "top": 0, "width": 1280, "height": 720},
    ]
    for x, y in [(1920, 0), (3200 - 96, 0), (1920, 720 - 4), (3200 - 96, 720 - 4)]:
        screen = flat(1080, 3200)
        draw_beacon(screen, PLAYING, x, y)
        reader, grabber, _, _ = make_reader(screen, monitors)
        assert reader.read() == PLAYING
        assert reader.geometry == Geometry(x, y, 4)
        assert all(width <= 640 for width, _ in grabber.grabs), "found without a full-screen capture"


def test_finds_a_windowed_game_with_a_full_search():
    screen = flat(1080, 1920)
    draw_beacon(screen, PLAYING, 700, 400)  # game window somewhere in the middle
    reader, grabber, _, _ = make_reader(screen)
    assert reader.read() == PLAYING
    assert reader.geometry == Geometry(700, 400, 4)
    assert (1920, 1080) in grabber.grabs


def test_waits_between_full_searches():
    screen = flat(1080, 1920)
    reader, grabber, _, clock = make_reader(screen)
    assert reader.read() is None
    assert grabber.grabs.count((1920, 1080)) == 1

    for _ in range(10):  # ten more looks within a second: no new search at all
        clock.now += 0.05
        assert reader.read() is None
    assert grabber.grabs.count((1920, 1080)) == 1

    clock.now += FULL_SCAN_EVERY
    draw_beacon(screen, PLAYING, 700, 400)
    assert reader.read() == PLAYING
    assert grabber.grabs.count((1920, 1080)) == 2


def test_a_brief_glitch_does_not_lose_the_beacon():
    screen = flat(1080, 1920)
    draw_beacon(screen, PLAYING, 0, 0)
    reader, grabber, logs, _ = make_reader(screen)
    assert reader.read() == PLAYING

    erase(screen, 0, 0)
    for _ in range(MISSES_BEFORE_LOST - 1):
        assert reader.read() is None
        assert reader.locked
    draw_beacon(screen, PLAYING, 0, 0)
    assert reader.read() == PLAYING
    assert not any("hors de vue" in line for line in logs)


def test_lost_beacon_is_found_again_at_the_same_place_without_a_search():
    screen = flat(1080, 1920)
    draw_beacon(screen, PLAYING, 700, 400)
    reader, grabber, logs, clock = make_reader(screen)
    assert reader.read() == PLAYING

    erase(screen, 700, 400)  # the player stops: the addon hides the beacon
    for _ in range(MISSES_BEFORE_LOST):
        clock.now += 0.05
        assert reader.read() is None
    assert not reader.locked
    assert any("hors de vue" in line for line in logs)

    clock.now += 0.05  # no search is due yet
    grabber.grabs.clear()
    draw_beacon(screen, PLAYING, 700, 400)
    assert reader.read() == PLAYING
    assert reader.locked
    assert grabber.grabs == [STRIP]


def test_follows_a_beacon_that_moved():
    screen = flat(1080, 1920)
    draw_beacon(screen, PLAYING, 0, 0)
    reader, _, _, clock = make_reader(screen)
    assert reader.read() == PLAYING

    erase(screen, 0, 0)  # the game window was moved
    draw_beacon(screen, PAUSED, 900, 300, cell=6)
    message = None
    for _ in range(MISSES_BEFORE_LOST + 2):
        clock.now += FULL_SCAN_EVERY
        message = reader.read()
        if message:
            break
    assert message == PAUSED
    assert reader.geometry == Geometry(900, 300, 6)


def test_capture_errors_are_not_fatal():
    screen = flat(200, 400)
    draw_beacon(screen, PLAYING, 0, 0)
    reader, grabber, _, _ = make_reader(screen)
    assert reader.read() == PLAYING

    def broken(region):
        raise OSError("desktop locked")

    grabber.grab = broken
    for _ in range(MISSES_BEFORE_LOST + 3):
        assert reader.read() is None
    assert not reader.locked
