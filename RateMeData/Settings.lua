-- The RateMeData companion owns all persistent settings and initialization.
local _, Store = ...
local A = Store.API
A.SETTINGS_SCHEMA_VERSION = 1

function A:InitializeStorage()
    local db = Store:Open(self.protocol, self:Stamp(), self.MAX_RECENT)
    self.db, self.data = db, db -- two runtime aliases to ONE persisted table
    local settings = db.settings
    if type(settings.hideCommentsByDefault) ~= "boolean" then settings.hideCommentsByDefault = false end
    if type(settings.debug) ~= "boolean" then settings.debug = false end
    if settings.allCharacters == nil then settings.allCharacters = false end
    -- The minimap button is visible by default.
    if type(settings.minimapVisible) ~= "boolean" then settings.minimapVisible = true end
    -- Clockwise/counterclockwise minimap placement in degrees, 45 = upper-right.
    if type(settings.minimapAngle) ~= "number"
        or settings.minimapAngle ~= settings.minimapAngle
        or settings.minimapAngle == math.huge
        or settings.minimapAngle == -math.huge then
        settings.minimapAngle = 45
    end
    settings.minimapAngle = settings.minimapAngle % 360
    -- Visual reputation highlights are opt-in; keep all existing settings intact.
    if type(settings.ratingHighlights) ~= "boolean" then settings.ratingHighlights = false end
    -- Glow defaults on within its opt-in parent; numeric nameplate badge defaults off.
    if type(settings.ratingHighlightsGlow) ~= "boolean" then settings.ratingHighlightsGlow = true end
    if type(settings.ratingHighlightsBadge) ~= "boolean" then settings.ratingHighlightsBadge = false end
    -- Show a multi-player rating form after leaving a non-raid party.
    if type(settings.partyReviewPrompt) ~= "boolean" then settings.partyReviewPrompt = true end
    -- Source preferences are independent for alerts and visual highlights.
    -- Community is the default source; personal rating checks are opt-in.
    if type(settings.lowRatingPersonal) ~= "boolean" then settings.lowRatingPersonal = false end
    if type(settings.lowRatingCommunity) ~= "boolean" then settings.lowRatingCommunity = true end
    if type(settings.ratingHighlightsPersonal) ~= "boolean" then settings.ratingHighlightsPersonal = false end
    if type(settings.ratingHighlightsCommunity) ~= "boolean" then settings.ratingHighlightsCommunity = true end
    if type(settings.lowRatingPersonalThreshold) ~= "number"
        or settings.lowRatingPersonalThreshold ~= settings.lowRatingPersonalThreshold
        or settings.lowRatingPersonalThreshold == math.huge
        or settings.lowRatingPersonalThreshold == -math.huge then
        settings.lowRatingPersonalThreshold = 3.0
    end
    settings.lowRatingPersonalThreshold = math.max(1, math.min(5,
        math.floor(settings.lowRatingPersonalThreshold * 2 + 0.5) / 2))
    -- Account-wide notification preferences.
    if type(settings.lowRatingAlerts) ~= "boolean" then settings.lowRatingAlerts = false end
    if type(settings.lowRatingThreshold) ~= "number"
        or settings.lowRatingThreshold ~= settings.lowRatingThreshold then
        settings.lowRatingThreshold = 3.0
    end
    if settings.lowRatingThreshold == math.huge or settings.lowRatingThreshold == -math.huge then
        settings.lowRatingThreshold = 3.0
    end
    settings.lowRatingThreshold = math.max(1, math.min(5,
        math.floor(settings.lowRatingThreshold * 2 + 0.5) / 2))
    if type(db.authored[self:Key(self.myName)]) ~= "table" then
        db.authored[self:Key(self.myName)] = {}
    end
end


-- Persistent setting changes go through the companion's data API.
function A:SetSetting(key, value)
    if type(key) ~= "string" or not self.db or type(self.db.settings) ~= "table"
        or self.db.settings[key] == nil then return false end
    self.db.settings[key] = value
    return true
end
