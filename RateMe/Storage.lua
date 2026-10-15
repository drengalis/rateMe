local _, A = ...

-- The preference schema is independent of the addon version, root data schema
-- and peer wire format. Existing unversioned preferences are schema 1.
-- Future upgrades must be consecutive and additive; never reuse an old key with
-- a different meaning without explicitly migrating it.
A.SETTINGS_SCHEMA_VERSION = 1
A.settingsMigrations = A.settingsMigrations or {}
function A:RegisterSettingsMigration(version, migration)
    if type(version) ~= "number" or version ~= math.floor(version) or version < 2
        or type(migration) ~= "function" then return false end
    if self.settingsMigrations[version] then return false end -- no replacing a published migration
    self.settingsMigrations[version] = migration
    return true
end
local function copySaved(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[copySaved(key, seen)] = copySaved(item, seen) end
    return result
end
function A:MigrateSettings(db)
    local stored = tonumber(db.settingsSchema)
    if not stored or stored ~= math.floor(stored) or stored < 1 then stored = 1 end
    if stored > self.SETTINGS_SCHEMA_VERSION then
        -- A downgraded addon can still read the known preferences and save
        -- ratings, but MUST NOT overwrite a newer installation's settings.
        return false, "future"
    end
    if stored == self.SETTINGS_SCHEMA_VERSION then
        db.settingsSchema = stored
        return true
    end
    -- Apply to a detached copy and commit only when EVERY migration succeeds.
    -- This preserves unknown fields and prevents partial migration on failure.
    local draft = copySaved(db.settings)
    for version = stored + 1, self.SETTINGS_SCHEMA_VERSION do
        local migration = self.settingsMigrations[version]
        if type(migration) ~= "function" then return false, "missing migration " .. version end
        -- The migration receives snapshots only. It cannot partially mutate
        -- the live SavedVariables by changing the metadata argument.
        local ok, result = pcall(migration, draft, copySaved(db))
        if not ok or result == false then return false, "migration failed " .. version end
    end
    db.settings = draft
    db.settingsSchema = self.SETTINGS_SCHEMA_VERSION
    return true
end

function A:InitializeStorage()
    if type(RateMeDB) ~= "table" then RateMeDB = {} end
    local db = RateMeDB
    if type(db.schema) ~= "number" or db.schema < 1 then db.schema = 1 end
    if type(db.authored) ~= "table" then db.authored = {} end
    if type(db.recent) ~= "table" then db.recent = {} end
    if type(db.peers) ~= "table" then db.peers = {} end
    -- When the stored peer marker differs, rediscover contacts; keep saved ratings.
    -- The addon stays at version 1 with the RATEME prefix during testing.
    if db.peerProtocol ~= self.protocol then
        db.peers = {}
        db.peerProtocol = self.protocol
    end
    if type(db.settings) ~= "table" then db.settings = {} end
    if type(db.ignored) ~= "table" then db.ignored = {} end
    local migrated, reason = self:MigrateSettings(db)
    if not migrated then
        -- An older client, absent migration or failed migration must NEVER
        -- normalize preferences back into the persistent future/old schema.
        -- Continue with runtime-only settings, but keep ratings and lookups
        -- linked to the original SavedVariables tables.
        local runtimeDB = {}
        for key, value in pairs(db) do runtimeDB[key] = value end
        runtimeDB.settings = copySaved(db.settings)
        db = runtimeDB
        self.settingsFutureSchema = reason == "future"
        self.settingsMigrationError = reason ~= "future" and reason or nil
        if reason ~= "future" then
            self:Log("Settings migration was not applied (" .. reason .. "); saved preferences kept unchanged.")
        end
    end
    -- Retire the previous local profanity dictionary; keep the user's hide preference.
    db.settings.filterComments = nil
    if type(db.settings.hideCommentsByDefault) ~= "boolean" then db.settings.hideCommentsByDefault = false end
    if db.settings.debug == nil then db.settings.debug = false end
    if db.settings.allCharacters == nil then db.settings.allCharacters = false end
    -- Keep the existing button visible when upgrading old installations.
    if type(db.settings.minimapVisible) ~= "boolean" then db.settings.minimapVisible = true end
    -- Clockwise/counterclockwise minimap placement in degrees, 45 = upper-right.
    if type(db.settings.minimapAngle) ~= "number"
        or db.settings.minimapAngle ~= db.settings.minimapAngle
        or db.settings.minimapAngle == math.huge
        or db.settings.minimapAngle == -math.huge then
        db.settings.minimapAngle = 45
    end
    db.settings.minimapAngle = db.settings.minimapAngle % 360
    -- Visual reputation highlights are opt-in; keep all existing settings intact.
    if type(db.settings.ratingHighlights) ~= "boolean" then db.settings.ratingHighlights = false end
    -- Preserve existing glow behaviour on upgrade; new numeric nameplate badge is opt-in.
    if type(db.settings.ratingHighlightsGlow) ~= "boolean" then db.settings.ratingHighlightsGlow = true end
    if type(db.settings.ratingHighlightsBadge) ~= "boolean" then db.settings.ratingHighlightsBadge = false end
    -- Show a multi-player rating form after leaving a non-raid party.
    if type(db.settings.partyReviewPrompt) ~= "boolean" then db.settings.partyReviewPrompt = true end
    -- Source preferences are independent for alerts and visual highlights.
    -- Existing installations continue using their prior community settings;
    -- personal rating checks are opt-in during migration.
    if type(db.settings.lowRatingPersonal) ~= "boolean" then db.settings.lowRatingPersonal = false end
    if type(db.settings.lowRatingCommunity) ~= "boolean" then db.settings.lowRatingCommunity = true end
    if type(db.settings.ratingHighlightsPersonal) ~= "boolean" then db.settings.ratingHighlightsPersonal = false end
    if type(db.settings.ratingHighlightsCommunity) ~= "boolean" then db.settings.ratingHighlightsCommunity = true end
    if type(db.settings.lowRatingPersonalThreshold) ~= "number"
        or db.settings.lowRatingPersonalThreshold ~= db.settings.lowRatingPersonalThreshold
        or db.settings.lowRatingPersonalThreshold == math.huge
        or db.settings.lowRatingPersonalThreshold == -math.huge then
        db.settings.lowRatingPersonalThreshold = 3.0
    end
    db.settings.lowRatingPersonalThreshold = math.max(1, math.min(5,
        math.floor(db.settings.lowRatingPersonalThreshold * 2 + 0.5) / 2))
    -- Account-wide notification preferences, migrated without changing prior ratings.
    if type(db.settings.lowRatingAlerts) ~= "boolean" then db.settings.lowRatingAlerts = false end
    if type(db.settings.lowRatingThreshold) ~= "number"
        or db.settings.lowRatingThreshold ~= db.settings.lowRatingThreshold then
        db.settings.lowRatingThreshold = 3.0
    end
    if db.settings.lowRatingThreshold == math.huge or db.settings.lowRatingThreshold == -math.huge then
        db.settings.lowRatingThreshold = 3.0
    end
    db.settings.lowRatingThreshold = math.max(1, math.min(5,
        math.floor(db.settings.lowRatingThreshold * 2 + 0.5) / 2))
    self.db = db
    if type(db.authored[self:Key(self.myName)]) ~= "table" then
        db.authored[self:Key(self.myName)] = {}
    end
    local pruneBefore = self:Stamp() - 7 * 86400
    for key, peer in pairs(db.peers) do
        if type(peer) ~= "table" or type(peer.seen) ~= "number" or peer.seen < pruneBefore then
            db.peers[key] = nil
        end
    end
end

function A:OwnRatings()
    return self.db.authored[self:Key(self.myName)]
end
function A:GetOwnRating(guid)
    return self:OwnRatings()[guid]
end

function A:UTF8SafeCut(text, maxBytes)
    -- Prevent truncated multibyte sequences (Lua 5.1 has no native utf8 library).
    local result = text:sub(1, maxBytes)
    while #result > 0 do
        local valid = true
        local i = 1
        while i <= #result do
            local x = result:byte(i)
            local count = (x < 128 and 1) or (x >= 194 and x <= 223 and 2)
                or (x >= 224 and x <= 239 and 3) or (x >= 240 and x <= 244 and 4) or 0
            if count == 0 or i + count - 1 > #result then valid = false; break end
            if count > 1 then
                for j = i + 1, i + count - 1 do
                    local b = result:byte(j)
                    if b < 128 or b > 191 then valid = false; break end
                end
                if not valid then break end
            end
            i = i + count
        end
        if valid then return result end
        result = result:sub(1, -2)
    end
    return ""
end
function A:SanitizeComment(value)
    if type(value) ~= "string" then return "" end
    -- Preserve intentional line breaks in multi-line reviews, but remove all
    -- other control characters and WoW markup delimiters (links/textures).
    value = value:gsub("\r\n", "\n"):gsub("\r", "\n")
    value = value:gsub("|", ""):gsub("[%z\1-\9\11-\31\127]", " ")
    return self:UTF8SafeCut(value, self.MAX_COMMENT)
end

function A:SaveOwnRating(target, score, comment)
    if not self:ValidateStoredTarget(target) then return false, "Invalid or opposing-faction target" end
    if type(score) ~= "number" or score ~= math.floor(score) or score < 1 or score > 5 then
        return false, "Choose a rating from 1 to 5"
    end
    local records = self:OwnRatings()
    local prior = records[target.guid]
    records[target.guid] = {
        guid = target.guid, name = target.name, faction = target.faction, class = target.class,
        score = score, comment = self:SanitizeComment(comment), date = self:Stamp(),
        rev = (prior and tonumber(prior.rev) or 0) + 1,
    }
    self:RememberTarget(target)
    self:NotifyUI()
    if self.OnPersonalRatingChanged then self:OnPersonalRatingChanged(target.guid) end
    return true
end

function A:DeleteOwnRating(target)
    if not self:ValidateStoredTarget(target) then return false end
    -- Keep a revisioned tombstone, so a deletion does not revive during this session.
    local records = self:OwnRatings()
    local prior = records[target.guid]
    if not prior then return false end
    records[target.guid] = {
        guid = target.guid, name = target.name, faction = target.faction, class = target.class,
        removed = true, score = 0, comment = "", date = self:Stamp(),
        rev = (tonumber(prior.rev) or 0) + 1,
    }
    self:NotifyUI()
    if self.OnPersonalRatingChanged then self:OnPersonalRatingChanged(target.guid) end
    return true
end

function A:RememberTarget(target)
    if not self:ValidateStoredTarget(target) then return end
    local recent = self.db.recent
    local item = recent[target.guid] or {}
    item.guid, item.name, item.faction, item.class = target.guid, target.name, target.faction, target.class
    item.viewed = self:Stamp()
    recent[target.guid] = item
    local count = 0
    for _ in pairs(recent) do count = count + 1 end
    while count > self.MAX_RECENT do
        local oldestKey, oldest = nil, math.huge
        for guid, entry in pairs(recent) do
            if (entry.viewed or 0) < oldest then oldest = entry.viewed or 0; oldestKey = guid end
        end
        if not oldestKey then break end
        recent[oldestKey] = nil
        count = count - 1
    end
end

function A:GetPersonalScore(guid)
    local vote = self:GetOwnRating(guid)
    if vote and not vote.removed and vote.faction == self.myFaction
        and type(vote.score) == "number" and vote.score >= 1 and vote.score <= 5 then
        return vote.score
    end
    return nil
end

-- Return an authenticated, fresh community sample only. Cached historical
-- summaries are for display, not for current alerts or colour effects.
function A:GetFreshCommunityScore(guid)
    local summary = self:GetSummary(guid)
    if summary and summary.fresh and summary.average and summary.count > 0 then
        return summary.average, summary.count
    end
    return nil
end

function A:OnPersonalRatingChanged(guid)
    if self.RefreshHighlights then self:RefreshHighlights() end
    if self.groupMembers and self.groupMembers[guid] and self.WarnForLowRating then
        self:WarnForLowRating(self.groupMembers[guid])
    end
end

function A:GetSummary(guid)
    local cache = self.runtime.cache[guid]
    if cache then
        local total, count, withComments = 0, 0, 0
        for _, v in pairs(cache.votes) do
            if v.score >= 1 and v.score <= 5 then
                total, count = total + v.score, count + 1
                if v.hasComment then withComments = withComments + 1 end
            end
        end
        local age = self:Now() - (cache.fetchedAt or 0)
        return { average = count > 0 and total / count or nil, count = count,
            comments = withComments, fresh = age < self.CACHE_SECONDS,
            age = math.max(0, age), at = cache.lastComplete or 0 }
    end
    local prior = self.db.recent[guid]
    if prior and prior.checked and prior.checked > 0 then
        return { average = prior.average, count = prior.count or 0, comments = prior.comments or 0,
            fresh = false, at = prior.checked, historical = true }
    end
    return nil
end

function A:ListOwn()
    local list = {}
    for owner, records in pairs(self.db.authored) do
        if owner == self:Key(self.myName) or self.db.settings.allCharacters then
            if type(records) == "table" then
                for _, entry in pairs(records) do
                    if type(entry) == "table" and not entry.removed and entry.score then
                        local item = {}
                        for k, v in pairs(entry) do item[k] = v end
                        item.owner = owner
                        table.insert(list, item)
                    end
                end
            end
        end
    end
    return list
end
function A:ListRecent()
    local list = {}
    for guid, entry in pairs(self.db.recent) do
        if entry.faction == self.myFaction and guid ~= self.myGuid then
            local item = {}
            for k, v in pairs(entry) do item[k] = v end
            local summary = self:GetSummary(guid)
            item.score = summary and summary.average or nil
            item.count = summary and summary.count or 0
            item.fresh = summary and summary.fresh or false
            table.insert(list, item)
        end
    end
    return list
end
