-- Chat: a coloured star and score before messages from rated players.
unpack = table.unpack or unpack
local filters={}
function ChatFrame_AddMessageEventFilter(event,fn) filters[event]=fn end
function CreateFrame()
 local f={}
 function f:RegisterEvent()end
 function f:SetScript()end
 return f
end
C_Timer={After=function()end,NewTicker=function()end}
function IsInInstance()return false,'none' end
local settings={ratingHighlights=true,ratingHighlightsGlow=true,ratingHighlightsBadge=false,
 ratingHighlightsPersonal=true,ratingHighlightsCommunity=true,ratingHighlightsChat=true}
local community,personal={},{}
local A={db={settings=settings},myGuid='Player-ME-1'}
function A:Now()return 0 end
function A:GetFreshCommunityScore(guid)return community[guid] end
function A:GetPersonalScore(guid)return personal[guid] end
function A:GetSummary()return nil end
function A:RefreshHighlights()end
function A:OnHighlightSettingsChanged()end
assert(loadfile('RateMe/Highlights.lua'))('RateMe',A)
A:InitializeChatStars()

local expected={'CHAT_MSG_SAY','CHAT_MSG_YELL','CHAT_MSG_WHISPER','CHAT_MSG_PARTY','CHAT_MSG_PARTY_LEADER',
 'CHAT_MSG_RAID','CHAT_MSG_RAID_LEADER','CHAT_MSG_RAID_WARNING','CHAT_MSG_GUILD','CHAT_MSG_OFFICER',
 'CHAT_MSG_CHANNEL','CHAT_MSG_INSTANCE_CHAT','CHAT_MSG_INSTANCE_CHAT_LEADER'}
for _,event in ipairs(expected) do assert(filters[event],'missing chat filter for '..event) end
assert(not filters.CHAT_MSG_WHISPER_INFORM,'own outgoing whispers are not decorated')
A:InitializeChatStars() -- idempotent
print('PASS: chat filters installed once for player chat channels')

-- Call a filter the way WoW does: (frame, event, message, author, ... guid as the 12th argument).
local function say(message,guid)
 return filters.CHAT_MSG_SAY(nil,'CHAT_MSG_SAY',message,'Author-Realm','','','','',0,0,'',0,7,guid)
end
local star='|TInterface\\AddOns\\RateMe\\Media\\StarFull.tga:0:0:0:0:64:64:0:64:0:64:'
local dot=' \194\183 '

community['Player-A-1']=4.25
local blocked,message,author=say('lfg deadmines','Player-A-1')
assert(blocked==false and author=='Author-Realm','name and other arguments pass through unchanged')
assert(message==star..'255:183:45|t|cffffb72d4.3|r'..dot..'lfg deadmines','gold star, one decimal, separator: '..tostring(message))
community['Player-A-1']=1.5
_,message=say('hi','Player-A-1')
assert(message:find('255:48:56|t',1,true) and message:find('|cffff30381.5|r',1,true),'red below 2.0: '..message)
community['Player-A-1']=3
_,message=say('hi','Player-A-1')
assert(message:find('183:198:224|t',1,true) and message:find('3.0|r'..dot..'hi',1,true),'neutral colour: '..message)
print('PASS: star colour, one-decimal score and separator before the message')

-- Personal rating is used when there is no fresh community score.
personal['Player-B-1']=5
_,message=say('hello','Player-B-1')
assert(message:find('5.0|r'..dot..'hello',1,true))
-- No score, own messages, missing GUIDs and disabled indicators leave chat untouched.
assert(say('plain','Player-C-1')==false and select(2,say('plain','Player-C-1'))==nil)
assert(say('mine',A.myGuid)==false and select(2,say('mine',A.myGuid))==nil)
assert(say('no guid',nil)==false and select(2,say('no guid',nil))==nil)
settings.ratingHighlights=false
assert(select(2,say('off','Player-A-1'))==nil,'master switch off: no stars')
settings.ratingHighlights=true;settings.ratingHighlightsCommunity=false
assert(select(2,say('community off','Player-A-1'))==nil,'community source off')
_,message=say('personal on','Player-B-1');assert(message:find('5.0',1,true),'personal source still on')
print('PASS: personal fallback; unrated, own, missing-GUID and disabled cases untouched')

-- The chat star has its own setting; turning it off leaves chat untouched.
settings.ratingHighlightsCommunity=true
assert(select(2,say('on','Player-A-1')),'stars shown with the setting on')
settings.ratingHighlightsChat=false
assert(say('off','Player-A-1')==false and select(2,say('off','Player-A-1'))==nil,'no stars with the chat setting off')
assert(select(2,say('off','Player-B-1'))==nil,'not for personal ratings either')
settings.ratingHighlightsChat=true
print('PASS: chat stars follow their own setting')
