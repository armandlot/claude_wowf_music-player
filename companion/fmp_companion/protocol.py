"""The message carried by the pixel beacon.

Mirror image of ForeverMusicPlayer/Protocol.lua: the addon encodes the
player's state into 24 coloured cells, this module decodes them. A cell
carries 3 bits, one per colour channel: red = 4, green = 2, blue = 1.

    cells  1-8   sync pattern (every colour once, in a fixed order)
    cell   9     protocol version                      3 bits
    cell   10    flags: 4 = player on, 2 = playing     3 bits
    cell   11    platform                              3 bits
    cells 12-14  volume 0-100, 511 = not managed       9 bits
    cells 15-16  nonce, new at every UI load           6 bits
    cells 17-18  event counter                         6 bits
    cells 19-20  last event (next, previous, ...)      6 bits
    cells 21-24  CRC-12 of the 36 bits above          12 bits
"""

from __future__ import annotations

import enum
from collections.abc import Iterable, Sequence
from dataclasses import dataclass

VERSION = 1
SYNC = (7, 0, 4, 2, 1, 6, 3, 5)  # white black red green blue yellow cyan magenta
CELL_COUNT = 24
VOLUME_UNMANAGED = 511

# Platform numbers sent by the addon, in order.
PLATFORMS = ("auto", "spotify", "deezer", "apple", "youtube")


class Command(enum.IntEnum):
    NONE = 0
    NEXT = 1
    PREVIOUS = 2
    SHUFFLE = 3
    REPEAT = 4


@dataclass(frozen=True)
class BeaconMessage:
    active: bool          # the in-game player is on (playing or paused)
    playing: bool         # the player wants music playing
    platform: int         # index into PLATFORMS
    volume: int | None    # 0-100, or None when the game does not manage it
    nonce: int            # changes at every UI load
    seq: int              # goes up by one (mod 64) with each event
    cmd: int              # the event: a Command value

    @property
    def platform_key(self) -> str:
        if 0 <= self.platform < len(PLATFORMS):
            return PLATFORMS[self.platform]
        return PLATFORMS[0]


def crc12(bits: Iterable[int]) -> int:
    """CRC-12, polynomial 0x80F, initial value 0xFFF, most significant bit first."""
    reg = 0xFFF
    for bit in bits:
        top = ((reg >> 11) & 1) ^ bit
        reg = (reg << 1) & 0xFFF
        if top:
            reg ^= 0x80F
    return reg


def _push(bits: list[int], value: int, count: int) -> None:
    for shift in range(count - 1, -1, -1):
        bits.append((value >> shift) & 1)


def encode(message: BeaconMessage) -> list[int]:
    """Cells for a message. The addon does this in the game; here it serves tests."""
    bits: list[int] = []
    _push(bits, VERSION, 3)
    _push(bits, (4 if message.active else 0) | (2 if message.playing else 0), 3)
    _push(bits, message.platform, 3)
    _push(bits, VOLUME_UNMANAGED if message.volume is None else message.volume, 9)
    _push(bits, message.nonce, 6)
    _push(bits, message.seq, 6)
    _push(bits, message.cmd, 6)
    _push(bits, crc12(bits), 12)
    cells = list(SYNC)
    for i in range(0, len(bits), 3):
        cells.append(bits[i] << 2 | bits[i + 1] << 1 | bits[i + 2])
    return cells


def decode(cells: Sequence[int]) -> BeaconMessage | None:
    """The message in a row of cells, or None if this is not a valid beacon."""
    if len(cells) != CELL_COUNT or tuple(cells[: len(SYNC)]) != SYNC:
        return None

    bits: list[int] = []
    for cell in cells[len(SYNC):]:
        if not 0 <= cell <= 7:
            return None
        _push(bits, cell, 3)

    position = 0

    def take(count: int) -> int:
        nonlocal position
        value = 0
        for bit in bits[position:position + count]:
            value = value << 1 | bit
        position += count
        return value

    version = take(3)
    flags = take(3)
    platform = take(3)
    volume = take(9)
    nonce = take(6)
    seq = take(6)
    cmd = take(6)
    checksum = take(12)

    if checksum != crc12(bits[:36]) or version != VERSION:
        return None
    if volume > 100 and volume != VOLUME_UNMANAGED:
        return None

    return BeaconMessage(
        active=bool(flags & 4),
        playing=bool(flags & 2),
        platform=platform,
        volume=None if volume == VOLUME_UNMANAGED else volume,
        nonce=nonce,
        seq=seq,
        cmd=cmd,
    )
