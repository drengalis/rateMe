-- Main-list headings must use the same horizontal bounds as their row fields.
unpack = table.unpack or unpack
local A = { db = { settings = {allCharacters = false} } }
UISpecialFrames = {}
local function mock(kind, name, parent)
    local obj = {kind=kind,name=name,parent=parent,shown=true}
    function obj:SetSize(w,h) self.width,self.height=w,h end
    function obj:SetWidth(w) self.width=w end
    function obj:SetHeight(h) self.height=h end
    function obj:ClearAllPoints() self.point=nil;self.points={} end
    function obj:GetWidth() return self.width or 675 end
    function obj:SetPoint(...) self.point={...}; self.points=self.points or {}; self.points[#self.points+1]={...} end
    function obj:SetText(s) self.text=s end
    function obj:GetText() return self.text or "" end
    function obj:SetJustifyH(v) self.justify=v end
    function obj:SetShown(v) self.shown=v end
    function obj:SetEnabled(v) self.enabled=v end
    function obj:SetScrollChild(x) self.scrollChild=x end
    function obj:SetScript(event,fn) self.scripts=self.scripts or {};self.scripts[event]=fn end
    function obj:CreateTexture(...) return mock("Texture", nil, self) end
    function obj:CreateFontString(...) return mock("FontString", nil, self) end
    function obj:Hide() self.shown=false end
    function obj:Show() self.shown=true end
    function obj:IsShown() return self.shown end
    function obj:SetAllPoints() end
    function obj:SetColorTexture() end
    function obj:SetBackdrop() end
    function obj:SetBackdropColor() end
    function obj:SetAlpha() end
    function obj:SetFrameStrata() end
    function obj:SetClampedToScreen() end
    function obj:SetMovable() end
    function obj:EnableMouse() end
    function obj:RegisterForDrag() end
    function obj:SetAutoFocus() end
    function obj:SetMaxLetters() end
    return obj
end
function CreateFrame(kind,name,parent) return mock(kind,name,parent) end
UIParent=mock('Frame','UIParent')
local chunk=assert(loadfile('RateMe/UI.lua'))
chunk('RateMe',A)
A:CreateMainWindow()
local f=A.main
local row=A:CreateMainRow(1)
local x=assert(f.scroller.points[1][2], 'scroll viewport x missing')
local columns={
    {header=f.playerHeading,field=row.nameText},
    {header=f.ratingHeading,field=row.scoreText},
    {header=f.dateHeading,field=row.dateText},
}
for _,c in ipairs(columns) do
    assert(c.header.justify=='RIGHT' and c.field.justify=='RIGHT')
    assert(c.header.point[4]==c.field.point[4]+x,
      'heading left coordinate differs from row field: '..tostring(c.header.text))
    assert(c.header.width==c.field.width,
      'heading width differs from row field: '..tostring(c.header.text))
    assert(c.header.point[4]+c.header.width==x+c.field.point[4]+c.field.width)
end
assert(row.subText.point[4]==row.nameText.point[4] and row.subText.width==row.nameText.width,
    'player name and class alignment differs')
-- Both tabs reuse the same row layout; date heading changes only its wording.
A.DateText=function(_,n) return tostring(n) end
A.WindowScoreText=function(_,n) return tostring(n) end
A.DisplayName=function(_,n) return n end
A.ListOwn=function() return {{name='One-Realm',guid='Player-abc-1',date=12,score=4}} end
A.ListRecent=function() return {{name='Two-Realm',guid='Player-abc-2',checked=14,score=3,count=2,fresh=true}} end
f.settingsPanel=mock('Frame','settingsPanel')
A:DrawMain()
assert(f.dateHeading.text=='Date rated' and f.rows[1].record.guid=='Player-abc-1')
f.tab='recent'; A:DrawMain()
assert(f.dateHeading.text=='Last checked' and f.rows[1].record.guid=='Player-abc-2')
for _,c in ipairs(columns) do
    assert(c.header.point[4]==c.field.point[4]+x and c.header.width==c.field.width)
end
print('PASS: both player lists have right-aligned headings matching name, score and date cells')

