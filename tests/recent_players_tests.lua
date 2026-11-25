-- Recent Players: capture from party/raid, saved list limit and load-time reset.
A={db={settings={partyReviewPrompt=false,allCharacters=false},grouped={}},MAX_RECENT=3}
local units, raid, grouped = {}, false, false
local clock=1000
time=function() return clock end
IsInRaid=function() return raid end
IsInGroup=function() return grouped end
GetNumGroupMembers=function() local n=0 for k in pairs(units) do n=n+1 end return n end
UnitIsInMyGuild=function() return false end
function A:CaptureUnit(u) local n=units[u]; if n then return {guid='Player-1-'..n,name=n..'-Realm',class='MAGE',faction='Alliance'} end end
function A:GetOwnRating(g) if g=='Player-1-Bob' then return {score=4} end end
assert(loadfile('RateMe/PartyReview.lua'))('RateMe',A)
CreateFrame=function() return {RegisterEvent=function() end,SetScript=function() end} end
A:InitializePartyReviews()
grouped=true; units={party1='Bob',party2='Guildie'}; A:OnPartyReviewRosterChange()
clock=2000; units={party1='Bob'}; A:OnPartyReviewRosterChange()
local g=A.db.grouped
assert(g['Player-1-Bob'].inGroup and not g['Player-1-Guildie'].inGroup and g['Player-1-Guildie'].lastGrouped==2000)
clock=3000; raid=true; units={raid1='Bob',raid2='Zed'}; A:OnPartyReviewRosterChange()
clock=4000; raid=false; grouped=false; units={}; A:OnPartyReviewRosterChange()
local n=0 for _,e in pairs(g) do n=n+1; assert(not e.inGroup) end
assert(n==3 and g['Player-1-Zed'].lastGrouped==4000)
clock=5000; grouped=true; units={party1='New'}; A:OnPartyReviewRosterChange()
assert(g['Player-1-New'] and not g['Player-1-Guildie'],'oldest pruned at limit')
n=0 for _ in pairs(g) do n=n+1 end assert(n==3)
-- Store: reload clears inGroup and prunes
local Store={API={}}
assert(loadfile('RateMeData/Store.lua'))('RateMeData',Store)
RateMeDB={schema=1,settingsSchema=1,grouped={a={lastGrouped=1,inGroup=true},b={lastGrouped=3},c={lastGrouped=2},d='junk'}}
Store:Open(nil,0,2)
assert(RateMeDB.grouped.b and RateMeDB.grouped.c and not RateMeDB.grouped.a and not RateMeDB.grouped.d and RateMeDB.grouped.b.inGroup==false)
-- list
print('PASS: recent players saved across sessions, raid and party, limit, in-group status reset on load')
