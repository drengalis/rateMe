-- Saved community data: Recent Lookups, expiry of unverified reviews, names and dates from other players.

-- Recent Lookups and expiry of unverified reviews
do
-- Other players must not fill Recent Lookups, and unconfirmed
-- reviews must not be kept forever.
local function boot(name)
 local a={myName=name or 'Me-Realm',myGuid='Player-1-aa',myFaction='Alliance',clock=0,stamp=1800000000}
 function a:Now()return self.clock end
 function a:Stamp()return self.stamp end
 function a:CleanName(n)if type(n)~='string' or #n<2 or #n>80 or n:find('[%s|%c]')then return nil end;return n end
 function a:Key(n)local v=self:CleanName(n);return v and v:lower()end
 function a:DisplayName(n)return n end
 function a:ValidateStoredTarget(t)return t.faction=='Alliance' and t.guid~=self.myGuid end
 function a:NotifyUI()end
 function a:RefreshTooltip()end
 function a:Log()end
 function a:Debug()end
 local store=dofile('tests/load_data_addon.lua');store:Bind(a)
 dofile('tests/load_communication_addon.lua')(a)
 a:InitializeStorage()
 a.outbox={};a.counter=0;a.nextSend=0;a.inbound={}
 return a,store
end
RateMeDB=nil
C_Timer={After=function()end,NewTicker=function()end}

-- Announcements from other players are saved but never added to Recent Lookups.
local a=boot()
local sender=boot('Other-Realm')
for i=1,30 do
 local target={guid=string.format('Player-1-%04x',i),name='Made'..string.char(96+i%26+1)..string.char(97+math.floor(i/26))..'-Realm',faction='Alliance',class='MAGE'}
 local packet=sender.payload:RatingBroadcast(target,{score=1,rev=1,date=1800000000})
 a.clock=i*10 -- stay under the per-sender announcement limit
 a:OnMessage('RATEME',packet,'CHANNEL','Other-Realm',false)
end
local saved,recent=0,0
for _ in pairs(a.db.community) do saved=saved+1 end
for _ in pairs(a.data.recent) do recent=recent+1 end
assert(saved==30,'announcements are still saved: '..saved)
assert(recent==0,'announcements must not touch Recent Lookups: '..recent)
-- Players you rate yourself are still added.
local mine={guid='Player-1-beef',name='Mine-Realm',faction='Alliance',class='PRIEST'}
assert(a:SaveOwnRating(mine,4,{}))
assert(a.data.recent[mine.guid],'your own ratings are added to Recent Lookups')
print('PASS: announcements saved without filling Recent Lookups; own ratings still listed')

-- Unverified reviews older than 90 days are deleted when the data loads.
local day=86400
local now=1800000000
RateMeDB={schema=1,settingsSchema=1,authored={},settings={},ignored={},recent={},peers={},community={
 ['Player-1-0a']={guid='Player-1-0a',name='Old-Realm',faction='Alliance',votes={
  ['old-unverified']={sender='Old-Realm',score=2,rev=1,date=now-200*day,receivedAt=now-91*day,via='Relay-Realm'},
  ['new-unverified']={sender='New-Realm',score=3,rev=1,date=now-200*day,receivedAt=now-10*day,via='Relay-Realm'},
  ['old-verified']={sender='Ver-Realm',score=5,rev=1,date=now-400*day,verifiedAt=now-400*day},
  ['verified-removal']={sender='Gone-Realm',score=0,rev=2,date=now-400*day,verifiedAt=now-400*day},
 }},
 ['Player-1-0b']={guid='Player-1-0b',name='Empty-Realm',faction='Alliance',votes={
  ['only-old']={sender='Only-Realm',score=1,rev=1,date=now-120*day,receivedAt=now-100*day,via='Relay-Realm'},
 }},
 ['Player-1-0c']={guid='Player-1-0c',name='NoReceipt-Realm',faction='Alliance',votes={
  ['dated-old']={sender='Dated-Realm',score=4,rev=1,date=now-95*day},
 }},
}}
local b=boot()
local votes=b.db.community['Player-1-0a'].votes
assert(votes['old-unverified']==nil,'unverified review received 91 days ago is deleted')
assert(votes['new-unverified'],'unverified review received 10 days ago is kept')
assert(votes['old-verified'] and votes['verified-removal'],'verified reviews and removals are kept at any age')
assert(b.db.community['Player-1-0b']==nil,'a player left with no reviews is removed')
-- The claimed date is never used; a review saved without a receipt
-- time counts as received now, and expires 90 days from now.
local dated=b.db.community['Player-1-0c'].votes['dated-old']
assert(dated and dated.receivedAt==now,'without a receipt time, the review counts as received at load')
print('PASS: unverified reviews deleted after 90 days; verified kept; empty players removed')
end

-- Player names from the game and from other players
do
-- Other players cannot rename entries or inject junk names.
local function boot(name)
 local a={myName=name or 'Me-Realm',myGuid='Player-1-aa',myFaction='Alliance',clock=0}
 function a:Now()return self.clock end
 function a:Stamp()return 1800000000+math.floor(self.clock)end
 function a:CleanName(n)if type(n)~='string' or #n<2 or #n>80 or n:find('[%s|%c]')then return nil end;return n end
 function a:Key(n)local v=self:CleanName(n);return v and v:lower()end
 function a:DisplayName(n)return n end
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
local a=boot()
local plausible=a.Payload.PlausibleName

-- Names from other players must look like real character names.
for _,good in ipairs({'Kirikou-John','Barrtok-Starwind','\195\137lodie-Realm',"Thrall-Kel'Thuzad",'Bo-Realm'}) do
 assert(plausible(good)==good,'should accept '..good)
end
for _,bad in ipairs({'Name1-Realm','Name-Realm2','B-Realm','Name-R','NoRealm','A-B-C','Some_thing-Realm',
 'Abcdefghijklmnopqrstuvwxy-Realm','Name-'..string.rep('r',49),"Name'-Realm",'-Realm','Name-'}) do
 assert(plausible(bad)==nil,'should reject '..bad)
end
-- Rejected names never reach storage: a junk target name or reviewer name drops the packet.
local target={guid='Player-1-bb',name='Target-Realm',faction='Alliance',class='MAGE'}
local junk={guid='Player-1-bc',name='Buy1Gold4Cheap-Realm',faction='Alliance',class='MAGE'}
local sender=boot('Other-Realm')
a:OnMessage('RATEME',sender.payload:RatingBroadcast(junk,{score=1,rev=1,date=1800000000}),'CHANNEL','Other-Realm',false)
assert(a.db.community[junk.guid]==nil,'announcement with a junk target name is ignored')
local _,_,args=a:DecodePacket(a.payload:SharedReview('ab-1',target.guid,{sender='Spam4Ever-Realm',score=1,rev=1,date=1}),'Other-Realm')
assert(a.payload:SharedReviewFields(args)==nil,'shared review with a junk author name is ignored')
_,_,args=a:DecodePacket(a.payload:SharedLookup('ab-1',junk,1),'Other-Realm')
assert(a.payload:SharedLookupFields(args)==nil,'shared lookup with a junk target name is ignored')
print('PASS: names from other players must look like real character names')

-- Fixes 1 and 2: a name from the game always wins; other names never replace one.
local game={guid='Player-1-cc',name='Real-Name',faction='Alliance',class='PRIEST',fromGame=true}
a:RememberTarget(game)
assert(a.data.recent[game.guid].name=='Real-Name' and a.data.recent[game.guid].nameSource=='game')
a:RememberTarget({guid=game.guid,name='Fake-Name',faction='Alliance',class='ROGUE'})
assert(a.data.recent[game.guid].name=='Real-Name','a name from another player never replaces one')
assert(a.data.recent[game.guid].class=='PRIEST','nor does the class')
-- A name learned elsewhere is used only while nothing better is known, and the game replaces it.
local other={guid='Player-1-dd',name='First-Guess',faction='Alliance',class='MAGE'}
a:RememberTarget(other)
assert(a.data.recent[other.guid].name=='First-Guess' and a.data.recent[other.guid].nameSource=='network')
a:RememberTarget({guid=other.guid,name='Second-Guess',faction='Alliance'})
assert(a.data.recent[other.guid].name=='First-Guess','a second outside name does not replace the first')
a:RememberTarget({guid=other.guid,name='True-Name',faction='Alliance',class='MAGE',fromGame=true})
assert(a.data.recent[other.guid].name=='True-Name' and a.data.recent[other.guid].nameSource=='game',
 'the game name replaces an outside one')
print('PASS: game names always win; outside names never replace an existing name')

-- Own ratings save the trusted name, not one learned from someone else.
assert(a:SaveOwnRating({guid=game.guid,name='Fake-Name',faction='Alliance',class='PRIEST'},4,{}))
assert(a:GetOwnRating(game.guid).name=='Real-Name','rating saved under the game name')
local packet=a.payload:RatingBroadcast(a:GetOwnRating(game.guid),a:GetOwnRating(game.guid))
assert(packet:find('|Real-Name|',1,true) and not packet:find('Fake',1,true),'and announced with it')
assert(a:DeleteOwnRating({guid=game.guid,name='Fake-Name',faction='Alliance'}))
assert(a:GetOwnRating(game.guid).name=='Real-Name','removal keeps the game name')
local fresh={guid='Player-1-ee',name='Fresh-Name',faction='Alliance',class='MAGE',fromGame=true}
assert(a:SaveOwnRating(fresh,5,{}))
assert(a:SaveOwnRating({guid=fresh.guid,name='Later-Fake',faction='Alliance'},3,{}))
assert(a:GetOwnRating(fresh.guid).name=='Fresh-Name','re-rating keeps the earlier trusted name')
print('PASS: own ratings use the trusted name')
end

-- Rating dates
do
-- Ratings dated more than a day ahead of this client's clock are rejected.
local function boot(name)
 local a={myName=name or 'Me-Realm',myGuid='Player-1-aa',myFaction='Alliance',clock=0}
 function a:Now()return self.clock end
 function a:Stamp()return 1800000000 end
 function a:CleanName(n)if type(n)~='string' or #n<2 or #n>80 or n:find('[%s|%c]')then return nil end;return n end
 function a:Key(n)local v=self:CleanName(n);return v and v:lower()end
 function a:DisplayName(n)return n end
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
local a=boot()
local now,day=1800000000,86400

-- The shared date check used by replies, announcements and shared reviews.
local function fields(date) return a.payload:RatingFields({'R','ab-1','Player-1-bb','4','1',tostring(date),'0'}) end
assert(fields(now),'today is accepted')
assert(fields(now+day),'up to one day ahead is accepted (clock differences)')
assert(fields(now+day+1)==nil,'more than one day ahead is rejected')
assert(fields(now+365*day)==nil,'years ahead is rejected')
assert(fields(now-3650*day),'old dates are fine')

-- Announcements dated in the future are ignored.
local target={guid='Player-1-bb',name='Target-Realm',faction='Alliance',class='MAGE'}
local sender=boot('Other-Realm')
a:OnMessage('RATEME',sender.payload:RatingBroadcast(target,{score=5,rev=1,date=now+30*day}),'CHANNEL','Other-Realm',false)
assert(a.db.community[target.guid]==nil,'future-dated announcement ignored')
a:OnMessage('RATEME',sender.payload:RatingBroadcast(target,{score=5,rev=1,date=now}),'CHANNEL','Other-Realm',false)
assert(a.db.community[target.guid],'a correctly dated one is saved')

-- Shared reviews dated in the future are ignored.
local _,_,args=a:DecodePacket(a.payload:SharedReview('ab-1',target.guid,
 {sender='Author-Realm',score=1,rev=1,date=now+30*day}),'Other-Realm')
assert(a.payload:SharedReviewFields(args)==nil,'future-dated shared review ignored')
print('PASS: ratings dated more than a day ahead are rejected')
end
