-- Load and bind the dormant communication companion for isolated tests.
return function(addon)
    local communication = {}
    for _, name in ipairs({'Store','Payload','Diagnostics','Broadcasts','ReviewTags','SharedReviews','Network'}) do
        assert(loadfile('RateMeCommunication/'..name..'.lua'))('RateMeCommunication', communication)
    end
    return communication:Bind(addon)
end
