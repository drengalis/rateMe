-- Persisted reviewer-block list; presentation and report guidance stay in RateMe.
local _, Store = ...
local A = Store.API

function A:ToggleReviewerBlock(reviewer)
    local key = self:Key(reviewer)
    if not key or not self.db or type(self.db.ignored) ~= "table" then return nil end
    local blocked = not self.db.ignored[key]
    self.db.ignored[key] = blocked or nil
    return blocked
end
