-- Both player lists page at 20 after global search and newest-first sort.
unpack = table.unpack or unpack
UISpecialFrames = {}
local A = {db = {settings = {allCharacters=false},recent={}}}
local function mock(kind,name,parent)
    local o={kind=kind,name=name,parent=parent,shown=true,enabled=true,scroll=0}
    function o:SetSize(w,h) self.width,self.height=w,h end
    function o:SetWidth(w) self.width=w end
    function o:SetHeight(h) self.height=h end
    function o:ClearAllPoints() self.point=nil;self.points={} end
    function o:GetWidth() return self.width or 675 end
    function o:SetPoint(...) self.point={...};self.points=self.points or {};self.points[#self.points+1]={...} end
    function o:SetText(s) self.text=s;if self.kind=='EditBox' and self.scripts and self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
    function o:GetText() return self.text or '' end
    function o:SetJustifyH(v) self.justify=v end
    function o:SetShown(v) self.shown=v end
    function o:SetEnabled(v) self.enabled=v end
    function o:SetScrollChild(x) self.scrollChild=x end
    function o:SetVerticalScroll(v) self.scroll=v;self.scrollSetCount=(self.scrollSetCount or 0)+1 end
    function o:SetScript(event,fn) self.scripts=self.scripts or {};self.scripts[event]=fn end
    function o:CreateTexture(...) return mock('Texture',nil,self) end
    function o:CreateFontString(...) return mock('FontString',nil,self) end
    function o:Hide() self.shown=false end
    function o:Show() self.shown=true end
    function o:IsShown() return self.shown end
    function o:SetAllPoints() end
    function o:SetColorTexture() end
    function o:SetBackdrop() end
    function o:SetBackdropColor() end
    function o:SetAlpha() end
    function o:SetFrameStrata() end
    function o:SetClampedToScreen() end
    function o:SetMovable() end
    function o:EnableMouse() end
    function o:RegisterForDrag() end
    function o:SetAutoFocus() end
    function o:SetMaxLetters() end
    function o:ClearFocus() self.focus=false end
    return o
end
CreateFrame=mock
UIParent=mock('Frame','UIParent')
local chunk=assert(loadfile('RateMe/UI.lua'));chunk('RateMe',A)
local own,recent={},{}
for i=1,45 do
 own[#own+1]={name=string.format('Owner%03d-Realm',i),guid='Player-A-'..i,date=i,score=3,class='MAGE'}
end
for i=1,23 do
 recent[#recent+1]={name=string.format('Recent%03d-Realm',i),guid='Player-B-'..i,
 checked=i+100,score=4.4,count=3,fresh=true,class='DRUID'}
end
function A:ListOwn()
 local out={}
 for _,v in ipairs(own) do out[#out+1]=v end
 if self.db.settings.allCharacters then
  out[#out+1]={name='Alt-Realm',guid='Player-Z',date=90,score=5}
 end
 return out
end
function A:ListRecent() return recent end
function A:DateText(n) return tostring(n) end
function A:WindowScoreText(n) return tostring(n) end
function A:DisplayName(n) return n end
function A:OpenReviews() end
function A:OpenEditor() end
A:CreateMainWindow()
local f=A.main
f.settingsPanel=mock('Frame','settingsPanel')
A.DrawSettings=function() end -- the separate settings contract test covers this panel
A:DrawMain()
assert(f.search.point[2]==72 and f.search.width==400, 'Search should be closer to label and wider')
assert(f.searchLabel.point[1]=='RIGHT' and f.searchLabel.point[2]==f.search and f.searchLabel.point[4]==-13 and f.search.point[3]==-520)
assert(f.clearSearch.point[1]=='LEFT' and f.clearSearch.point[2]==f.search and f.clearSearch.point[4]==6 and f.clearSearch.point[5]==-1)
assert(not f.allCharacters and not f.refresh, 'List footer must not have All Characters or Refresh buttons')
assert(not f.clearSearch.enabled, 'Clear button should be disabled when search is empty')
assert(f.scroller.points[2][1]=='BOTTOMRIGHT' and f.scroller.points[2][2]==-50 and f.scroller.points[2][3]==108)
assert(f.pageIndicator.text=='Page 1 of 3' and f.status.text=='1-20 of 45 players')
assert(f.rows[1].record.name=='Owner045-Realm' and f.rows[20].record.name=='Owner026-Realm')
assert(not f.rows[21] and not f.previousPage.enabled and f.nextPage.enabled)
local function click(b)
 assert(b.enabled~=false,'A disabled button was clicked: '..tostring(b.text))
 b.scripts.OnClick(b)
end
click(f.nextPage)
assert(f.pageIndicator.text=='Page 2 of 3' and f.rows[1].record.name=='Owner025-Realm')
assert(f.status.text=='21-40 of 45 players' and f.scroller.scroll==0)
local resetCount=f.scroller.scrollSetCount
f.scroller:SetVerticalScroll(63)
A:DrawMain() -- asynchronous data redraw should not jump on the same view
assert(f.scroller.scroll==63 and f.scroller.scrollSetCount==resetCount+1)
click(f.nextPage)
assert(f.pageIndicator.text=='Page 3 of 3' and f.status.text=='41-45 of 45 players')
assert(f.rows[1].record.name=='Owner005-Realm' and f.rows[5].record.name=='Owner001-Realm')
assert(not f.rows[6].shown and not f.nextPage.enabled and f.previousPage.enabled)
click(f.previousPage);assert(f.pageIndicator.text=='Page 2 of 3' and f.scroller.scroll==0)
-- Search across the full dataset, not only the displayed page.
f.search:SetText('Owner001');f.search.scripts.OnTextChanged(f.search)
assert(f.clearSearch.enabled, 'Clear button should enable for nonempty input')
assert(f.pageIndicator.text=='Page 1 of 1' and f.status.text=='1-1 of 1 players')
assert(f.rows[1].record.name=='Owner001-Realm' and not f.rows[2].shown)
assert(not f.nextPage.enabled and not f.previousPage.enabled)
f.search:SetText('no-match');f.search.scripts.OnTextChanged(f.search)
assert(f.status.text=='0 players' and f.pageIndicator.text=='Page 1 of 1' and not f.rows[1].shown)
click(f.clearSearch)
assert(f.search:GetText()=='' and not f.clearSearch.enabled, 'X must clear the current search')
-- The Settings checkbox, tested separately, updates the same existing SavedVariable.
click(f.nextPage);click(f.nextPage)
A.db.settings.allCharacters=true
f.pages.mine=1; f.selected=nil; A:DrawMain()
assert(f.rows[1].record.name=='Alt-Realm' and f.pages.mine==1)
assert(f.status.text=='1-20 of 46 players')
-- Other tab has its own pager and uses the same search-footer location.
click(f.tabRecent)
assert(not f.allCharacters and not f.refresh and f.search.shown and f.clearSearch.shown)
assert(f.dateHeading.text=='Last checked' and f.status.text=='1-20 of 23 players')
assert(f.rows[1].record.name=='Recent023-Realm' and f.rows[20].record.name=='Recent004-Realm')
assert(not f.refresh)
click(f.nextPage)
assert(f.status.text=='21-23 of 23 players' and f.rows[1].record.name=='Recent003-Realm')
assert(not f.rows[4].shown and not f.nextPage.enabled)
-- Search resets the recent tab to page one too.
f.search:SetText('Recent001');f.search.scripts.OnTextChanged(f.search)
assert(f.status.text=='1-1 of 1 players' and f.rows[1].record.name=='Recent001-Realm')
click(f.tabSettings)
assert(not f.search.shown and not f.pageIndicator.shown and not f.previousPage.shown and not f.nextPage.shown)
assert(not f.allCharacters and not f.refresh and not f.clearSearch.shown)
print('PASS: search-only footer and clear button; Settings-only All Characters;  20-item pagination; globally filtered/sorted lists; tab/empty boundaries; scroll and settings')
