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
        if not summary.fresh then tooltip:AddLine("Cached rating — checking online peers", 0.61, 0.65, 0.7) end
    else
        tooltip:AddLine("No community ratings available", 0.63, 0.68, 0.73)
    end
    local mine = self:GetOwnRating(target.guid)
    if mine and not mine.removed then
        tooltip:AddDoubleLine("Your rating", self:StarMarkup(mine.score, 13), 0.91, 0.91, 0.87, 1, 0.78, 0.30)
    end
    self:Query(target)
end

local MENU_TAGS = {
    "MENU_UNIT_TARGET", "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_PARTY1",
    "MENU_UNIT_PARTY2", "MENU_UNIT_PARTY3", "MENU_UNIT_PARTY4", "MENU_UNIT_RAID",
    "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FOCUS", "MENU_UNIT_FRIEND", "MENU_UNIT_GUILD",
    "MENU_UNIT_GUILD_MEMBER", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
}

function A:MenuTarget(owner, context)
    local unit = context and context.unit
    if (not unit or type(unit) ~= "string") and owner and type(owner.unit) == "string" then
        unit = owner.unit
    end
    if unit then return self:CaptureUnit(unit) end
    -- Some menu contexts expose a name only. Use the target token ONLY on an exact
    -- name match; never assume a party/guild menu describes the selected target.
    local name = context and context.name
    if type(name) == "string" and self:UnitEligible("target") then
        local t = self:CaptureUnit("target")
        if t and (name == UnitName("target") or self:Key(name) == self:Key(t.name)) then return t end
    end
    return nil
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
            A:Log("/rateme — main window; /rateme party — last party; /rateme target — rate target; /rateme reviews — reviews for target; /rateme minimap [show|hide]; /rateme peers; /rateme netstats; /rateme debug")
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
                local target = A:MenuTarget(owner, contextData)
                if not target then return end
                rootDescription:CreateDivider()
                rootDescription:CreateButton("Rate Me!", function()
                    A:OpenEditor(target)
                end)
            end)
        end
    else
        self:Log("Menu.ModifyMenu unavailable; use /rateme target.")
    end
end
