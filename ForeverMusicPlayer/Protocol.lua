-- Protocol.lua
-- Turns the player's state into the row of coloured cells drawn by Beacon.lua.
-- This file is pure Lua (no game API), so it is tested outside the game, and
-- companion/fmp_companion/protocol.py is its mirror image on the PC side.
--
-- A cell carries 3 bits, one per colour channel: red = 4, green = 2, blue = 1.
-- The strip is 24 cells:
--
--   cells  1-8   sync pattern (every colour once, in a fixed order)
--   cell   9     protocol version                      3 bits
--   cell   10    flags: 4 = player on, 2 = playing     3 bits
--   cell   11    platform                              3 bits
--   cells 12-14  volume 0-100, 511 = not managed       9 bits
--   cells 15-16  nonce, new at every UI load           6 bits
--   cells 17-18  event counter                         6 bits
--   cells 19-20  last event (next, previous, ...)      6 bits
--   cells 21-24  CRC-12 of the 36 bits above          12 bits

local ADDON_NAME, ns = ...

local Protocol = {}
ns.Protocol = Protocol

Protocol.VERSION = 1
Protocol.SYNC = { 7, 0, 4, 2, 1, 6, 3, 5 } -- white black red green blue yellow cyan magenta
Protocol.CELL_COUNT = 24
Protocol.VOLUME_UNMANAGED = 511
Protocol.CMD = { NONE = 0, NEXT = 1, PREVIOUS = 2, SHUFFLE = 3, REPEAT = 4 }

local floor = math.floor

-- Appends `count` bits of `value` to `bits`, most significant bit first.
local function PushBits(bits, value, count)
    for i = count - 1, 0, -1 do
        bits[#bits + 1] = floor(value / 2 ^ i) % 2
    end
end

-- CRC-12, polynomial 0x80F, initial value 0xFFF, most significant bit first.
-- Works on an array of 0/1 so it needs no bit library.
local POLY = { 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1 }

function Protocol.Crc12(bits)
    local reg = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }
    for i = 1, #bits do
        local top = (reg[1] + bits[i]) % 2
        for j = 1, 11 do
            reg[j] = reg[j + 1]
        end
        reg[12] = 0
        if top == 1 then
            for j = 1, 12 do
                reg[j] = (reg[j] + POLY[j]) % 2
            end
        end
    end
    local value = 0
    for j = 1, 12 do
        value = value * 2 + reg[j]
    end
    return value
end

-- msg = { active, playing, platform, volume (0-100 or nil), nonce, seq, cmd }
-- Returns an array of CELL_COUNT numbers in 0..7.
function Protocol.Encode(msg)
    local bits = {}
    PushBits(bits, Protocol.VERSION, 3)
    PushBits(bits, (msg.active and 4 or 0) + (msg.playing and 2 or 0), 3)
    PushBits(bits, msg.platform or 0, 3)
    PushBits(bits, msg.volume or Protocol.VOLUME_UNMANAGED, 9)
    PushBits(bits, msg.nonce or 0, 6)
    PushBits(bits, msg.seq or 0, 6)
    PushBits(bits, msg.cmd or 0, 6)
    PushBits(bits, Protocol.Crc12(bits), 12)

    local cells = {}
    for i = 1, #Protocol.SYNC do
        cells[i] = Protocol.SYNC[i]
    end
    for i = 1, #bits, 3 do
        cells[#cells + 1] = bits[i] * 4 + bits[i + 1] * 2 + bits[i + 2]
    end
    return cells
end

-- Splits a cell value into its red, green and blue components (0 or 1 each).
function Protocol.CellColor(value)
    return floor(value / 4) % 2, floor(value / 2) % 2, value % 2
end
