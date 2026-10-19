-- Communication is dormant until the main addon binds its application API.
local _, Communication = ...
_G.RateMeCommunicationStore = Communication
Communication.API = {}

function Communication:Bind(addon)
    assert(type(addon) == "table", "RateMeCommunication:Bind expects RateMe")
    if addon.communication == self then return addon end
    for key, value in pairs(self.API) do addon[key] = value end
    addon.protocol, addon.prefix = "1", "RATEME"
    addon.MAX_PENDING, addon.QUERY_SECONDS = 5, 15
    addon.payload = addon.Payload.new(addon)
    addon.communication = self
    return addon
end
