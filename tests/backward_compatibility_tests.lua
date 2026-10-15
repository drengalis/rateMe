-- Run from repository root: lua tests/backward_compatibility_tests.lua
-- Compatibility contract: a v1 client and an upgraded client interoperate.
local A = {
    myName = "New-Realm", protocol = 1,
    db = { peers = { ["old-realm"] = { seen = 100 }, ["newpeer-realm"] = { seen = 100 } } },
    wireCodecs = {}, outbox = {}, nextSend = 0,
}
function A:Key(name) return type(name) == "string" and name:lower() or nil end
function A:CleanName(name) return name end
function A:Now() return 100 end
function A:Stamp() return 100 end
function A:Log() end
function A:AllowInbound() return true end
local sends = {}
assert(loadfile("RateMe/Network.lua"))("RateMe", A)
function A:QueueSend(packet, channel, to, logged)
    sends[#sends + 1] = { packet = packet, channel = channel, to = to, logged = logged }
    return true
end

-- Legacy clients do not advertise newer codecs and must always receive v1.
assert(A:EncodePacket("Q", {"ab12", "Player-1-2", "New-Realm", 2}, "Old-Realm")
    == "Q|ab12|Player-1-2|New-Realm|2")
assert(A:EncodePacket("R", {"ab12", "Player-1-2", 4, 1, 1234, 0}, "Old-Realm")
    == "R|ab12|Player-1-2|4|1|1234|0")
assert(A:DecodePacket("R|ab12|Player-1-2|4|1|1234|0", "Old-Realm") == "R")
assert(not A:SendCapabilities("Old-Realm")) -- no changed wire format registered yet

local function encode2(tag, values) return tag .. "~" .. table.concat(values, "~") end
local function decode2(body)
    local parts = {}
    for item in body:gmatch("[^~]+") do parts[#parts + 1] = item end
    local tag = table.remove(parts, 1)
    return tag, tag .. "|" .. table.concat(parts, "|")
end
assert(A:RegisterWireCodec(2, encode2, decode2))
assert(not A:RegisterWireCodec(2, encode2, decode2)) -- immutable registration
assert(A:SendCapabilities("Newpeer-Realm"))
assert(sends[#sends].packet == "K|1|1,2" and sends[#sends].channel == "WHISPER")
assert(A:WireVersionForPeer("Old-Realm") == 1)
assert(A:EncodePacket("Q", {"ab12", "Player-1-2", "New-Realm", 2}, "Old-Realm")
    == "Q|ab12|Player-1-2|New-Realm|2")
assert(not A:HandleCapabilities("K|1|2", "Newpeer-Realm")) -- must include v1
assert(not A:HandleCapabilities("K|1|1,2,2", "Newpeer-Realm"))
assert(A:HandleCapabilities("K|1|1,2", "Newpeer-Realm"))
assert(A:WireVersionForPeer("Newpeer-Realm") == 2)
local extended = A:EncodePacket("R", {"ab12", "Player-1-2", 4, 1, 1234, 0}, "Newpeer-Realm")
assert(extended:sub(1, 4) == "X|2|")
local tag, legacy = A:DecodePacket(extended, "Newpeer-Realm")
assert(tag == "R" and legacy == "R|ab12|Player-1-2|4|1|1234|0")
assert(A:DecodePacket(extended, "Old-Realm") == nil)
assert(A:DecodePacket("X|3|R~ab12", "Newpeer-Realm") == nil)

-- The upgraded client must receive ordinary v1 queries and responses unchanged.
local observed = {}
function A:HandleQuery(parts, sender)
    observed.query = {parts = parts, sender = sender}
    self:QueueSend(self:EncodePacket("R", {parts[2], parts[3], 5, 1, 1234, 0}, sender), "WHISPER", sender)
end
function A:HandleRating(parts, sender) observed.response = {parts = parts, sender = sender} end
A:OnMessage("RATEME", "Q|ab12|Player-1-2|Old-Realm|2", "WHISPER", "Old-Realm", false)
assert(observed.query and observed.query.parts[2] == "ab12" and observed.query.sender == "Old-Realm")
assert(sends[#sends].packet == "R|ab12|Player-1-2|5|1|1234|0")
A:OnMessage("RATEME", "R|ab12|Player-1-2|4|1|1234|0", "WHISPER", "Old-Realm", false)
assert(observed.response and observed.response.parts[4] == "4")

-- Settings are independently versioned, copied transactionally and keep unknown keys.
assert(loadfile("RateMe/Storage.lua"))("RateMe", A)
local saved = { settingsSchema = 1, settings = { oldValue = "original", unknownKey = 8 } }
A.SETTINGS_SCHEMA_VERSION = 2
assert(A:RegisterSettingsMigration(2, function(settings)
    settings.newFlag = true
    settings.oldValue = "migrated"
end))
assert(not A:RegisterSettingsMigration(2, function() end))
local original = saved.settings
assert(A:MigrateSettings(saved))
assert(saved.settings ~= original and original.oldValue == "original")
assert(saved.settingsSchema == 2 and saved.settings.newFlag == true)
assert(saved.settings.unknownKey == 8 and saved.settings.oldValue == "migrated")
A.SETTINGS_SCHEMA_VERSION = 3
local snapshot = saved.settings
local ok, why = A:MigrateSettings(saved)
assert(not ok and why == "missing migration 3")
assert(saved.settings == snapshot and saved.settingsSchema == 2)
assert(A:RegisterSettingsMigration(3, function(settings)
    settings.unknownKey = 0
    error("simulated failed migration")
end))
ok, why = A:MigrateSettings(saved)
assert(not ok and why == "migration failed 3")
assert(saved.settings == snapshot and saved.settings.unknownKey == 8)
local future = { settingsSchema = 9, settings = { futureKey = "preserve" } }
ok, why = A:MigrateSettings(future)
assert(not ok and why == "future")
assert(future.settingsSchema == 9 and future.settings.futureKey == "preserve")
print("Backward-compatibility tests passed")
