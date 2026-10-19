-- Readable activity logging: no packet body or written review text in chat.
local messages = {}
DEFAULT_CHAT_FRAME = {AddMessage = function(_, message) messages[#messages + 1] = message end}
function CreateFrame() return {RegisterEvent = function() end, SetScript = function() end} end
local A = {db = {settings = {debug = false}, peers = {}, ignored = {}}, myName = 'Tester-Realm'}
assert(loadfile('RateMe/Core.lua'))('RateMe', A)
local S = dofile('tests/load_data_addon.lua')
assert(loadfile('RateMe/Storage.lua'))('RateMe', A)
assert(loadfile('RateMe/Payload.lua'))('RateMe', A)
assert(loadfile('RateMe/Network.lua'))('RateMe', A)
local function joined() return table.concat(messages, '\n') end
local function contains(s) assert(joined():find(s,1,true), 'Expected activity text: ' .. s .. '\n' .. joined()) end
A:DebugPacket('RX','C|id|guid|1|private review text','WHISPER','Peer-Realm')
assert(#messages == 0, 'disabled activity must not print')
A.db.settings.debug = true
A:DebugPacket('TX','Q|id|Player-1-AB|Peer-Realm|0','WHISPER','Peer-Realm')
A:DebugPacket('RX','R|id|guid|5|1|100|0','WHISPER','Peer-Realm')
A:DebugPacket('RX','C|id|guid|1|private review text','WHISPER','Peer-Realm')
A:DebugPacket('RX','X|2|private-codec-body','WHISPER','Peer-Realm')
A:DebugPacket('DROP/queue','Q|id|guid|Peer|0','WHISPER','Peer-Realm')
A:DebugPacket('RETRY/throttled','Q|id|guid|Peer|0','WHISPER','Peer-Realm')
A:DebugPacket('IGNORE/invalid-or-unsupported','X|27|private-codec-body','WHISPER','Peer-Realm')
contains('Sent a rating lookup request to Peer Realm (direct message)')
contains('Received a rating reply from Peer Realm (direct message)')
contains('Received a written review from Peer Realm')
contains('Received a new-format addon message (format 2; contents hidden) from Peer Realm')
contains('outgoing message queue is full')
contains('The game is limiting addon messages')
contains('its format was invalid or unsupported')
assert(not joined():find('private review text',1,true))
assert(not joined():find('private-codec-body',1,true))
assert(not joined():find('TX Q',1,true) and not joined():find('RX R',1,true))
local sends = {}
C_ChatInfo = {SendAddonMessage = function(prefix,msg,channel,target)
    sends[#sends+1] = {prefix,msg,channel,target}; return true
end}
A.outbox={}; A.netStats={}; A.Now=function()return 100 end; A.nextSend=0
assert(A:QueueSend('Q|id|Player-1-AB|Peer-Realm|0','WHISPER','Peer-Realm'))
A:FlushMessages()
assert(sends[1][1]=='RATEME' and #A.outbox==0)
contains('Sent a rating lookup request to Peer Realm')
-- Saving a rating prints a readable notice but never broadcasts anything itself.
A.myFaction='Alliance'; A.myGuid='Player-1-FF'; A.Stamp=function()return 1792368000 end
A.ValidateStoredTarget=function()return true end; A.RememberTarget=function()end
A.NotifyUI=function()end; A.OwnRatings=function()return A.db.authored end
A.db.authored={}
assert(A:SaveOwnRating({guid='Player-1-CC',name='Target-Realm',faction='Alliance'},5,'private review text'))
contains('Saved your rating for Target Realm: 5 out of 5 stars (update 1)')
assert(#sends==1 and not joined():find('private review text',1,true))
assert(A:DeleteOwnRating({guid='Player-1-CC',name='Target-Realm',faction='Alliance'}))
contains('Removed your rating for Target Realm (update 2)')
assert(#sends==1)
local ui=assert(io.open('RateMe/UI.lua','r')):read('*a')
assert(ui:find('local diagnostics = section(',1,true))
assert(ui:find('p.debug:SetChecked(settings.debug)',1,true))
local integration=assert(io.open('RateMe/Integration.lua','r')):read('*a')
assert(integration:find('A:DrawSettings() -- Keep the Settings checkbox synchronized',1,true))
assert(A.SETTINGS_SCHEMA_VERSION==1 and A.protocol=='1' and A.prefix=='RATEME')
print('PASS: readable activity messages, redaction, transports and settings')
