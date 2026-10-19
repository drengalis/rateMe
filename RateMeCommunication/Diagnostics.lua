local _, Communication = ...
local A = Communication.API

-- Translate packet metadata into readable local activity messages. Do not
-- display raw packet data: even malformed packets may contain private reviews.
local PACKET_NAMES = {
    H = "peer discovery greeting", A = "peer discovery reply",
    P = "peer introduction", K = "supported message format announcement",
    Q = "rating lookup request", R = "rating reply",
    ["C?"] = "written review request", C = "written review",
}
local CHANNEL_NAMES = {
    WHISPER = "direct message", PARTY = "party", RAID = "raid",
    GUILD = "guild", INSTANCE_CHAT = "instance group",
}
function A:DebugPacket(direction, packet, channel, peer)
    if not self.db or not self.db.settings or not self.db.settings.debug then return end
    local tag = type(packet) == "string" and packet:match("^([^|]+)|") or nil
    local kind = PACKET_NAMES[tag]
    if tag == "X" then
        local version = packet:match("^X|(%d+)|")
        kind = version and ("new-format addon message (format " .. version .. "; contents hidden)")
            or "new-format addon message (contents hidden)"
    end
    kind = kind or "unrecognized addon message"
    local name = type(peer) == "string" and peer:gsub("[|%c]", "") or ""
    if name == "" then name = "other players" end
    name = self:DisplayName(name)
    local route = CHANNEL_NAMES[channel] or "addon channel"
    local context
    if channel == "WHISPER" then
        context = (direction == "RX" or direction == "IGNORE/invalid-or-unsupported")
            and (" from " .. name) or (" to " .. name)
        context = context .. " (direct message)"
    else
        context = " in " .. route
        if direction == "RX" or direction == "IGNORE/invalid-or-unsupported" then
            context = context .. " from " .. name
        end
    end
    local bytes = type(packet) == "string" and #packet or 0
    local message
    if direction == "TX" then
        message = "Sent a " .. kind .. context .. " (" .. bytes .. " bytes)."
    elseif direction == "RX" then
        message = "Received a " .. kind .. context .. " (" .. bytes .. " bytes)."
    elseif direction == "DROP/queue" then
        message = "Could not queue a " .. kind .. context .. ": the outgoing message queue is full."
    elseif direction == "RETRY/throttled" then
        message = "The game is limiting addon messages. Will retry sending a " .. kind .. context .. "."
    elseif direction == "DROP/throttled" then
        message = "Stopped trying to send a " .. kind .. context .. ": the game kept limiting messages."
    elseif direction == "DROP/error" then
        message = "Could not send a " .. kind .. context .. ": the game's addon messaging API returned an error."
    elseif direction == "DROP/rejected" then
        message = "The game rejected a " .. kind .. context .. "."
    elseif direction == "IGNORE/invalid-or-unsupported" then
        message = "Ignored an addon message" .. context .. ": its format was invalid or unsupported."
    end
    if message then self:Debug(message) end
end

