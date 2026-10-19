-- No data imports: RateMeData owns RateMeDB exclusively from first release.
local fs = assert(io.open('RateMeData/RateMeData.toc', 'r')):read('*a')
local fc = assert(io.open('RateMeData/RateMeData_Camelot.toc', 'r')):read('*a')
local ms = assert(io.open('RateMe/RateMe.toc', 'r')):read('*a')
local mc = assert(io.open('RateMe/RateMe_Camelot.toc', 'r')):read('*a')
assert(fs:find('## SavedVariables: RateMeDB',1,true))
assert(fc:find('## SavedVariables: RateMeDB',1,true))
assert(not ms:find('## SavedVariables:',1,true) and not mc:find('## SavedVariables:',1,true))
assert(ms:find('## Dependencies: RateMeData',1,true))
assert(mc:find('## Dependencies: RateMeData',1,true))
for _, str in ipairs({'RateMeDataDB', 'legacy', 'RegisterMigration', 'MigrateSettings'}) do
  for _, name in ipairs({'Store.lua','Settings.lua'}) do
    local txt = assert(io.open('RateMeData/'..name,'r')):read('*a')
    assert(not txt:find(str,1,true), 'Unexpected migration feature: '..str)
  end
end
local store = dofile('tests/load_data_addon.lua')
assert(RateMeDataStore == store)
RateMeDB = nil
local data = store:Open('1',1700000025,150)
assert(data == RateMeDB and data.schema == 1 and data.settingsSchema == 1)
for _, key in ipairs({'authored','settings','ignored','recent','peers'}) do
  assert(type(data[key]) == 'table', key)
end
assert(data.peerProtocol == '1' and next(data.peers) == nil)
assert(store:Open('1',1700000025,150) == data)
-- Every category persists under the same table, including personal ratings.
RateMeDB.authored['owner-realm'] = {['Player-2'] = {score=5,comment='private'}}
RateMeDB.recent['Player-1']={guid='Player-1',name='Target-Realm',faction='Alliance',checked=1700000020}
RateMeDB.settings.debug = true
RateMeDB.ignored['reviewer-realm'] = true
RateMeDB.peers['peer-realm'] = {name='Peer-Realm',seen=1700000024}
assert(store:Open('1',1700000025,150) == RateMeDB)
assert(RateMeDB.authored['owner-realm']['Player-2'].comment=='private')
assert(RateMeDB.recent['Player-1'].name=='Target-Realm')
assert(RateMeDB.settings.debug and RateMeDB.ignored['reviewer-realm'])
assert(RateMeDB.peers['peer-realm'].name=='Peer-Realm')
-- Unknown future schemas fail closed; no conversion path and no mutation.
for _, field in ipairs({'schema','settingsSchema'}) do
  local future = {schema=1,settingsSchema=1,futureFlag='untouched'}
  future[field]=2
  RateMeDB=future
  local ok = pcall(function() store:Open('1',1700000025,150) end)
  assert(not ok and future[field] == 2 and future.futureFlag=='untouched')
  assert(future.authored==nil and future.peerProtocol==nil)
end
RateMeDB = {settings={},authored={},recent={},peers={},ignored={},peerProtocol='1'}
local A={myName='Owner-Realm',protocol='1',MAX_RECENT=150,myFaction='Alliance'}
function A:Key(name) return name:lower() end
function A:Stamp() return 1700000080 end
assert(loadfile('RateMe/Storage.lua'))('RateMe',A)
assert(A.InitializeStorage == store.API.InitializeStorage)
assert(A.runtime == store.session and A.runtime.cache and A.runtime.requests)
A:InitializeStorage()
assert(A.data == RateMeDB and A.db == RateMeDB)
assert(A:GetOwnRating('Player-2') == nil)
A.db.authored['owner-realm']['Player-2']={score=5}
assert(A:GetOwnRating('Player-2').score==5)
assert(RateMeDB.settingsSchema==1)
print('PASS: companion owns the sole SavedVariables table, all data categories, no migration')
