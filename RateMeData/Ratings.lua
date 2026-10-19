-- Storage class implemented by RateMeData; bound into the RateMe interface for existing callers.
local _, Store = ...
local A = Store.API

function A:OwnRatings()
    return self.db.authored[self:Key(self.myName)]
end

function A:GetOwnRating(guid)
    return self:OwnRatings()[guid]
end


function A:SaveOwnRating(target, score, tags)
    if not self:ValidateStoredTarget(target) then return false, "Invalid or opposing-faction target" end
    if type(score) ~= "number" or score ~= math.floor(score) or score < 1 or score > 5 then
        return false, "Choose a rating from 1 to 5"
    end
    local encoded = self:EncodeReviewTags(tags)
    if not encoded then return false, "Choose up to three valid, non-conflicting tags" end
    local records = self:OwnRatings()
    local prior = records[target.guid]
    records[target.guid] = {
        guid = target.guid, name = target.name, faction = target.faction, class = target.class,
        score = score, tags = encoded, date = self:Stamp(),
        rev = (prior and tonumber(prior.rev) or 0) + 1,
    }
    self:RememberTarget(target)
    self:NotifyUI()
    if self.db and self.db.settings and self.db.settings.debug then
        self:Debug(string.format("Saved your rating for %s: %d out of 5 stars (update %d).",
            self:DisplayName(target.name), score, records[target.guid].rev))
    end
    if self.ScheduleRatingBroadcast then self:ScheduleRatingBroadcast(target) end
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
        removed = true, score = 0, tags = "", date = self:Stamp(),
        rev = (tonumber(prior.rev) or 0) + 1,
    }
    self:NotifyUI()
    if self.db and self.db.settings and self.db.settings.debug then
        self:Debug(string.format("Removed your rating for %s (update %d).",
            self:DisplayName(target.name), records[target.guid].rev))
    end
    if self.ScheduleRatingBroadcast then self:ScheduleRatingBroadcast(target) end
    if self.OnPersonalRatingChanged then self:OnPersonalRatingChanged(target.guid) end
    return true
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

function A:OnPersonalRatingChanged(guid)
    if self.RefreshHighlights then self:RefreshHighlights() end
    if self.groupMembers and self.groupMembers[guid] and self.WarnForLowRating then
        self:WarnForLowRating(self.groupMembers[guid])
    end
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
