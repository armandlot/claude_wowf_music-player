"""The beacon protocol: encoding, decoding, and agreement with the addon."""

import random
import shutil
import subprocess
from pathlib import Path

import pytest

from fmp_companion import protocol
from fmp_companion.protocol import BeaconMessage, Command

REPO = Path(__file__).resolve().parents[2]


def random_message(rng: random.Random) -> BeaconMessage:
    return BeaconMessage(
        active=rng.random() < 0.5,
        playing=rng.random() < 0.5,
        platform=rng.randrange(5),
        volume=None if rng.random() < 0.25 else rng.randrange(101),
        nonce=rng.randrange(64),
        seq=rng.randrange(64),
        cmd=rng.randrange(5),
    )


def test_round_trip():
    rng = random.Random(1)
    for _ in range(2000):
        message = random_message(rng)
        cells = protocol.encode(message)
        assert len(cells) == protocol.CELL_COUNT
        assert all(0 <= cell <= 7 for cell in cells)
        assert tuple(cells[:8]) == protocol.SYNC
        assert protocol.decode(cells) == message


def test_any_single_wrong_cell_is_rejected():
    rng = random.Random(2)
    for _ in range(200):
        cells = protocol.encode(random_message(rng))
        for index in range(protocol.CELL_COUNT):
            for wrong in range(8):
                if wrong == cells[index]:
                    continue
                damaged = list(cells)
                damaged[index] = wrong
                assert protocol.decode(damaged) is None


def test_rejects_wrong_length_and_wrong_sync():
    cells = protocol.encode(BeaconMessage(True, True, 1, 50, 3, 4, Command.NEXT))
    assert protocol.decode(cells[:-1]) is None
    assert protocol.decode(cells + [0]) is None
    assert protocol.decode([0] * protocol.CELL_COUNT) is None
    assert protocol.decode([7] * protocol.CELL_COUNT) is None


def test_rejects_other_protocol_versions(monkeypatch):
    message = BeaconMessage(True, False, 2, None, 9, 0, 0)
    monkeypatch.setattr(protocol, "VERSION", 2)
    cells = protocol.encode(message)  # a valid version-2 beacon
    monkeypatch.setattr(protocol, "VERSION", 1)
    assert protocol.decode(cells) is None


def test_rejects_impossible_volume():
    message = BeaconMessage(True, True, 0, 300, 0, 0, 0)  # valid checksum, absurd volume
    assert protocol.decode(protocol.encode(message)) is None


def test_platform_key():
    assert BeaconMessage(True, True, 0, None, 0, 0, 0).platform_key == "auto"
    assert BeaconMessage(True, True, 1, None, 0, 0, 0).platform_key == "spotify"
    assert BeaconMessage(True, True, 4, None, 0, 0, 0).platform_key == "youtube"
    assert BeaconMessage(True, True, 7, None, 0, 0, 0).platform_key == "auto"


@pytest.mark.skipif(shutil.which("lua5.1") is None, reason="lua5.1 is not installed")
def test_addon_and_companion_agree():
    """Cells produced by the addon's Protocol.lua decode to the same message here."""
    output = subprocess.run(
        ["lua5.1", "tests/lua/vectors.lua"], cwd=REPO, check=True, capture_output=True, text=True,
    ).stdout
    lines = output.strip().splitlines()
    assert len(lines) == 300
    volumes = set()
    for line in lines:
        fields, cells = line.split("|")
        active, playing, platform, volume, nonce, seq, cmd = (int(value) for value in fields.split())
        cells = [int(value) for value in cells.split()]
        expected = BeaconMessage(
            bool(active), bool(playing), platform, None if volume < 0 else volume, nonce, seq, cmd,
        )
        assert protocol.decode(cells) == expected
        assert protocol.encode(expected) == cells
        volumes.add(expected.volume)
    assert None in volumes and len(volumes) > 20  # the vectors cover both kinds of volume
