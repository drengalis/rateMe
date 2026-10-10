-- Main-window tabs belong in the title row, away from the title and close button.
unpack = table.unpack or unpack
UISpecialFrames = {}
local A = {db={settings={allCharacters=false}}}
local function mock(kind,name,parent)
    local x={kind=kind,name=name,parent=parent,shown=true}
    function x:SetSize(w,h) self.width,self.height=w,h end
    function x:SetWidth(w) self.width=w end
    function x:SetHeight(h) self.height=h end
    function x:ClearAllPoints() self.point=nil;self.points={} end
    function x:GetWidth() return self.width or 675 end
    function x:SetPoint(...) self.point={...};self.points=self.points or {};self.points[#self.points+1]={...} end
    function x:SetText(v) self.text=v end
    function x:GetText() return self.text or '' end
    function x:SetJustifyH(v) self.justify=v end
    function x:SetShown(v) self.shown=v end
    function x:SetEnabled(v) self.enabled=v end
    function x:SetScrollChild(v) self.scrollChild=v end
    function x:SetScript(key,fn) self.scripts=self.scripts or {};self.scripts[key]=fn end
    function x:CreateTexture(...) return mock('Texture',nil,self) end
    function x:CreateFontString(...) return mock('FontString',nil,self) end
    function x:Hide() self.shown=false end
    function x:Show() self.shown=true end
    function x:IsShown() return self.shown end
    for _,k in ipairs({'SetAllPoints','SetColorTexture','SetBackdrop','SetBackdropColor','SetAlpha',
        'SetFrameStrata','SetClampedToScreen','SetMovable','EnableMouse','RegisterForDrag',
        'SetAutoFocus','SetMaxLetters'}) do x[k]=function() end end
    return x
end
CreateFrame=mock;UIParent=mock('Frame','UIParent')
assert(loadfile('RateMe/UI.lua'))('RateMe',A)
A:CreateMainWindow()
local f=A.main
assert(f.width==770 and f.title.text=='Rate Me!' and f.tagline.text=='Reputation earned. Reputation shared.')
assert(f.title.point[4]==26 and f.tagline.point[4]==26 and f.tagline.point[5]<f.title.point[5])
assert(f.title.justify=='LEFT' and f.tagline.justify=='LEFT', 'Both title and tagline must explicitly left-align regardless of fontstring width')
-- The title/navigation and content areas have a shared horizontal rule.
assert(f.headerDivider and f.headerDivider.height==1, 'Missing header divider')
assert(f.headerDivider.points[1][1]=='TOPLEFT' and f.headerDivider.points[1][4]==29 and f.headerDivider.points[1][5]==-81)
assert(f.headerDivider.points[2][1]=='TOPRIGHT' and f.headerDivider.points[2][4]==-29)
assert(f.footerDivider and f.footerDivider.height==1, 'Missing list/footer divider')
assert(f.footerDivider.points[1][1]=='TOPLEFT' and f.footerDivider.points[1][4]==29 and f.footerDivider.points[1][5]==-506)
assert(f.footerDivider.points[2][1]=='TOPRIGHT' and f.footerDivider.points[2][4]==-29)
assert(f.listHeadingDivider and f.listHeadingDivider.height==1, 'Column-heading divider missing')
assert(f.listHeadingDivider.points[1][5]==-117 and f.listHeadingDivider.points[2][5]==-117,
    'Column divider must remain between headings and the list viewport')
assert(f.footerBackground and f.footerBackground.points[1][5]==-506 and
    f.footerBackground.points[2][1]=='BOTTOMRIGHT' and f.footerBackground.points[2][5]==12,
    'Footer background should sit below the list and inside the frame border')
local tabs={f.tabMine,f.tabRecent,f.tabSettings}
assert(tabs[1].text=='My Ratings' and tabs[2].text=='Recent Lookups' and tabs[3].text=='Settings')
for i,tab in ipairs(tabs) do
    assert(tab.point[1]=='TOPLEFT' and tab.point[5]==-19, 'Tab not in title row')
    assert(tab.point[4]>=350, 'Navigation must be at the upper right')
    if i>1 then
        assert(tabs[i-1].point[4]+tabs[i-1].width+4<=tab.point[4], 'Tabs overlap')
    end
end
assert(tabs[3].point[4]+tabs[3].width<=720, 'Last tab intrudes on close button')
assert(f.title.point[4]+f.title.width < tabs[1].point[4], 'Title and tabs overlap')
assert(f.tagline.point[4]+f.tagline.width < tabs[1].point[4], 'Tagline and navigation overlap')
f.settingsPanel=mock('Frame','settings')
A.DrawSettings=function() end
A.ListOwn=function() return {} end;A.ListRecent=function() return {} end
A:DrawMain();assert(f.tab=='mine' and not f.tabMine.enabled)
assert(f.footerDivider.shown, 'Divider should show on My Ratings')
assert(f.footerBackground.shown and f.listHeadingDivider.shown,
    'Footer panel and column rule should show on My Ratings')
for _,pair in ipairs({{f.tabRecent,'recent'},{f.tabSettings,'settings'},{f.tabMine,'mine'}}) do
    pair[1].scripts.OnClick(pair[1]);assert(f.tab==pair[2] and not pair[1].enabled)
    assert(f.footerDivider.shown==(f.tab~='settings'), 'Footer divider should only show on lists')
    assert(f.footerBackground.shown==(f.tab~='settings') and
        f.listHeadingDivider.shown==(f.tab~='settings'),
        'Settings must not display a list-only column rule or footer panel')
end
print('PASS: title-bar layout, section/column dividers, footer background, tab visibility and close clearance')
