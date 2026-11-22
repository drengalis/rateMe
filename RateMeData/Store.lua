-- All persistent Rate Me! data belongs to this companion addon. The only
-- SavedVariables declaration is RateMeData/RateMeData.toc: RateMeDB.
local _, Store = ...
_G.RateMeDataStore = Store
Store.SCHEMA_VERSION = 1
local UNVERIFIED_REVIEW_DAYS = 90
Store.API = Store.API or {}

local function dateOf(item)
    if type(item) ~= "table" then return 0 end
    return math.max(tonumber(item.checked) or 0, tonumber(item.viewed) or 0)
end

local function pruneOldest(records, maximum, when)
    local count = 0
    for _ in pairs(records) do count = count + 1 end
    while count > maximum do
        local oldest, stamp
        for key, item in pairs(records) do
            local value = when(item)
            if oldest == nil or value < stamp then oldest, stamp = key, value end
        end
        if oldest == nil then break end
        records[oldest] = nil
        count = count - 1
    end
end

-- Bind the data API to the main addon's existing A:Method() interface; method
-- definitions and SavedVariables are owned solely by RateMeData.
function Store:Bind(addon)
    assert(type(addon) == "table", "RateMeData:Bind expects the main addon")
    for key, value in pairs(self.API) do addon[key] = value end
    addon.CACHE_SECONDS = addon.CACHE_SECONDS or 900
    addon.MAX_RECENT = addon.MAX_RECENT or 150
    -- Runtime views and request state also live here. Durable reviews are in
    -- db.community; monotonic timers and transport evidence stay session-only.
    self.session = self.session or addon.runtime or {cache={}, requests={}, seen={}}
    addon.runtime = self.session
    return addon
end

-- Initial schema only. There is no import or migration path in this unreleased
-- storage layout. Refuse an unfamiliar schema rather than overwriting it.
function Store:Open(protocol, now, recentLimit)
    if type(RateMeDB) ~= "table" then RateMeDB = {} end
    local db = RateMeDB
    if db.schema ~= nil and db.schema ~= self.SCHEMA_VERSION then
        error("RateMeData: unsupported data schema; refusing to modify RateMeDB")
    end
    if db.settingsSchema ~= nil and db.settingsSchema ~= 1 then
        error("RateMeData: unsupported settings schema; refusing to modify RateMeDB")
    end
    db.schema, db.settingsSchema = self.SCHEMA_VERSION, 1
    for _, key in ipairs({"authored", "settings", "ignored", "recent", "peers", "community", "windows"}) do
        if type(db[key]) ~= "table" then db[key] = {} end
    end
    if db.peerProtocol ~= protocol then
        db.peers = {} -- discovery state, not personal ratings
        db.peerProtocol = protocol
    end
    pruneOldest(db.recent, recentLimit or 150, dateOf)
    -- Reviews nobody has confirmed (passed along by someone other than the
    -- author) are deleted 90 days after this client received them; a player left with no reviews is
    -- removed. Verified reviews, including removals, are kept.
    local unverifiedCutoff = (now or 0) - UNVERIFIED_REVIEW_DAYS * 86400
    for guid, item in pairs(db.community) do
        if type(item) ~= "table" or type(item.votes) ~= "table" then
            db.community[guid] = nil
        else
            for key, vote in pairs(item.votes) do
                local verified = type(vote) == "table" and type(vote.verifiedAt) == "number" and vote.verifiedAt > 0
                if type(vote) ~= "table" then
                    item.votes[key] = nil
                elseif not verified then
                    -- Expiry uses when this client received the review, never the
                    -- date it claims. Reviews saved before receipt
                    -- times existed count as received now.
                    local received = tonumber(vote.receivedAt)
                    if not received then
                        vote.receivedAt = now or 0
                    elseif received < unverifiedCutoff then
                        item.votes[key] = nil
                    end
                end
            end
            if next(item.votes) == nil then db.community[guid] = nil end
        end
    end
    local cutoff = (now or 0) - 7 * 86400
    for key, peer in pairs(db.peers) do
        if type(peer) ~= "table" or type(peer.seen) ~= "number" or peer.seen < cutoff then
            db.peers[key] = nil
        end
    end
    pruneOldest(db.peers, 120, function(peer) return tonumber(peer.seen) or 0 end)
    return db
end
