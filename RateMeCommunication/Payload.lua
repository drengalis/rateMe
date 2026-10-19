-- Versioned RATEME payload processing. Network.lua owns transport, discovery,
-- routing, rate limits, and application state; this class owns wire formats.
-- v1 messages are immutable. An X|version|body packet is allowed only after a
-- confirmed peer advertises that version with K|1|comma-separated-versions.
local _, Communication = ...
local A = Communication.API

local Payload = {}
Payload.__index = Payload
local MAX_PACKET_BYTES = 255
local MAX_CODEC_VERSION = 16

local function fields(value, limit)
    local out, start = {}, 1
    for _ = 1, limit - 1 do
        local at = value:find("|", start, true)
        if not at then break end
        out[#out + 1] = value:sub(start, at - 1)
        start = at + 1
    end
    out[#out + 1] = value:sub(start)
    return out
end

function Payload.new(owner)
    local self = setmetatable({owner = owner, codecs = owner.wireCodecs or {}}, Payload)
    owner.wireCodecs = self.codecs -- preserve the existing registration interface
    self:ResetSession()
    return self
end

function Payload:ResetSession()
    self.peerCapabilities, self.advertised = {}, {}
    self.owner.wirePeerCapabilities = self.peerCapabilities
    self.owner.wireAdvertised = self.advertised
end

function Payload:ForgetPeer(peer)
    local key = self.owner:Key(peer)
    if key then self.peerCapabilities[key] = nil end
end

function Payload:RegisterCodec(version, encode, decode)
    if type(version) ~= "number" or version ~= math.floor(version)
        or version < 2 or version > MAX_CODEC_VERSION
        or type(encode) ~= "function" or type(decode) ~= "function"
        or self.codecs[version] then return false end
    self.codecs[version] = {encode = encode, decode = decode}
    return true
end

function Payload:SupportedVersions()
    local versions = {1}
    for version in pairs(self.codecs) do versions[#versions + 1] = version end
    table.sort(versions)
    return versions
end

function Payload:SendCapabilities(peer)
    local owner = self.owner
    local key = owner:Key(peer)
    if not key or not owner.db or not owner.data.peers[key] then return false end
    if self.advertised[key] and owner:Now() - self.advertised[key] < 120 then return false end
    local versions = self:SupportedVersions()
    if #versions == 1 then return false end -- v1-only clients send no new packets
    if not owner:QueueSend("K|1|" .. table.concat(versions, ","), "WHISPER", peer) then return false end
    self.advertised[key] = owner:Now()
    return true
end

function Payload:HandleCapabilities(message, sender)
    local owner = self.owner
    local key = owner:Key(sender)
    if not key or not owner.db or not owner.data.peers[key] then return end
    local marker, list = message:match("^K|([^|]+)|([%d,]+)$")
    if marker ~= "1" or not list or #list > 48 then return end
    local advertised, count = {}, 0
    for item in list:gmatch("[^,]+") do
        local version = tonumber(item)
        if not version or version ~= math.floor(version) or version < 1
            or version > MAX_CODEC_VERSION or advertised[version] then return end
        advertised[version] = true
        count = count + 1
        if count > MAX_CODEC_VERSION then return end
    end
    if count == 0 or not advertised[1] or list:sub(1, 1) == ","
        or list:sub(-1) == "," or list:find(",,", 1, true) then return end
    self.peerCapabilities[key] = advertised
    return true
end

function Payload:VersionForPeer(peer)
    local caps = self.peerCapabilities[self.owner:Key(peer)]
    if not caps then return 1 end
    local selected = 1
    for version in pairs(self.codecs) do
        if caps[version] and version > selected then selected = version end
    end
    return selected
end

function Payload:Legacy(tag, values)
    local parts = {tag}
    for i = 1, #values do parts[#parts + 1] = tostring(values[i]) end
    return table.concat(parts, "|")
end

-- Discovery and introductions always use the original format, even between
-- upgraded peers. v1 clients understand these packets and ignore K/X safely.
function Payload:Hello(protocol) return self:Legacy("H", {protocol}) end
function Payload:Ack(protocol) return self:Legacy("A", {protocol}) end
function Payload:Introductions(names) return self:Legacy("P", {table.concat(names, ",")}) end
function Payload:IntroductionNames(args)
    if not args or #args ~= 2 or #args[2] > 180 then return nil end
    local names = {}
    for peer in args[2]:gmatch("[^,]+") do names[#names + 1] = peer end
    return names
end

function Payload:Encode(tag, values, peer)
    local legacy = self:Legacy(tag, values)
    local version = peer and self:VersionForPeer(peer) or 1
    if version > 1 then
        local codec = self.codecs[version]
        local ok, body = pcall(codec.encode, tag, values)
        if ok and type(body) == "string" and #body > 0 then
            local packet = "X|" .. version .. "|" .. body
            if #packet <= MAX_PACKET_BYTES then return packet end
        end
        -- No speculative downgrade in the peer directory: only this packet
        -- falls back to the known-compatible v1 representation.
    end
    return legacy
end

function Payload:Decode(message, sender)
    if type(message) ~= "string" or #message == 0 or #message > MAX_PACKET_BYTES then return nil end
    local tag, canonical
    if message:sub(1, 2) ~= "X|" then
        tag, canonical = message:match("^([^|]+)"), message
    else
        local number, body = message:match("^X|(%d+)|(.+)$")
        local version = tonumber(number)
        if not version or version < 2 or version > MAX_CODEC_VERSION
            or tostring(version) ~= number then return nil end
        local owner = self.owner
        local key = owner:Key(sender)
        local caps = key and self.peerCapabilities[key]
        local codec = self.codecs[version]
        if not codec or not caps or not caps[version] or not owner.db
            or not owner.data.peers[key] then return nil end
        local ok, decodedTag, decodedLegacy = pcall(codec.decode, body)
        if not ok or (decodedTag ~= "Q" and decodedTag ~= "R"
            and decodedTag ~= "C?" and decodedTag ~= "C")
            or type(decodedLegacy) ~= "string"
            or decodedLegacy:match("^([^|]+)") ~= decodedTag
            or #decodedLegacy > MAX_PACKET_BYTES then return nil end
        tag, canonical = decodedTag, decodedLegacy
    end
    local argCount = ({H = 2, A = 2, P = 2, Q = 5, R = 7, B = 11, T = 6})[tag]
    return tag, canonical, argCount and fields(canonical, argCount) or nil
end

function Payload:ValidId(id)
    return type(id) == "string" and #id >= 2 and #id <= 25
        and id:match("^[%w%-]+$") ~= nil
end
function Payload:ValidGuid(guid)
    return type(guid) == "string" and #guid <= 64
        and guid:match("^Player%-%x+%-%x+$") ~= nil
end

-- The parser checks the legacy field shape and primitives. The Network
-- handlers additionally check identity, pending requests, and rate limits.
function Payload:QueryFields(args, maxHops)
    if not args or #args ~= 5 then return end
    local id, guid, origin, hops = args[2], args[3], self.owner:CleanName(args[4]), tonumber(args[5])
    if not self:ValidId(id) or not self:ValidGuid(guid) or not origin or not hops
        or hops ~= math.floor(hops) or hops < 0 or hops > maxHops then return end
    return id, guid, origin, hops
end
function Payload:RatingFields(args)
    if not args or #args ~= 7 then return end
    local id, guid, score, revision, timestamp, hasComment = args[2], args[3],
        tonumber(args[4]), tonumber(args[5]), tonumber(args[6]), tonumber(args[7])
    if not score or score ~= math.floor(score) or score < 0 or score > 5
        or not revision or revision ~= math.floor(revision) or revision < 1 or revision > 100000000
        or not timestamp or timestamp < 0 or timestamp > 5000000000
        or (hasComment ~= 0 and hasComment ~= 1) then return end
    return id, guid, score, revision, timestamp, hasComment
end
A.Payload = Payload
-- Facade preserved for existing addon callers and tests; implementations live
-- in Payload, not Network. New wire formats register exclusively here.
function A:RegisterWireCodec(version, encode, decode) return self.payload:RegisterCodec(version, encode, decode) end
function A:SupportedWireVersions() return self.payload:SupportedVersions() end
function A:SendCapabilities(peer) return self.payload:SendCapabilities(peer) end
function A:HandleCapabilities(message, sender) return self.payload:HandleCapabilities(message, sender) end
function A:WireVersionForPeer(peer) return self.payload:VersionForPeer(peer) end
function A:EncodePacket(tag, values, peer) return self.payload:Encode(tag, values, peer) end
function A:DecodePacket(message, sender) return self.payload:Decode(message, sender) end


-- B|1|reviewer|targetGUID|targetName|faction|class|score|revision|UTC|hasComment
-- No written review text travels in broadcast traffic.
function Payload:RatingBroadcast(target, record)
    return self:Legacy("B", {"1", self.owner.myName, target.guid, target.name,
        target.faction, target.class or "", record.removed and 0 or record.score,
        record.rev, record.date, 0})
end

function Payload:BroadcastFields(args)
    if not args or #args ~= 11 or args[2] ~= "1" then return end
    local reviewer, name = self.owner:CleanName(args[3]), self.owner:CleanName(args[5])
    local guid, faction, class = args[4], args[6], args[7]
    if not reviewer or not name or not self:ValidGuid(guid)
        or (faction ~= "Alliance" and faction ~= "Horde")
        or #class > 24 or class:find("[^A-Z_]") then return end
    local _, _, score, rev, stamp, hasComment = self:RatingFields(
        {"R", "broadcast", guid, args[8], args[9], args[10], args[11]})
    if not score then return end
    return {guid=guid, name=name, faction=faction, class=class}, reviewer,
        {score=score, rev=rev, date=stamp}
end


-- Additive tag packet. Numeric R/B messages retain their exact legacy shape.
-- Three permanent IDs occupy at most THREE ASCII BYTES in this packet and DB.
function Payload:ReviewTags(request, guid, revision, tags)
    return self:Legacy("T", {"1",request or "-",guid,revision,self.owner:EncodeReviewTags(tags) or ""})
end
function Payload:ReviewTagFields(args)
    if not args or #args~=6 or args[2]~="1" then return end
    local request,guid,rev,tags=args[3],args[4],tonumber(args[5]),args[6]
    if (request~="-" and not self:ValidId(request)) or not self:ValidGuid(guid)
        or not rev or rev~=math.floor(rev) or rev<1 or rev>100000000 then return end
    local encoded=self.owner:EncodeReviewTags(tags)
    if not encoded then return end
    return request,guid,rev,encoded
end
