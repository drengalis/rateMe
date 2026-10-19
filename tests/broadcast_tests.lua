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
local pending={}
C_Timer={After=function(_,f)pending[#pending+1]=f end}
local joined,left=0,0
JoinTemporaryChannel=function(name)assert(name=='RateMeNet');joined=joined+1 end
LeaveChannelByName=function(name)assert(name=='RateMeNet');left=left+1 end
GetChannelName=function()return 4 end
IsInGuild=function()return true end
IsInGroup=function()return false end
IsInRaid=function()return false end
local a=boot()
assert(a.db.settings.receiveRatingBroadcasts and a.db.settings.sendRatingBroadcasts)
assert(a.db.settings.lookupPeerCount==7)
assert(a:SetSetting('lookupPeerCount',100) and a:GetLookupPeerCount()==20)
assert(a:SetSetting('lookupPeerCount',-1) and a:GetLookupPeerCount()==1)
assert(not a:SetSetting('lookupPeerCount',0/0))
assert(not a:SetSetting('receiveRatingBroadcasts','false'))
local target={guid='Player-1-bb',name='Target-Realm',faction='Alliance',class='MAGE'}
a:RememberPeer('Alice-Realm')
assert(a:SaveOwnRating(target,5,'private comment'))
assert(a:SaveOwnRating(target,4,'new private comment'))
assert(#pending==1) -- rapid edits coalesce
pending[1]()
assert(#a.outbox==3) -- shared channel, guild and known peer
local packet=a.outbox[1].message
assert(packet:sub(1,4)=='B|1|' and not packet:find('private',1,true))
assert(a.outbox[1].channel=='CHANNEL' and a.outbox[1].target==4)
local decoded,canonical,args=a:DecodePacket(packet,'Me-Realm')
assert(decoded=='B')
local t,reviewer,vote=a.payload:BroadcastFields(args)
assert(t.guid==target.guid and reviewer=='Me-Realm' and vote.score==4 and vote.rev==2)
-- Receiver must use the actual event sender, not the payload's claimed author.
RateMeDB=nil
local b=boot('Other-Realm')
b:OnMessage('RATEME',packet,'CHANNEL','Mallory-Realm',false)
assert(next(b.db.community)==nil)
b:OnMessage('RATEME',packet,'CHANNEL','Me-Realm',false)
local saved=b.db.community[target.guid].votes['me-realm']
assert(saved.score==4 and b:IsCommunityReviewVerified(saved))
assert(b:GetFreshCommunityScore(target.guid)==4)
-- A later direct announcement upgrades an equal-revision unverified copy.
b.db.community[target.guid].votes['me-realm'].verifiedAt=nil
b.runtime.cache[target.guid].votes['me-realm'].verifiedAt=nil
b:OnMessage('RATEME',packet,'WHISPER','Me-Realm',false)
assert(b:IsCommunityReviewVerified(b.db.community[target.guid].votes['me-realm']))
local accepted=b.netStats.broadcastsAccepted
b:OnMessage('RATEME',packet,'GUILD','Me-Realm',false)
assert(b.netStats.broadcastsAccepted==accepted) -- overlap is not another vote
b:SetSetting('receiveRatingBroadcasts',false)
local update=packet:gsub('|4|2|','|3|3|')
b:OnMessage('RATEME',update,'CHANNEL','Me-Realm',false)
assert(b.db.community[target.guid].votes['me-realm'].rev==2)
b:SetSetting('receiveRatingBroadcasts',true)
b:OnMessage('RATEME',update,'CHANNEL','Me-Realm',true) -- logged metadata rejected
assert(b.db.community[target.guid].votes['me-realm'].rev==2)
b:OnMessage('RATEME',update,'CHANNEL','Me-Realm',false)
assert(b.db.community[target.guid].votes['me-realm'].score==3)
-- Broadcasts cannot authenticate a relayed review. Opposing faction rejected.
b:OnMessage('RATEME',update:gsub('Alliance','Horde'),'WHISPER','Me-Realm',false)
assert(b.db.community[target.guid].votes['me-realm'].score==3)
local removal=update:gsub('|3|3|','|0|4|')
b:OnMessage('RATEME',removal,'WHISPER','Me-Realm',false)
assert(b.db.community[target.guid].votes['me-realm'].score==0)
assert(b.runtime.cache[target.guid].votes['me-realm']==nil)
b:OnMessage('RATEME',packet,'CHANNEL','Me-Realm',false)
assert(b.db.community[target.guid].votes['me-realm'].score==0)
-- An in-flight older lookup cannot resurrect a broadcast deletion.
b.runtime.requests.old={target=target,guid=target.guid,votes={['me-realm']=vote},revisions={['me-realm']=2}}
b:FinishQuery('old')
assert(b.runtime.cache[target.guid].votes['me-realm']==nil)
-- Save/reload and receiver preferences persist.
b=boot('Other-Realm')
assert(b.db.community[target.guid].votes['me-realm'].rev==4)
-- Settings take effect for queued sends, not just future edits.
a.db.settings.sendRatingBroadcasts=false
local transmitted=0
C_ChatInfo={SendAddonMessage=function()transmitted=transmitted+1 end}
a:FlushMessages();assert(transmitted==0)
a.db.settings.receiveRatingBroadcasts=false
a:OnCommunicationSettingsChanged();assert(left==1)
-- If the custom route is unavailable, normal group/known-peer routes remain.
GetChannelName=function()return 0 end
local before=#a.outbox
a.db.settings.sendRatingBroadcasts=true
a:BroadcastOwnRating(a:GetOwnRating(target.guid))
assert(joined==1 and #a.outbox==before+2)
print('PASS: broadcast routes, coalescing, sender identity, settings, duplicates, tombstones, query race and unavailable channel')
