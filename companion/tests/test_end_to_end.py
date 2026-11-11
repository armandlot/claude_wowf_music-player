"""The whole chain, short of the real game and the real Windows.

The addon's actual Lua code plays a scripted session (tests/lua/scenario.lua)
and prints what its beacon shows at every screen capture. Here those cells are
painted on a fake screen, read back by the companion's screen reader, and
turned into actions on fake music apps.
"""

import asyncio
import shutil
import subprocess
from pathlib import Path

import pytest

from fmp_companion.capture import ScreenReader
from fmp_companion.config import Config
from fmp_companion.controller import Controller

from screen import FakeGrabber, draw_cells, flat
from test_controller import FakeBackend, FakeSession

REPO = Path(__file__).resolve().parents[2]


@pytest.mark.skipif(shutil.which("lua5.1") is None, reason="lua5.1 is not installed")
def test_a_session_played_in_the_addon_drives_the_music_apps():
    output = subprocess.run(
        ["lua5.1", "tests/lua/scenario.lua"], cwd=REPO, check=True, capture_output=True, text=True,
    ).stdout

    spotify, deezer = FakeSession("Spotify.exe"), FakeSession("Deezer.exe")
    backend = FakeBackend(spotify=spotify, deezer=deezer)
    screen = flat(1080, 1920)
    now = [0.0]
    logs: list[str] = []
    reader = ScreenReader(FakeGrabber(screen), log=logs.append, clock=lambda: now[0])
    controller = Controller(backend, Config(), log=logs.append, clock=lambda: now[0])

    history: list[tuple[str, str]] = []  # (step, action) in the order they happened
    seen = {"spotify": 0, "deezer": 0}

    async def play_back():
        for line in output.strip().splitlines():
            step, visible, cells = (part.strip() for part in line.split("|"))
            screen[:8, :200, :3] = 40
            if visible == "1":
                draw_cells(screen, [int(value) for value in cells.split()], 0, 0, 4)
            now[0] += 0.05
            await controller.handle(reader.read())
            await controller.tick()
            for name, session in (("spotify", spotify), ("deezer", deezer)):
                for call in session.calls[seen[name]:]:
                    history.append((step, f"{name}.{call}"))
                seen[name] = len(session.calls)

    asyncio.run(play_back())

    assert history == [
        ("play", "spotify.play"),
        ("skip-burst", "spotify.next"),
        ("skip-burst", "spotify.next"),
        ("skip-burst", "spotify.previous"),
        ("pause", "spotify.pause"),
        ("play-deezer", "deezer.play"),
        # "reload": Deezer is already playing, nothing to do
        ("stop", "deezer.pause"),
        ("play-again", "deezer.play"),
    ]
    assert backend.volumes[0] == ("Spotify.exe", 40)
    assert set(backend.volumes[1:]) == {("Deezer.exe", 40)}
    assert backend.launched == []
    assert any("hors de vue" in line for line in logs), "the beacon hid while idle"
    assert spotify.playing is False and deezer.playing is True
