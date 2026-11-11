-- vectors.lua
-- Prints beacon messages and the cells the addon produces for them, so the
-- companion's tests can check both sides speak the same protocol:
--
--     lua5.1 tests/lua/vectors.lua
--
-- Each line: active playing platform volume nonce seq cmd | 24 cell values
-- (volume -1 means "not managed").

local ns = {}
assert(loadfile("ForeverMusicPlayer/Protocol.lua"))("ForeverMusicPlayer", ns)
local Protocol = ns.Protocol

-- Small fixed random generator: the same messages on every run.
local seed = 12345
local function random(limit)
    seed = (seed * 1103515245 + 12345) % 2147483648
    return math.floor(seed / 65536) % limit
end

for _ = 1, 300 do
    local message = {
        active = random(2) == 1,
        playing = random(2) == 1,
        platform = random(5),
        volume = random(101),
        nonce = random(64),
        seq = random(64),
        cmd = random(5),
    }
    if random(4) == 0 then
        message.volume = nil -- not managed
    end
    local cells = Protocol.Encode(message)
    io.write(
        message.active and 1 or 0, " ", message.playing and 1 or 0, " ", message.platform, " ",
        message.volume or -1, " ", message.nonce, " ", message.seq, " ", message.cmd,
        " | ", table.concat(cells, " "), "\n")
end
