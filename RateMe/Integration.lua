local _, A = ...

function A:RefreshTooltip(guid)
    local tooltip = GameTooltip
    if not tooltip or not tooltip:IsShown() or not tooltip.RefreshData then return end
    local unit
    if TooltipUtil and TooltipUtil.GetDisplayedUnit then
        local _, token = TooltipUtil.GetDisplayedUnit(tooltip)
        unit = token
    elseif tooltip.GetUnit then
        local _, token = tooltip:GetUnit()
        unit = token
    end
    local target = unit and self:CaptureUnit(unit)
    if target and target.guid == guid then
        pcall(function() tooltip:RefreshData() end)
    end
end

function A:AddTooltip(tooltip)
    if not tooltip or not tooltip.IsForbidden or tooltip:IsForbidden() then return end
    local unit
    if TooltipUtil and TooltipUtil.GetDisplayedUnit then
        local _, token = TooltipUtil.GetDisplayedUnit(tooltip)
        unit = token
    elseif tooltip.GetUnit then
        local _, token = tooltip:GetUnit()
        unit = token
    end
    local target = unit and self:CaptureUnit(unit)
    if not target then return end
    local summary = self:GetSummary(target.guid)
    tooltip:AddLine(" ")
    tooltip:AddLine("Rate Me!", 1, 0.72, 0.28)
    if summary and summary.count > 0 then
        local stars = self:StarMarkup(summary.average, 13)
        tooltip:AddDoubleLine("Community", string.format("%s  (%d ratings)", stars, summary.count),
            0.91, 0.91, 0.87, 1, 0.78, 0.30)
        if summary.peerCount and summary.peerCount>0 then
            tooltip:AddLine(tostring(summary.peerCount).." review(s) supplied by peers; authors unverified",1,0.75,0.3)
        end
        if not summary.fresh then tooltip:AddLine("Cached rating — checking online peers", 0.61, 0.65, 0.7) end
    else
        tooltip:AddLine("No community ratings available", 0.63, 0.68, 0.73)
    end
    local mine = self:GetOwnRating(target.guid)
    if mine and not mine.removed then
        tooltip:AddDoubleLine("Your rating", self:StarMarkup(mine.score, 13), 0.91, 0.91, 0.87, 1, 0.78, 0.30)
    end
    self:RequestLookup(target, 1)
end

local MENU_TAGS = {
    "MENU_UNIT_TARGET", "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_PARTY1",
    "MENU_UNIT_PARTY2", "MENU_UNIT_PARTY3", "MENU_UNIT_PARTY4", "MENU_UNIT_RAID",
    "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FOCUS", "MENU_UNIT_FRIEND", "MENU_UNIT_GUILD",
    "MENU_UNIT_GUILD_MEMBER", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
    "MENU_UNIT_CHAT_ROSTER", "MENU_UNIT_COMMUNITIES_WOW_MEMBER",
    "MENU_UNIT_RECENT_ALLY", "MENU_UNIT_RECENT_ALLY_OFFLINE", "MENU_UNIT_FRIEND_OFFLINE",
}

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2)
end

-- Midnight-era clients may hand back secret values that error on any string use.
local function plainString(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return type(v) == "string" and v ~= "" and v or nil
end

-- Name-only menus (chat names, friends, who, guild roster) carry no unit token,
-- so faction comes from race. Built from the client's own race data; races that
-- exist on both factions (Pandaren, Dracthyr, ...) map to false and are rejected.
local raceFaction
local function factionForRace(race)
    if not raceFaction then
        raceFaction = {}
        if C_CreatureInfo and C_CreatureInfo.GetRaceInfo and C_CreatureInfo.GetFactionInfo then
            for id = 1, 150 do
                local info = safeCall(C_CreatureInfo.GetRaceInfo, id)
                local faction = safeCall(C_CreatureInfo.GetFactionInfo, id)
                local file = info and info.clientFileString
                local tag = faction and faction.groupTag
                if type(file) == "string" and (tag == "Alliance" or tag == "Horde") then
                    if raceFaction[file] == nil then
                        raceFaction[file] = tag
                    elseif raceFaction[file] ~= tag then
                        raceFaction[file] = false
                    end
                end
            end
        end
    end
    return raceFaction[race] or nil
end

local function factionForRaceID(raceID)
    local faction = raceID and C_CreatureInfo and safeCall(C_CreatureInfo.GetFactionInfo, raceID)
    local tag = faction and faction.groupTag
    return (tag == "Alliance" or tag == "Horde") and tag or nil
end

function A:MenuContextGUID(context)
    if type(context) ~= "table" then return nil end
    local guid = context.guid
    if type(guid) ~= "string" and type(context.playerLocation) == "table" then
        local loc = context.playerLocation
        if loc.IsValid and safeCall(loc.IsValid, loc) and loc.GetGUID then
            guid = safeCall(loc.GetGUID, loc)
        end
    end
    local ally = type(context.recentAllyData) == "table" and context.recentAllyData.characterData
    if type(guid) ~= "string" and type(ally) == "table" then
        guid = ally.guid
    end
    if type(guid) ~= "string" and context.lineID and C_ChatInfo and C_ChatInfo.GetChatLineSenderGUID then
        guid = safeCall(C_ChatInfo.GetChatLineSenderGUID, context.lineID)
    end
    guid = plainString(guid)
    return guid and guid:match("^Player%-") and guid or nil
end

-- On WoW Forever the second name part (UnitFullName's "realm") is the character's
-- surname. Splits "First<sep>Surname" with Blizzard's own separator rules.
local function splitFullName(full)
    full = plainString(full)
    if not full then return nil end
    if NameUtil and NameUtil.SplitPlayerNameIntoParts then
        local first, surname = safeCall(NameUtil.SplitPlayerNameIntoParts, full)
        if plainString(first) then return first, plainString(surname) end
    end
    local first, surname = full:match("^([^%-]+)%-(.+)$")
    if first then return first, surname end
    return full, nil
end

-- Recent Allies entries carry their own character data (including the exact
-- race ID), which also covers players missing from the client's player cache.
-- realmName is the actual server; the surname lives only in fullName.
local function allyInfo(context)
    local ally = type(context) == "table" and type(context.recentAllyData) == "table"
        and context.recentAllyData.characterData
    if type(ally) ~= "table" then return nil end
    local class
    if ally.classID and C_CreatureInfo and C_CreatureInfo.GetClassInfo then
        local info = safeCall(C_CreatureInfo.GetClassInfo, ally.classID)
        class = info and info.classFile
    end
    local name, surname = splitFullName(ally.fullName)
    if not name then name = plainString(ally.name) end
    return class, factionForRaceID(ally.raceID), name, surname
end

function A:CaptureGUID(guid, context)
    if guid == self.myGuid then return nil end
    -- Prefer a live unit token when the player is grouped, targeted, or nearby.
    local token = plainString(UnitTokenFromGUID and safeCall(UnitTokenFromGUID, guid))
    if token then
        local t = self:CaptureUnit(token)
        if t then return t end
    end
    local class, faction, name, realm = allyInfo(context)
    if not name and GetPlayerInfoByGUID then
        local _, race
        _, class, _, race, _, name, realm = safeCall(GetPlayerInfoByGUID, guid)
        name, realm, race, class = plainString(name), plainString(realm), plainString(race), plainString(class)
        faction = race and factionForRace(race)
        -- Prefer the menu's own name parts: GetPlayerInfoByGUID may report the
        -- server where a surname belongs.
        local menuName, menuSurname = splitFullName(type(context) == "table" and context.name)
        if menuName then
            name = menuName
            realm = menuSurname or plainString(context.surname) or plainString(context.server)
        end
    end
    if not name then return nil end
    local mine = self.myFaction or UnitFactionGroup("player")
    if faction ~= mine then return nil end
    if not realm then
        realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
    end
    local display = self:CleanName(name .. "-" .. (realm or ""):gsub("%s", ""))
    if not display then return nil end
    return { guid = guid, name = display, class = class, faction = mine }
end

function A:MenuTarget(owner, context)
    local unit = context and context.unit
    if (not unit or type(unit) ~= "string") and owner and type(owner.unit) == "string" then
        unit = owner.unit
    end
    if unit then
        local t = self:CaptureUnit(unit)
        if t then return t end
    end
    local guid = self:MenuContextGUID(context)
    if guid then
        local t = self:CaptureGUID(guid, context)
        if t then return t end
    end
    -- Some menu contexts expose a name only. Match it exactly against players
    -- the client can identify; never assume a menu describes the selected target.
    local name, surname = splitFullName(context and context.name)
    if name then
        surname = surname or plainString(context.surname) or plainString(context.server)
        if surname then
            name = name .. "-" .. surname:gsub("%s", "")
        end
        return self:CaptureByName(name, context)
    end
    return nil
end

local function nameMatches(key, name, realm)
    name, realm = plainString(name), plainString(realm)
    if not name then return false end
    if realm and not name:find("%-") then
        name = name .. "-" .. realm:gsub("%s", "")
    end
    return A:Key(name) == key
end

-- Resolves a bare "Name" or "Name-Realm" to a player via unit tokens, the
-- friends list, then the guild roster. Returns nil unless one matches exactly.
function A:CaptureByName(name, context)
    local key = self:Key(name)
    if not key then return nil end
    local units = { "target", "focus", "mouseover" }
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local n, r = UnitName(unit)
            if nameMatches(key, n, r) then
                local t = self:CaptureUnit(unit)
                if t then return t end
            end
        end
    end
    if C_FriendList and C_FriendList.GetFriendInfo then
        local info = safeCall(C_FriendList.GetFriendInfo, name)
            or safeCall(C_FriendList.GetFriendInfo, (name:match("^[^%-]+")))
        if type(info) == "table" and type(info.guid) == "string" and nameMatches(key, info.name) then
            local t = self:CaptureGUID(info.guid, context)
            if t then return t end
        end
    end
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        for i = 1, (GetNumGuildMembers() or 0) do
            local n = select(1, GetGuildRosterInfo(i))
            if nameMatches(key, n) then
                local guid = select(17, GetGuildRosterInfo(i))
                if type(guid) == "string" then return self:CaptureGUID(guid, context) end
                break
            end
        end
    end
    return nil
end

-- /rateme debug: describe every unit menu so unknown tags and context fields
-- on this client can be identified.
local function describeContext(context)
    if type(context) ~= "table" then return tostring(context) end
    local parts = {}
    for k, v in pairs(context) do
        if issecretvalue and issecretvalue(v) then
            parts[#parts + 1] = tostring(k) .. "=<secret>"
        elseif type(v) ~= "table" and type(v) ~= "function" and type(v) ~= "userdata" then
            parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
        else
            parts[#parts + 1] = tostring(k) .. "=<" .. type(v) .. ">"
        end
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

function A:DebugMenu(source, which, context)
    if not (self.db and self.db.settings.debug) then return end
    local ok, text = pcall(describeContext, context)
    self:Debug("Menu " .. tostring(source) .. " " .. tostring(which) .. ": " .. (ok and text or "?"))
end

function A:InitializeIntegration()
    SLASH_RATEME1 = "/rateme"
    SlashCmdList.RATEME = function(msg)
        msg = (msg or ""):lower():match("^%s*(.-)%s*$")
        if msg == "target" or msg == "rate" then
            local target = A:CaptureUnit("target")
            if target then A:OpenEditor(target) else A:Log("Select a friendly, same-faction player first.") end
        elseif msg == "reviews" then
            local target = A:CaptureUnit("target")
            if target then A:OpenReviews(target) else A:Log("Select a friendly, same-faction player first.") end
        elseif msg == "party" then
            if A.lastPartyMembers and #A.lastPartyMembers > 0 then
                A:OpenPartyReview(A.lastPartyMembers)
            else
                A:Log("No recent party to review. Leave a party first.")
            end
        elseif msg == "partytest" then
            A:OpenPartyReviewTest()
        elseif msg == "debug" then
            A:SetSetting("debug", not A.db.settings.debug)
            A:DrawSettings() -- Keep the Settings checkbox synchronized with /rateme debug.
            A:Log(A.db.settings.debug and "Activity details are now shown in your chat window."
                or "Activity details are now hidden from your chat window.")
        elseif msg == "netstats" then
            A:Log(A:NetworkStatsText())
        elseif msg == "peers" then
            local count = 0
            for _ in pairs(A.data.peers) do count = count + 1 end
            A:Log(count .. " known peers in directory (not necessarily online).")
        elseif msg == "minimap" then
            A:SetMinimapVisible(not A.db.settings.minimapVisible)
            A:DrawSettings()
            A:Log("Minimap button " .. (A.db.settings.minimapVisible and "shown" or "hidden") .. ".")
        elseif msg == "minimap show" then
            A:SetMinimapVisible(true)
            A:DrawSettings()
            A:Log("Minimap button shown.")
        elseif msg == "minimap hide" then
            A:SetMinimapVisible(false)
            A:DrawSettings()
            A:Log("Minimap button hidden. Type /rateme to open the addon.")
        elseif msg == "help" then
            A:Log("/rateme — main window; /rateme party — last party; /rateme partytest — party window preview (no saving); /rateme target — rate target; /rateme reviews — reviews for target; /rateme minimap [show|hide]; /rateme peers; /rateme netstats; /rateme debug")
        else
            A:ToggleMain()
        end
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            A:AddTooltip(tooltip)
        end)
    else
        self:Log("Modern tooltip API unavailable; tooltip integration disabled.")
    end
    if Menu and Menu.ModifyMenu then
        for _, tag in ipairs(MENU_TAGS) do
            Menu.ModifyMenu(tag, function(owner, rootDescription, contextData)
                -- Menu callbacks run via securecallfunction, which hides errors; surface them.
                local ok, target = pcall(A.MenuTarget, A, owner, contextData)
                if not ok then
                    A:Debug("Menu " .. tag .. " error: " .. tostring(target))
                    return
                end
                if not target then
                    A:Debug("Menu " .. tag .. ": no eligible player resolved.")
                    return
                end
                rootDescription:CreateDivider()
                rootDescription:CreateButton("Rate Me!", function()
                    A:OpenEditor(target)
                end)
            end)
        end
    else
        self:Log("Menu.ModifyMenu unavailable; use /rateme target.")
    end
    if type(UnitPopup_OpenMenu) == "function" then
        hooksecurefunc("UnitPopup_OpenMenu", function(which, contextData)
            A:DebugMenu("UnitPopup_OpenMenu", which, contextData)
        end)
    end
    if type(UnitPopup_ShowMenu) == "function" then
        hooksecurefunc("UnitPopup_ShowMenu", function(_, which, unit, name)
            A:DebugMenu("UnitPopup_ShowMenu", which, { unit = unit, name = name })
        end)
    end
end
