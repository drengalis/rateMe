local function widget()
 local t={scripts={}}
 return setmetatable(t,{__index=function(_,k)
  if k=='CreateTexture' or k=='CreateFontString' then return function()return widget()end end
  if k=='SetScript' then return function(self,event,fn)self.scripts[event]=fn end end
  if k=='SetText' then return function(self,text)self.text=text end end
  return function()end
 end})
end
CreateFrame=function()return widget()end
GameTooltip=widget()
GameTooltip.lines={}
function GameTooltip:AddLine(text)table.insert(self.lines,text)end
local store={}
assert(loadfile('RateMeData/Community.lua'))('RateMeData',{API=store})
assert(loadfile('RateMeData/Tags.lua'))('RateMeData',{API=store})
local a={IsCommunityReviewVerified=store.IsCommunityReviewVerified,myName='Me',db={ignored={}},runtime={cache={}}}
for k,v in pairs(store)do if a[k]==nil then a[k]=v end end
function a:Key(n)return n:lower()end
function a:DisplayName(n)return n end
function a:DateText(n)return 'LOCAL '..tostring(n)..' PM' end
function a:GetSummary()return {count=1,freshCount=0,cachedCount=1}end
function a:ScoreText()return '5' end
function a:WindowScoreText()return '5' end
function a:ReviewCommentText()return 'Comment hidden','Show'end
function a:GetCommentReportEvidence()return nil end
assert(loadfile('RateMe/UI.lua'))('RateMe',a)
function a:ScoreText()return '5' end
function a:WindowScoreText()return '5' end
function a:DateText(n)return 'LOCAL '..tostring(n)..' PM' end
a.reviews={target={guid='Player-target',name='Target'},rows={},content=widget(),targetText=widget(),ratingText=widget(),status=widget()}
local vote={sender='Alice',score=5,date=100,verifiedAt=200}
a.runtime.cache['Player-target']={votes={alice=vote}}
a:DrawReviews()
local row=a.reviews.rows[1]
assert(row.verificationText.text=='Verified author')
row.verification.scripts.OnEnter(row.verification)
assert(GameTooltip.lines[3]=='Last verified: LOCAL 200 PM')
vote.verifiedAt=nil
a:DrawReviews()
assert(row.verificationText.text=='Unverified author')
vote.via='Relay';vote.receivedAt=300
a:DrawReviews()
assert(row.verificationText.text=='Peer supplied' and row.nameText.text=='Alice')
GameTooltip.lines={}
row.verification.scripts.OnEnter(row.verification)
assert(GameTooltip.lines[1]=='Peer supplied' and GameTooltip.lines[2]:find('Relay',1,true))
a.runtime.cache['Player-target'].votes={me={sender='Me',score=5,date=100}}
a:DrawReviews()
assert(row.verificationText.text=='Your review')
print('PASS: verified/cached, unverified, own-review UI labels and verification tooltip')
