local root=''
local frames,tickers,delayed={},{},{}
function CreateFrame()
 local f={events={}}
 function f:RegisterEvent(e)self.events[e]=true end
 function f:SetScript(e,fn)self[e]=fn end
 frames[#frames+1]=f
 return f
end
C_Timer={NewTicker=function(_,fn)tickers[#tickers+1]=fn end,After=function(_,fn)delayed[#delayed+1]=fn end}
local registered
C_ChatInfo={RegisterAddonMessagePrefix=function(p)registered=p;return true end,SendAddonMessage=function()error('unexpected transmission during load')end}
local function toc(folder,name)
 local ns={}
 for line in io.lines(root..folder..'/'..name..'.toc') do
  if line:match('%.lua$') then assert(loadfile(root..folder..'/'..line))(folder,ns) end
 end
 return ns
end
local data=toc('RateMeData','RateMeData')
local communication=toc('RateMeCommunication','RateMeCommunication')
assert(#frames==0 and #tickers==0 and #delayed==0) -- companion alone is dormant
local a=toc('RateMe','RateMe')
assert(a.communication==communication and a.payload.owner==a)
assert(a.Query==communication.API.Query and a.DebugPacket==communication.API.DebugPacket)
assert(a.SaveCommunityRating==data.API.SaveCommunityRating)
assert(a.prefix=='RATEME' and a.protocol=='1' and a.version=='1')
assert(a:EncodePacket('R',{'ab','Player-1-ab',5,1,100,0})=='R|ab|Player-1-ab|5|1|100|0')
local tag,canonical,args=a:DecodePacket('R|ab|Player-1-ab|5|1|100|0','Alice')
assert(tag=='R' and args[4]=='5')
communication:Bind(a)
assert(a.payload.owner==a)
a:InitializeNetwork()
assert(registered=='RATEME' and a.netFrame.events.CHAT_MSG_ADDON)
local rx,discovery,groups=0,0,0
function a:OnMessage(prefix,message,channel,sender,logged)
 assert(prefix=='RATEME' and sender=='Alice' and logged==false);rx=rx+1
end
function a:Discovery()discovery=discovery+1 end
function a:OnGroupRosterUpdate()groups=groups+1 end
a.netFrame.OnEvent(a.netFrame,'CHAT_MSG_ADDON','RATEME','test','WHISPER','Alice')
a.netFrame.OnEvent(a.netFrame,'GROUP_ROSTER_UPDATE')
assert(rx==1 and discovery==1 and groups==1)
-- Alternate manifests declare the same files and dependencies.
for _,folder in ipairs({'RateMe','RateMeData','RateMeCommunication'}) do
 local function read(name)local f=assert(io.open(root..folder..'/'..name));local s=f:read('*a');f:close();return s end
 assert(read(folder..'.toc')==read(folder..'_Camelot.toc'))
end
print('PASS: three-addon TOC loading, dormant companion, binding, protocol-1 payload and event routing')
