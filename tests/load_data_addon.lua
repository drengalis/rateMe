-- Test helper: mimic WoW loading RateMeData before RateMe.
local S = {}
for _, path in ipairs({'Store','Settings','Tags','Ratings','Community','Peers','Reviewers'}) do
    assert(loadfile('RateMeData/'..path..'.lua'))('RateMeData', S)
end
return S

