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
        'SetAutoFocus','SetMaxLetters','SetToplevel','Raise','SetResizable','SetResizeBounds','SetMinResize','SetMaxResize','SetFrameLevel','SetNormalTexture','SetHighlightTexture','SetPushedTexture','SetScale','SetVertexColor','SetTexture','SetBackdropBorderColor','SetTextColor','SetWordWrap','SetJustifyV','SetObeyStepOnDrag'}) do x[k]=function() end end
    function x:GetFrameLevel() return 1 end
    function x:IsResizable() return false end
    return x
end
CreateFrame=mock;UIParent=mock('Frame','UIParent')
assert(loadfile('RateMe/UI.lua'))('RateMe',A)
A:CreateMainWindow()
local f=A.main
-- The window title lives in the Blizzard titlebar (here the fallback title
-- fontstring, since the mock has no templates); there is no in-window title.
assert(f.width==770 and f.TitleText and f.TitleText.text=='Rate Me!' and not f.title)
assert(f.CloseButton, 'Standard close button missing')
assert(f.tagline.text=='Reputation earned. Reputation shared.')
-- x = 66 keeps the tagline clear of the round portrait in the top-left corner.
assert(f.tagline.point[4]==66 and f.tagline.point[5]==-48 and f.tagline.justify=='LEFT',
    'Tagline must sit right of the portrait and explicitly left-align')
-- The title/navigation and content areas have a shared horizontal rule.
assert(f.headerDivider and f.headerDivider.height==1, 'Missing header divider')
assert(f.headerDivider.points[1][1]=='TOPLEFT' and f.headerDivider.points[1][4]==29 and f.headerDivider.points[1][5]==-81)
assert(f.headerDivider.points[2][1]=='TOPRIGHT' and f.headerDivider.points[2][4]==-29)
-- Footer elements are anchored to the bottom edge so they follow resizing:
-- 59 = 565 (design height) - 506 (the original top-based offset).
assert(f.footerDivider and f.footerDivider.height==1, 'Missing list/footer divider')
assert(f.footerDivider.points[1][1]=='TOPLEFT' and f.footerDivider.points[1][3]=='BOTTOMLEFT'
    and f.footerDivider.points[1][4]==29 and f.footerDivider.points[1][5]==59)
assert(f.footerDivider.points[2][1]=='TOPRIGHT' and f.footerDivider.points[2][3]=='BOTTOMRIGHT'
    and f.footerDivider.points[2][4]==-29)
assert(f.listHeadingDivider and f.listHeadingDivider.height==1, 'Column-heading divider missing')
assert(f.listHeadingDivider.points[1][5]==-117 and f.listHeadingDivider.points[2][5]==-117,
    'Column divider must remain between headings and the list viewport')
assert(f.footerBackground and f.footerBackground.points[1][3]=='BOTTOMLEFT' and f.footerBackground.points[1][5]==59 and
    f.footerBackground.points[2][1]=='BOTTOMRIGHT' and f.footerBackground.points[2][5]==12,
    'Footer background should sit below the list and inside the frame border')
-- Tabs are right-aligned below the titlebar and chained right to left.
local tabs={f.tabMine,f.tabRecent,f.tabSettings}
assert(tabs[1].text=='My Ratings' and tabs[2].text=='Recent Lookups' and tabs[3].text=='Settings')
assert(tabs[3].point[1]=='TOPRIGHT' and tabs[3].point[2]==f and tabs[3].point[4]==-29 and tabs[3].point[5]==-38,
    'Settings tab must align with the right-hand dividers, below the titlebar')
for i=1,2 do
    assert(tabs[i].point[1]=='TOPRIGHT' and tabs[i].point[2]==tabs[i+1] and tabs[i].point[3]=='TOPLEFT'
        and tabs[i].point[4]<=-4 and tabs[i].point[5]==0, 'Tabs must chain without overlapping')
end
local settingsLeft=f.width-29-tabs[3].width
local recentLeft=settingsLeft+tabs[2].point[4]-tabs[2].width
local mineLeft=recentLeft+tabs[1].point[4]-tabs[1].width
assert(f.tagline.point[4]+f.tagline.width < mineLeft, 'Tagline and navigation overlap')
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
print('PASS: titlebar title, portrait clearance, right-aligned tabs, bottom-anchored footer and tab visibility')

