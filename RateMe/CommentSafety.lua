-- Rate Me! review privacy controls.
-- WoW's mature-language chat filter is not a public, general-purpose API for
-- addon review windows. Do not maintain a local profanity dictionary.
-- Comment text is sanitized by Storage.lua for UI-formatting safety, not censored.
local _, A = ...

function A:ReviewVisibilityKey(guid, reviewer, revision)
    return tostring(guid) .. ":" .. tostring(reviewer) .. ":" .. tostring(revision or 0)
end

function A:ReviewDisplayState(guid, reviewer, vote)
    self.revealedReviews = self.revealedReviews or {}
    local key = self:ReviewVisibilityKey(guid, reviewer, vote and vote.rev)
    local state = self.revealedReviews[key]
    if state then return state, key end
    return self.db.settings.hideCommentsByDefault and "hidden" or "visible", key
end

function A:ReviewCommentText(guid, reviewer, vote)
    if self.db.ignored[reviewer] then return "Reviewer blocked locally. Unblock to view their comment.", nil, nil end
    if not vote.hasComment then return "No written comment", nil, nil end
    if not vote.comment then return "Comment not retrieved. Use Fetch Comments.", nil, nil end
    local state, key = self:ReviewDisplayState(guid, reviewer, vote)
    if state == "hidden" then return "[Comment hidden. Select Show to view.]", "Show", key end
    return vote.comment, "Hide", key
end

function A:CycleReviewVisibility(guid, reviewer, vote)
    local state, key = self:ReviewDisplayState(guid, reviewer, vote)
    self.revealedReviews[key] = state == "hidden" and "visible" or "hidden"
    self:DrawReviews()
end

-- Evidence is attached only when a comment arrived directly on the logged
-- transport. Never derive a report subject from the reviewed target or a
-- forwarded lookup. Old/cache-only and personally authored reviews have no
-- independently captured logged sender, so Report is unavailable for them.
function A:GetCommentReportEvidence(targetGUID, reviewer, vote)
    if type(targetGUID) ~= "string" or type(vote) ~= "table"
        or type(vote.comment) ~= "string" or vote.comment == "" then return nil end
    local source = vote.commentSource
    if type(source) ~= "table" or source.logged ~= true
        or source.targetGUID ~= targetGUID or source.revision ~= vote.rev
        or type(source.receivedAt) ~= "number"
        or type(source.payload) ~= "string" then return nil end
    local author = self:CleanName(source.sender)
    if not author or self:Key(author) ~= self:Key(reviewer)
        or self:Key(author) ~= self:Key(vote.sender)
        or self:Key(author) == self:Key(self.myName) then return nil end
    -- The source includes the exact logged packet accepted for this review.
    -- Check its target, revision and text before using it as report evidence.
    -- For legacy packets, the logged bytes are the canonical message. For a
    -- negotiated codec, reception separately stores its validated v1-shaped
    -- projection while preserving the actual logged packet as report evidence.
    local canonical = source.canonicalPayload or source.payload
    if source.payload:sub(1, 2) == "X|" and (type(source.canonicalPayload) ~= "string"
        or source.canonicalPayload:sub(1, 2) ~= "C|") then return nil end
    if source.payload:sub(1, 2) ~= "X|" and canonical ~= source.payload then return nil end
    local id, guid, revision, comment = canonical:match("^C|([^|]+)|([^|]+)|([^|]+)|(.+)$")
    if not id or guid ~= targetGUID or tonumber(revision) ~= vote.rev
        or comment ~= vote.comment then return nil end
    return {author = author, targetGUID = targetGUID, receivedAt = source.receivedAt,
        revision = vote.rev, comment = vote.comment, payload = source.payload}
end
