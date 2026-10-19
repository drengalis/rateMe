-- Rate Me! v1: lightweight simulated tests of numeric badge lifecycle.
unpack = table.unpack or unpack
STANDARD_TEXT_FONT = 'Fonts\\FRIZQT__.TTF'
local objects = {}
local function frame(kind, parent)
    local f = {kind=kind,parent=parent,visible=true}
    objects[#objects+1]=f
    function f:SetSize(w,h)self.width=w;self.height=h end
    function f:GetWidth()return self.width or 120 end
    function f:GetHeight()return self.height or 14 end
    function f:EnableMouse(v)self.mouse=v end
    function f:SetFrameStrata(v)self.strata=v end
    function f:SetFrameLevel(v)self.level=v end
    function f:GetFrameLevel()return self.level or 1 end
    function f:SetPoint(...)self.point={...}end
    function f:SetAllPoints(a)self.allPoints=a end
    function f:ClearAllPoints()self.point=nil;self.allPoints=nil end
    function f:CreateTexture()return frame('Texture',self)end
    function f:CreateFontString()return frame('FontString',self)end
    function f:SetTexture(x)self.texture=x end
    function f:SetBlendMode(x)self.blend=x end
    function f:SetWidth(x)self.width=x end
    function f:SetHeight(x)self.height=x end
    function f:SetVertexColor(...)self.tint={...}end
    function f:SetJustifyH(x)self.justify=x end
    function f:SetFont(...)self.font={...}end
    function f:SetTextColor(...)self.textColor={...}end
    function f:SetShadowColor(...)self.shadowColor={...}end
    function f:SetShadowOffset(...)self.shadowOffset={...}end
    function f:SetText(x)self.text=x end
    function f:Hide()self.visible=false end
    function f:Show()self.visible=true end
    function f:IsShown()return self.visible end
    function f:IsVisible()return self.visible end
    function f:IsForbidden()return false end
    return f
end
UIParent=frame('UIParent')
function CreateFrame(kind,name,parent)return frame(kind,parent)end
local health=frame('HealthBar'); health:SetSize(110,14)
local plate=frame('Nameplate'); plate.UnitFrame=frame('UnitFrame');plate.UnitFrame.healthBar=health
local target={guid='Player-ABC-123',name='Friendly-Realm',class='MAGE',faction='Alliance'}
local selected={ratingHighlights=true,ratingHighlightsGlow=false,ratingHighlightsBadge=true,ratingHighlightsPersonal=true,ratingHighlightsCommunity=true}
local community, personal=4.34,2
local combat=false; local instance=false
function InCombatLockdown()return combat end
function IsInInstance()if instance then return true,'party' end return false,'none' end
C_NamePlate={GetNamePlateForUnit=function(unit) if unit=='nameplate1' then return plate end end,
    GetNamePlates=function()return {plate} end}
local A={db={settings=selected},myGuid='Player-ME-123',nameplateHighlights={},groupFrameHighlights={},
 pendingHighlightTargets={},passiveHighlightBudget={started=0,count=0},lastHighlightQuery=-10,MAX_PENDING=5}
function A:Now()return 0 end
function A:GetPersonalScore(guid) if guid==target.guid then return personal end end
function A:GetFreshCommunityScore(guid) if guid==target.guid then return community end end
function A:GetSummary(guid) if community and guid==target.guid then return {fresh=true,average=community,count=9} end end
function A:CaptureUnit(unit) if unit=='nameplate1' then return target end end
function A:ValidateStoredTarget(x)return x.guid==target.guid end
function A:ActiveQueries()return 0 end
function A:Query()return false end
function A:Debug()end
local chunk=assert(loadfile('RateMe/Highlights.lua'));chunk('RateMe',A)
assert(A:HighlightColor(target.guid)==nil,'glow is independently disabled')
local value,source=A:NameplateBadgeScore(target.guid)
assert(value==4.34 and source=='community')
A:OnNameplateAdded('nameplate1')
local entry=A.nameplateHighlights[plate]
assert(entry and entry.badge and entry.badge.visible,'badge created with glow off')
assert(entry.badge.width==46 and entry.badge.point[1]=='RIGHT' and entry.badge.point[2]==health and entry.badge.point[3]=='LEFT' and entry.badge.point[4]==-5)
local badge=entry.badge
local badgeStar,badgeLabel
for _,x in ipairs(objects) do
 if x.parent==badge and x.kind=='Texture' then badgeStar=x end
 if x.parent==badge and x.kind=='FontString' then badgeLabel=x end
end
assert(badgeStar and badgeLabel and badgeStar.texture:match('StarFull%.tga$'))
assert(badgeLabel.text=='4.3' and badgeStar.tint[1]==1 and badgeStar.tint[2]==0.72)
assert(badgeLabel.font[2]==11 and badgeLabel.width==40, 'Badge text must use the smaller font and narrower width')
assert(badgeLabel.point[1]=='CENTER' and badgeLabel.point[5]==-1, 'Rating number must sit slightly lower in star')
community=1.6;A:RefreshHighlights();assert(badgeLabel.text=='1.6' and badgeStar.tint[2]==0.19,'low-rated star must be red')
community=3.26;A:RefreshHighlights();assert(badgeLabel.text=='3.3' and badgeStar.tint[1]==0.72,'neutral colour')
community=nil;A:RefreshHighlights();assert(badgeLabel.text=='2.0' and badge.visible,'fallback to personal')
selected.ratingHighlightsPersonal=false;A:RefreshHighlights();assert(not badge.visible,'no score, no badge')
selected.ratingHighlightsPersonal=true;selected.ratingHighlightsBadge=false;A:RefreshHighlights();assert(not badge.visible,'badge toggle works with master still on')
selected.ratingHighlightsBadge=true;instance=true;A:RefreshHighlights();assert(not badge.visible,'badge hidden in restricted PvE instance')
instance=false;A:RefreshHighlights();assert(badge.visible)
A:OnNameplateRemoved('nameplate1');assert(not badge.visible,'badge hidden on nameplate removal')
combat=true;A:OnNameplateAdded('nameplate1');assert(entry.badge==badge,'reuse without protected creation')
print('PASS: independent nameplate badge, star texture and one-decimal text')
print('PASS: community preference, personal fallback, gold/red/neutral thresholds')
print('PASS: toggle, PvE restriction, nameplate removal and combat-safe reuse')

