-- Rate Me! for WoW Forever (Interface 16001, Lua 5.1)
local addonName, A = ...
A.name = addonName
A.title = "Rate Me!"
A.version = "1"
A.protocol = "1"
A.prefix = "RATEME"
-- Bundled textures avoid missing Unicode star glyphs in WoW UI fonts.
A.STAR_FULL_TEXTURE = "Interface\\AddOns\\RateMe\\Media\\StarFull.tga"
A.STAR_EMPTY_TEXTURE = "Interface\\AddOns\\RateMe\\Media\\StarEmpty.tga"
A.STAR_HALF_TEXTURE = "Interface\\AddOns\\RateMe\\Media\\StarHalf.tga"

-- Use real icons in all visible rating displays, never unsupported Unicode stars.
-- Averages round to the nearest half star; exact stored scores remain unchanged
-- for sorting, alerts, comparisons, and calculations.
function A:StarMarkup(score, size)
    size = tonumber(size) or 13
    size = math.max(8, math.min(32, math.floor(size)))
    local value = math.max(0, math.min(5, tonumber(score) or 0))
    local roundedHalves = math.floor(value * 2 + 0.5)
    local icons = {}
    for n = 1, 5 do
        local level = roundedHalves - (n - 1) * 2
        local path = level >= 2 and self.STAR_FULL_TEXTURE
            or (level == 1 and self.STAR_HALF_TEXTURE or self.STAR_EMPTY_TEXTURE)
        icons[n] = "|T" .. path .. ":" .. size .. ":" .. size .. ":0:0|t"
    end
    return table.concat(icons, "")
end
A.MAX_PENDING = 5
A.QUERY_SECONDS = 15
A.myName = nil
A.myGuid = nil
A.myFaction = nil

-- Monotonic/session time for deadlines. Never persist or display this value.
function A:Now()
    return GetTime()
end
-- Persist and exchange UTC-based Unix epoch seconds (no timezone offset).
-- GetServerTime() is already an epoch timestamp, not a server-local clock
-- string; time() is also epoch seconds on clients without that API.
function A:Stamp()
    if GetServerTime then return GetServerTime() end
    return time()
end
function A:Log(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffc756Rate Me!|r " .. tostring(msg))
    end
end
function A:Debug(msg)
    if self.db and self.db.settings.debug then self:Log("[Activity] " .. tostring(msg)) end
end

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
    if not self.db or not self.db.settings.debug then return end
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

function A:CleanName(name)
    if type(name) ~= "string" or #name < 2 or #name > 80 then return nil end
    if name:find("[%s|%c]") then return nil end
    if not name:find("%-") then
        local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
        if not realm or realm == "" then return nil end
        name = name .. "-" .. realm:gsub("%s", "")
    end
    return name
end
-- Presentation only: WoW network identities and SavedVariables keep Name-Realm.
-- Display the hyphen as a space in Rate Me! windows and notifications.
function A:DisplayName(name)
    if type(name) ~= "string" then return "Unknown" end
    return (name:gsub("%-", " "))
end

function A:Key(name)
    local clean = self:CleanName(name)
    return clean and clean:lower() or nil
end
function A:OwnIdentity()
    local name, realm
    if UnitFullName then name, realm = UnitFullName("player") end
    if not name then name = UnitName("player") end
    if not realm or realm == "" then
        realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
    end
    self.myName = self:CleanName(name .. "-" .. (realm or ""):gsub("%s", ""))
    self.myGuid = UnitGUID("player")
    self.myFaction = UnitFactionGroup("player")
    return self.myName ~= nil and self.myGuid ~= nil
end

function A:UnitEligible(unit)
    if type(unit) ~= "string" or (issecretvalue and issecretvalue(unit)) then return false end
    local ok, eligible = pcall(function()
        if not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return false end
        if not UnitIsFriend("player", unit) then return false end
        local mine, theirs = UnitFactionGroup("player"), UnitFactionGroup(unit)
        return (mine == "Alliance" or mine == "Horde") and mine == theirs
    end)
    return ok and eligible == true
end

function A:CaptureUnit(unit)
    if not self:UnitEligible(unit) then return nil end
    -- UnitGUID/UnitClass can also be restricted on modern clients; never crash menus.
    local ok, target = pcall(function()
        local guid = UnitGUID(unit)
        if type(guid) ~= "string" or not guid:match("^Player%-") then return nil end
        local name, realm
        if UnitFullName then name, realm = UnitFullName(unit) end
        if not name then name = UnitName(unit) end
        if not name then return nil end
        if not realm or realm == "" then
            realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
        end
        local display = self:CleanName(name .. "-" .. (realm or ""):gsub("%s", ""))
        if not display then return nil end
        local _, class = UnitClass(unit)
        return { guid = guid, name = display, class = class, faction = self.myFaction or UnitFactionGroup("player") }
    end)
    return ok and target or nil
end

function A:ValidateStoredTarget(target)
    if type(target) ~= "table" or type(target.guid) ~= "string" or not target.guid:match("^Player%-") then return false end
    if not self:CleanName(target.name) then return false end
    return target.faction and target.faction == self.myFaction and target.guid ~= self.myGuid
end

function A:WhenReady()
    if self.ready then return end
    if not self:OwnIdentity() then return end
    self.ready = true
    self:InitializeStorage()
    self:InitializeNetwork()
    self:InitializeUI()
    self:InitializeAlerts()
    self:InitializeHighlights()
    self:InitializePartyReviews()
    self:InitializeIntegration()
    self:Log("loaded. Use /rateme to open or right-click a friendly player.")
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:SetScript("OnEvent", function(_, event, arg)
    if (event == "ADDON_LOADED" and arg == addonName and IsLoggedIn and IsLoggedIn())
        or event == "PLAYER_LOGIN" then
        A:WhenReady()
    end
end)
