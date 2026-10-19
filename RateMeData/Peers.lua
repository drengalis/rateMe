-- Storage class implemented by RateMeData; bound into the RateMe interface for existing callers.
local _, Store = ...
local A = Store.API

function A:RememberPeer(name)
    local key = self:Key(name)
    if not key or key == self:Key(self.myName) then return end
    local item = self.data.peers[key] or {}
    item.name = self:CleanName(name)
    item.seen = self:Stamp()
    self.data.peers[key] = item
    -- Cap peer directory, avoiding unbounded SavedVariables growth.
    local count = 0
    for _ in pairs(self.data.peers) do count = count + 1 end
    if count > 120 then
        local oldestKey, timestamp = nil, math.huge
        for k, p in pairs(self.data.peers) do
            if (p.seen or 0) < timestamp then timestamp, oldestKey = p.seen or 0, k end
        end
        if oldestKey then self.data.peers[oldestKey] = nil end
    end
end

function A:PeerNames(exclude, maximum)
    local sorted = {}
    -- A day-old peer isn't evidence that it is still reachable online.
    local cutoff = self:Stamp() - 3600
    for key, peer in pairs(self.data.peers) do
        if peer.seen and peer.seen >= cutoff and peer.name and key ~= self:Key(exclude)
            and key ~= self:Key(self.myName) then
            sorted[#sorted + 1] = peer
        end
    end
    table.sort(sorted, function(x, y) return (x.seen or 0) > (y.seen or 0) end)
    local result = {}
    for i = 1, math.min(maximum or #sorted, #sorted) do result[#result + 1] = sorted[i].name end
    return result
end

function A:SetPeerHello(name, stamp)
    local key = self:Key(name)
    if key and type(self.data.peers[key]) == "table" then
        self.data.peers[key].hello = stamp
    end
end
