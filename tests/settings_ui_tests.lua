-- Offline UI contract test with a lightweight stand-in for WoW frame methods.
unpack = table.unpack or unpack
_G = _G or {}
local A = {db={settings={lowRatingAlerts=false,lowRatingPersonal=false,lowRatingCommunity=true,
 lowRatingPersonalThreshold=3,lowRatingThreshold=3,ratingHighlights=false,ratingHighlightsGlow=true,ratingHighlightsBadge=false,
 ratingHighlightsPersonal=false,ratingHighlightsCommunity=true,partyReviewPrompt=true,
 hideCommentsByDefault=false,minimapVisible=true,allCharacters=false}}}
local counters={alert=0,highlights=0,minimap=0}
function A:SetSetting(key,value) self.db.settings[key]=value;return true end
function A:OnAlertSettingsChanged() counters.alert=counters.alert+1 end
function A:OnHighlightSettingsChanged() counters.highlights=counters.highlights+1 end
function A:SetMinimapVisible(v) counters.minimap=counters.minimap+1;self.db.settings.minimapVisible=v end
local created={},{}
local objects={}
local function frame(kind,name,parent)
 local x={kind=kind,name=name,parent=parent,scripts={},enabled=true,shown=true,checked=false,value=0}
 objects[#objects+1]=x
 function x:SetSize(w,h) self.width=w;self.height=h end
 function x:SetWidth(w) self.width=w end
 function x:SetHeight(h) self.height=h end
 function x:SetPoint(...) self.point={...};self.points=self.points or {};self.points[#self.points+1]={...} end
 function x:SetText(t) self.text=t end
 function x:SetTextColor(...) self.textColor={...} end
 function x:SetJustifyH(t)self.justify=t end
 function x:SetJustifyV(t)self.justifyV=t end
 function x:SetBackdrop(t) self.backdrop=t end
 function x:SetBackdropColor(...)self.bgColor={...} end
 function x:SetBackdropBorderColor(...)self.borderColor={...} end
 function x:GetFrameLevel()return 1 end
 function x:SetFrameLevel(level)self.level=level end
 function x:SetColorTexture(...)self.color={...} end
 function x:SetAllPoints(...)self.allPoints={...} end
 function x:SetTexture(path)self.texture=path end
 function x:GetStringWidth()return #(self.text or "") * 7 end
 function x:SetScript(k,v)self.scripts[k]=v end
 function x:SetChecked(v)self.checked=v and true or false end
 function x:GetChecked()return self.checked end
 function x:SetEnabled(v)self.enabled=v and true or false end
 function x:SetAlpha(v)self.alpha=v end
 function x:SetShown(v)self.shown=v and true or false end
 function x:Hide()self.shown=false end
 function x:Show()self.shown=true end
 function x:GetName()return self.name end
 function x:SetValue(v) self.value=v;if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self,v) end end
 function x:GetValue()return self.value end
 function x:SetMinMaxValues(a,b)self.min=a;self.max=b end
 function x:SetValueStep(v)self.step=v end
 function x:SetObeyStepOnDrag(v)self.obey=v end
 function x:SetScrollChild(c)self.scrollChild=c end
 function x:CreateTexture(...)return frame('Texture',nil,self) end
 function x:CreateFontString(...)return frame('FontString',nil,self) end
 return x
end
function CreateFrame(kind,name,parent) return frame(kind,name,parent) end
GameTooltip={SetOwner=function(self,...)self.owner={...} end,AddLine=function(self,...)self.lines=self.lines or {};self.lines[#self.lines+1]={...} end,
 Show=function(self)self.shown=true end,Hide=function(self)self.shown=false end}
A.main=frame('Frame','RateMeMainWindow');A.main.pages={mine=3,recent=2}
local chunk=assert(loadfile('RateMe/UI.lua'))
chunk('RateMe', A)
A:CreateSettingsPanel()
local p=A.main.settingsPanel.content
assert(p.height==1285 and p.width==699)
assert(A.main.settingsPanel.scrollChild==p)
assert(p.enabled and p.alertPersonal and p.alertCommunity and p.threshold and p.personalThreshold)
assert(p.highlights and p.highlightGlow and p.highlightBadge and p.highlightPersonal and p.highlightCommunity and p.minimapVisible and p.partyReviewPrompt and p.hideCommentsByDefault and p.allCharacters and p.debug)
local cards={}
for _,o in ipairs(objects) do
 if o.parent==p and o.bgColor then cards[#cards+1]=o end
end
assert(#cards==7,'Expected seven distinct sections, got '..#cards)
local previousBottom=0
for _,card in ipairs(cards) do
 assert(card.bgColor[4]==1,'Panels must be opaque')
 assert(card.points and #card.points==2, 'Each card must have two width-defining anchors')
 assert(card.points[1][1]=='TOPLEFT' and card.points[1][4]==8)
 assert(card.points[2][1]=='TOPRIGHT' and card.points[2][4]==-8)
 local top=-card.points[1][5]
 assert(top>=previousBottom,'Section panels overlap')
 previousBottom=top+card.height
end
assert(previousBottom<=p.height,'Scroll content must contain every panel')
-- Cards follow the content width when UI scale or window dimensions change.
local before = p.width
local resized = A.main.settingsPanel.scripts.OnSizeChanged
assert(type(resized)=='function', 'Settings width handler missing')
resized(A.main.settingsPanel, 750)
assert(p.width==746 and p.width>before, 'Content did not expand with the scroll viewport')
resized(A.main.settingsPanel, 703)
assert(p.width==699)
-- Removed the former gold stripe, which appeared as an odd character in-game.
for _,o in ipairs(objects) do
 assert(not (o.kind=='Texture' and o.width==3 and o.height==25), 'Stray header accent remains')
end
A:DrawSettings()
assert(p.enabled:GetChecked()==false and p.alertPersonal.enabled==false and p.personalThreshold.enabled==false)
assert(p.highlights:GetChecked()==false and p.highlightGlow.enabled==false and p.highlightBadge.enabled==false and p.highlightPersonal.enabled==false)
assert(p.partyReviewPrompt:GetChecked() and p.minimapVisible:GetChecked() and not p.allCharacters:GetChecked() and not p.debug:GetChecked())
p.debug:SetChecked(true);p.debug.scripts.OnClick(p.debug)
assert(A.db.settings.debug==true and p.debug:GetChecked())
p.debug:SetChecked(false);p.debug.scripts.OnClick(p.debug)
assert(A.db.settings.debug==false and not p.debug:GetChecked())
p.allCharacters:SetChecked(true);p.allCharacters.scripts.OnClick(p.allCharacters)
assert(A.db.settings.allCharacters and A.main.pages.mine==1, 'All Characters setting did not apply and reset My Ratings pagination')
p.allCharacters:SetChecked(false);p.allCharacters.scripts.OnClick(p.allCharacters)
assert(not A.db.settings.allCharacters, 'All Characters setting did not persist the off state')
-- Master enable, source enable, threshold change, and disabled state update.
p.enabled:SetChecked(true);p.enabled.scripts.OnClick(p.enabled)
assert(A.db.settings.lowRatingAlerts and p.alertPersonal.enabled and p.alertCommunity.enabled)
p.alertPersonal:SetChecked(true);p.alertPersonal.scripts.OnClick(p.alertPersonal)
assert(A.db.settings.lowRatingPersonal and p.personalThreshold.enabled)
p.personalThreshold:SetValue(2.6)
assert(A.db.settings.lowRatingPersonalThreshold==2.5 and p.personalThresholdValue.text=='2.5 stars or lower')
p.highlights:SetChecked(true);p.highlights.scripts.OnClick(p.highlights)
assert(p.highlightGlow.enabled and p.highlightBadge.enabled and p.highlightPersonal.enabled and p.highlightCommunity.enabled)
p.highlightBadge:SetChecked(true);p.highlightBadge.scripts.OnClick(p.highlightBadge)
assert(A.db.settings.ratingHighlightsBadge and counters.highlights>=2)
p.highlightGlow:SetChecked(false);p.highlightGlow.scripts.OnClick(p.highlightGlow)
assert(A.db.settings.ratingHighlightsGlow==false and p.highlightPersonal.enabled)
p.highlightBadge:SetChecked(false);p.highlightBadge.scripts.OnClick(p.highlightBadge)
assert(p.highlightPersonal.enabled==false and p.highlightCommunity.enabled==false)
p.minimapVisible:SetChecked(false);p.minimapVisible.scripts.OnClick(p.minimapVisible)
assert(not A.db.settings.minimapVisible)
p.hideCommentsByDefault:SetChecked(true);p.hideCommentsByDefault.scripts.OnClick(p.hideCommentsByDefault)
assert(A.db.settings.hideCommentsByDefault)
assert(counters.alert>=3 and counters.highlights>=1)
local helpIcons={}
local headings={['My Ratings']=true,['Group Rating Alerts']=true,['Player Rating Highlights']=true,
 ['Post-Party Ratings']=true,['Comment Safety']=true,['Minimap Button']=true}
local headingCount=0
for _,o in ipairs(objects) do
 if o.kind=='Button' and o.width==14 and o.height==14 and o.scripts.OnEnter then helpIcons[#helpIcons+1]=o end
 if headings[o.text] then headingCount=headingCount+1 end
 assert(o.text~='Preferences', 'No redundant Preferences heading')
end
assert(#helpIcons==0, 'Settings must contain no information icons')
assert(headingCount==6, 'Exactly six section headings')
-- The previous explanatory subtitles were removed; hint text below specific controls and the colour legend remain.
for _,unwanted in ipairs({'Warn when someone joining your group has a low rating.',
 'Gold for 4.0+; red below 2.0. No glow for other scores.',
 'Review teammates after a normal party ends (never a raid).',
 "Choose when other players' written comments become visible.",
 'Open Rate Me! quickly using the draggable minimap star.'}) do
 for _,o in ipairs(objects) do assert(o.text~=unwanted, 'Unexpected section subtitle: '..unwanted) end
end
print('PASS: six full-width responsive opaque panels, no stray header accents, help icons or subtitles')
print('PASS: controls and defaults; dependent dimming; callbacks; threshold rounding; unchanged callbacks')
