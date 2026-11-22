-- Storage class implemented by RateMeData; bound into the RateMe interface for existing callers.
local _, Store = ...
local A = Store.API

-- Peer tiers, best first:
--   1 trusted  - on your friends list or in your guild (checked by RateMe
--                through the game's own lists, so strangers cannot fake it)
--   2 proven   - has sent a real rating reply or shared review to your lookup
--   3 newcomer - has only greeted you (or announced a rating)
-- A peer can only be pushed out of the list by someone in the same or a
-- better tier. Repeated greetings never move a newcomer up the list.
local MAX_PEERS = 120
local NEW_PEERS_PER_MINUTE = 10

function A:PeerTier(key, peer)
    if self.IsTrustedPeerKey and self:IsTrustedPeerKey(key) then return 1 end
    if type(peer) == "table" and peer.proven then return 2 end
    return 3
end

-- Within a tier: trusted/proven peers by most recent activity, newcomers by
-- when they were first added (a greeting does not refresh that).
local function rankTime(peer, tier)
    if tier == 3 then return peer.added or peer.seen or 0 end
    return peer.proven and math.max(peer.proven, peer.seen or 0) or peer.seen or 0
end

-- kind: "greeting" (hello/ack or announcement: rate-limited for strangers,
-- never refreshes rank), "proven" (a real reply to our lookup), or nil
-- (plain add, used by tests and internal callers).
function A:RememberPeer(name, kind)
    local key = self:Key(name)
    if not key or key == self:Key(self.myName) then return end
    local now = self:Stamp()
    local item = self.data.peers[key]
    if not item then
        if kind == "greeting" and self:PeerTier(key, nil) == 3 then
            -- At most NEW_PEERS_PER_MINUTE strangers join per minute by greeting.
            local window = self.peerAdmissions
            local t = self.Now and self:Now() or now
            if not window or t - window.started >= 60 then
                window = {started = t, count = 0}
                self.peerAdmissions = window
            end
            if window.count >= NEW_PEERS_PER_MINUTE then return end
            window.count = window.count + 1
        end
        item = {added = now}
    end
    item.name = self:CleanName(name)
    item.seen = now -- last heard from at all: used only to tell who is online
    item.added = item.added or now
    if kind == "proven" then item.proven = now end
    self.data.peers[key] = item
    -- Keep at most MAX_PEERS: drop the worst-tier, oldest-ranked peer.
    local count = 0
    for _ in pairs(self.data.peers) do count = count + 1 end
    if count > MAX_PEERS then
        local victim, worstTier, worstTime
        for k, p in pairs(self.data.peers) do
            local tier = self:PeerTier(k, p)
            local time = rankTime(p, tier)
            if not victim or tier > worstTier or (tier == worstTier and time < worstTime) then
                victim, worstTier, worstTime = k, tier, time
            end
        end
        if victim then self.data.peers[victim] = nil end
    end
end

-- Peers seen in the last hour, best tier first. Within a tier, trusted and
-- proven peers are ordered by recent activity, newcomers by first contact.
function A:RankedPeers(exclude)
    local ranked = {}
    local cutoff = self:Stamp() - 3600
    local excluded, mine = self:Key(exclude), self:Key(self.myName)
    for key, peer in pairs(self.data.peers) do
        if peer.seen and peer.seen >= cutoff and peer.name and key ~= excluded and key ~= mine then
            local tier = self:PeerTier(key, peer)
            ranked[#ranked + 1] = {name = peer.name, tier = tier, time = rankTime(peer, tier), key = key}
        end
    end
    table.sort(ranked, function(x, y)
        if x.tier ~= y.tier then return x.tier < y.tier end
        if x.tier == 3 then
            if x.time ~= y.time then return x.time < y.time end
        elseif x.time ~= y.time then return x.time > y.time end
        return x.key < y.key
    end)
    return ranked
end

function A:PeerNames(exclude, maximum)
    local result = {}
    for _, peer in ipairs(self:RankedPeers(exclude)) do
        if maximum and #result >= maximum then break end
        result[#result + 1] = peer.name
    end
    return result
end

function A:SetPeerHello(name, stamp)
    local key = self:Key(name)
    if key and type(self.data.peers[key]) == "table" then
        self.data.peers[key].hello = stamp
    end
end
