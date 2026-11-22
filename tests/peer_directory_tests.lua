-- Peer directory: friends/guild first, then proven peers, then newcomers; strangers
-- cannot flood or take over the peer list.
local function boot(name)
 local a={myName=name or 'Me-Realm',myGuid='Player-1-aa',myFaction='Alliance',clock=0,stamp=1800000000}
 function a:Now()return self.clock end
 function a:Stamp()return self.stamp+math.floor(self.clock)end
 function a:CleanName(n)if type(n)~='string' or #n<2 or #n>80 or n:find('[%s|%c]')then return nil end;return n end
 function a:Key(n)local v=self:CleanName(n);return v and v:lower()end
 function a:DisplayName(n)return (n:gsub('%-',' '))end
 function a:ValidateStoredTarget(t)return t.faction=='Alliance' and t.guid~=self.myGuid end
 function a:NotifyUI()end
 function a:RefreshTooltip()end
 function a:Log()end
 function a:Debug()end
 local store=dofile('tests/load_data_addon.lua');store:Bind(a)
 dofile('tests/load_communication_addon.lua')(a)
 a:InitializeStorage()
 a.outbox={};a.counter=0;a.nextSend=0;a.inbound={}
 return a
end
RateMeDB=nil
C_Timer={After=function()end,NewTicker=function()end}
local function letters(i) return string.char(97+math.floor((i-1)/26))..string.char(97+(i-1)%26) end
local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end

-- At most 10 strangers join per minute by greeting.
local a=boot()
for i=1,15 do a:OnMessage('RATEME','H|1','WHISPER','Stranger'..letters(i)..'-Realm',false) end
assert(count(a.data.peers)==10,'only 10 new peers per minute: '..count(a.data.peers))
a.clock=61
for i=16,20 do a:OnMessage('RATEME','H|1','WHISPER','Stranger'..letters(i)..'-Realm',false) end
assert(count(a.data.peers)==15,'more are accepted the next minute')
-- Friends and guildmates are never held back.
local trusted={}
function a:IsTrustedPeerKey(key) return trusted[key]==true end
a.clock=62
for i=21,32 do local n='Guildie'..letters(i)..'-Realm';trusted[a:Key(n)]=true;a:OnMessage('RATEME','H|1','WHISPER',n,false) end
assert(count(a.data.peers)==27,'friends/guild join without the limit: '..count(a.data.peers))
-- A repeated greeting does not move a newcomer up the list.
local first=a.data.peers['strangeraa-realm'].added
a.stamp=a.stamp+500;a.clock=200
a:OnMessage('RATEME','H|1','WHISPER','Strangeraa-Realm',false)
assert(a.data.peers['strangeraa-realm'].added==first,'greeting does not refresh rank')
print('PASS: 10 new strangers per minute; friends/guild unlimited; greetings do not refresh rank')

-- A real reply to our lookup makes the sender proven.
local target={guid='Player-1-bb',name='Target-Realm',faction='Alliance'}
assert(a:Query(target,false,true))
local id=next(a.runtime.requests)
a:HandleRating({'R',id,target.guid,'4','1','1800000000','0'},'Strangerab-Realm')
assert(a.data.peers['strangerab-realm'].proven,'reply makes a proven peer')
assert(a:PeerTier('strangerab-realm',a.data.peers['strangerab-realm'])==2)
assert(a:PeerTier('strangerac-realm',a.data.peers['strangerac-realm'])==3)
assert(a:PeerTier('guildieau-realm',a.data.peers['guildieau-realm'])==1)
-- An announcement alone does not.
local sender=boot('Announcer-Realm')
a:OnMessage('RATEME',sender.payload:RatingBroadcast(target,{score=3,rev=1,date=1800000000}),'CHANNEL','Announcer-Realm',false)
assert(a.data.peers['announcer-realm'] and not a.data.peers['announcer-realm'].proven,'announcements do not prove a peer')
print('PASS: replies make proven peers; greetings and announcements do not')

-- Ranking: friends/guild, then proven, then newcomers (oldest first).
local ranked=a:RankedPeers(nil)
assert(ranked[1].tier==1 and ranked[13].tier==2 and ranked[14].tier==3,'tier order')
for i=2,#ranked do assert(ranked[i-1].tier<=ranked[i].tier) end
assert(ranked[14].key=='strangeraa-realm','oldest newcomer first among newcomers')
-- Announcement whispers go to friends/guild first.
for _,name in ipairs(a:PeerNames(nil,10)) do assert(trusted[a:Key(name)],name..' should be friend/guild') end
print('PASS: ranking and announcement whispers favour friends/guild')

-- Lookups: established peers first, about a quarter of spots for newcomers.
local pick=a:SelectQueryPeers('lookup-1',nil,a.myName,8)
local tiers={0,0,0}
for _,name in ipairs(pick) do local k=a:Key(name);local t=a:PeerTier(k,a.data.peers[k]);tiers[t]=tiers[t]+1 end
assert(#pick==8 and tiers[1]==6 and tiers[3]==2,'6 friends/guild + 2 newcomers: '..table.concat(tiers,','))
-- Different lookups start at different friends/guild (load is spread).
local other=a:SelectQueryPeers('lookup-2',nil,a.myName,8)
assert(pick[1]~=other[1] or pick[2]~=other[2],'rotation within a tier')
-- With only newcomers available, every spot is used.
RateMeDB=nil
local n=boot()
for i=1,5 do n:RememberPeer('Only'..letters(i)..'-Realm') end
assert(#n:SelectQueryPeers('x',nil,n.myName,4)==4,'newcomers fill unused spots')
print('PASS: lookups favour friends/guild and proven peers, with spots for newcomers')

-- A full list drops the worst tier first; newcomers cannot push out better peers.
RateMeDB=nil
local f=boot()
local ftrusted={}
function f:IsTrustedPeerKey(key) return ftrusted[key]==true end
for i=1,20 do local nm='Friend'..letters(i)..'-Realm';ftrusted[f:Key(nm)]=true;f:RememberPeer(nm) end
for i=1,100 do f.clock=i;f:RememberPeer('Proven'..letters(i)..'-Realm','proven') end
assert(count(f.data.peers)==120)
f.clock=1000
for i=1,10 do f:RememberPeer('Alt'..letters(i)..'-Realm','greeting') end
assert(count(f.data.peers)==120)
for k in pairs(f.data.peers) do assert(not k:find('^alt'),'a newcomer cannot push out a better peer') end
f:RememberPeer('Newproof-Realm','proven')
assert(f.data.peers['newproof-realm'] and count(f.data.peers)==120,'a proven peer replaces the oldest proven one')
assert(f.data.peers['provenaa-realm']==nil,'oldest proven peer dropped')
for i=1,20 do assert(f.data.peers['friend'..letters(i)..'-realm'],'friends/guild are never dropped') end
print('PASS: full list drops worst tier first; friends/guild never dropped')

-- Friends and guild members are read from the game's own lists.
_G.unpack=table.unpack or unpack
local function stub() return setmetatable({},{__index=function() return function() end end}) end
CreateFrame=function() return stub() end
C_FriendList={GetNumFriends=function()return 2 end,GetFriendInfoByIndex=function(i)
 return ({{name='Pal-Realm'},{name='Buddy-Other'}})[i] end}
IsInGuild=function()return true end
GetNumGuildMembers=function()return 2 end
GetGuildRosterInfo=function(i)return ({'Guildmate-Realm','Officer-Realm'})[i] end
RateMeDB=nil
local g=boot()
assert(loadfile('RateMe/Integration.lua'))('RateMe',g)
g:RefreshTrustedPeers()
assert(g:IsTrustedPeerKey('pal-realm') and g:IsTrustedPeerKey('buddy-other') and g:IsTrustedPeerKey('guildmate-realm'))
assert(not g:IsTrustedPeerKey('stranger-realm') and not g:IsTrustedPeerKey(nil))
g:RememberPeer('Pal-Realm');g:RememberPeer('Officer-Realm');g:RememberPeer('Somebody-Realm','proven');g:RememberPeer('Rando-Realm')
local summary=g:PeerSummaryText()
assert(summary:find('4 known peers: 2 friends/guild, 1 proven, 1 new',1,true),summary)
assert(summary:find('Friends/guild: Officer Realm, Pal Realm.',1,true),summary)
print('PASS: friends and guild members recognised; /rateme peers shows the tiers')
