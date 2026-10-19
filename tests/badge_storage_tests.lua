local A={myName='Owner-Realm'}
function A:Key(name)return name:lower() end
function A:Stamp()return 500000 end
local S = dofile('tests/load_data_addon.lua')
RateMeDB = {settings={ratingHighlights=true,ratingHighlightsPersonal=true,ratingHighlightsCommunity=true,
 lowRatingAlerts=true,lowRatingThreshold=2.5},authored={['owner-realm']={['Player-ABC-123']={score=5}}}}
local chunk=assert(loadfile('RateMe/Storage.lua'));chunk('RateMe',A)
A:InitializeStorage()
assert(A.db.settings.ratingHighlights and A.db.settings.ratingHighlightsGlow==true)
assert(A.db.settings.ratingHighlightsBadge==false,'new option must be opt-in')
assert(A.db.settings.lowRatingThreshold==2.5)
assert(A.db.authored['owner-realm']['Player-ABC-123'].score==5)
A.db.settings.ratingHighlightsBadge=true; A.db.settings.ratingHighlightsGlow=false
A:InitializeStorage()
assert(A.db.settings.ratingHighlightsBadge and not A.db.settings.ratingHighlightsGlow, 'new values must persist')
print('PASS: badge defaults off, default glow preserved, all ratings and settings retained')

