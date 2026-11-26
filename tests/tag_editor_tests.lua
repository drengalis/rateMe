-- Offline tag editor and picker regression tests.
local A = {MAX_COMMENT=160,STAR_EMPTY_TEXTURE='empty',STAR_FULL_TEXTURE='full'}
local objects={}
local function frame(kind,name,parent,template)
 local x={kind=kind,name=name,parent=parent,template=template,scripts={},shown=true,text='',scroll=0,height=0}
 objects[#objects+1]=x
 function x:SetSize(w,h) self.width=w;self.height=h end
 function x:SetWidth(w)self.width=w end
 function x:SetHeight(h)self.height=h end
 function x:GetHeight()return self.height end
 function x:SetPoint(...)self.point={...} end
 function x:ClearAllPoints()self.point=nil end
 function x:SetFrameStrata()end
 -- Window chrome added with the Blizzard frame templates and resizing.
 for _,k in ipairs({'SetToplevel','Raise','SetResizable','SetResizeBounds','SetMinResize','SetMaxResize','SetFrameLevel','SetNormalTexture','SetHighlightTexture','SetPushedTexture','SetScale','SetVertexColor','SetTexture','SetBackdropBorderColor','SetTextColor','SetWordWrap','SetJustifyV','SetObeyStepOnDrag'}) do if not x[k] then x[k]=function() end end end
 if not x.GetFrameLevel then function x:GetFrameLevel() return 1 end end
 if not x.IsResizable then function x:IsResizable() return false end end
 function x:SetClampedToScreen()end
 function x:SetMovable()end
 function x:EnableMouse()end
 function x:RegisterForDrag()end
 function x:SetScript(n,v)self.scripts[n]=v end
 function x:HookScript(n,v)local o=self.scripts[n];self.scripts[n]=function(...)if o then o(...)end;v(...)end end
 function x:Hide()self.shown=false end
 function x:Show()self.shown=true end
 function x:IsShown()return self.shown end
 function x:SetAllPoints()end
 function x:SetColorTexture(...)self.color={...} end
 function x:SetBackdrop(b)self.backdrop=b end
 function x:SetBackdropColor(...)self.background={...} end
 function x:SetBackdropBorderColor(...)self.border={...} end
 function x:SetAlpha(a)self.alpha=a end
 function x:SetText(t)self.text=t;if self.kind=='EditBox' and self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
 function x:GetText()return self.text end
 function x:SetJustifyH(v)self.justify=v end
 function x:SetFontObject(v)self.font=v end
 function x:SetTextColor(...)self.textcolor={...} end
 function x:SetTexture(t)self.texture=t end
 function x:SetTexCoord(...)self.texcoord={...} end
 function x:SetMultiLine(v)self.multiline=v end
 function x:SetMaxLetters(v)self.maxLetters=v end
 function x:SetMaxBytes(v)self.maxBytes=v end
 function x:SetAutoFocus(v)self.autofocus=v end
 function x:SetSpacing(v)self.spacing=v end
 function x:EnableMouseWheel(v)self.wheel=v end
 function x:SetScrollChild(c)self.scrollChild=c end
 function x:GetVerticalScroll()return self.scroll end
 function x:SetVerticalScroll(v)self.scroll=math.max(0,v) end
 function x:GetVerticalScrollRange()return 100 end
 function x:UpdateScrollChildRect()self.updateCalls=(self.updateCalls or 0)+1 end
 function x:SetEnabled(v)self.enabled=v end
 function x:Insert(t)self.text=self.text..t end -- WoW may not fire OnTextChanged for Insert()
 function x:ClearFocus()self.cleared=true end
 function x:SetFocus()self.focus=true end
 function x:CreateTexture()return frame('Texture',nil,self)end
 function x:CreateFontString()return frame('FontString',nil,self)end
 return x
end
function CreateFrame(kind,name,parent,template)
 local x=frame(kind,name,parent,template)
 if template=='UIPanelScrollFrameTemplate' and name then
  _G[name..'ScrollBar']=frame('Slider',name..'ScrollBar',x,'UIPanelScrollBarTemplate')
 end
 return x
end
UIParent=frame('Frame','UIParent')
UISpecialFrames={}
GameFontHighlight='highlight';ChatFontNormal='chat'
function A:UTF8SafeCut(t,n)return t:sub(1,n)end
function A:RatingNumberText(s) return string.format('%.1f',s) end
local chunk=assert(loadfile('RateMe/UI.lua'));chunk('RateMe',A)
local store=dofile('tests/load_data_addon.lua')
store:Bind(A)
A:CreateEditorWindow()
local f=A.editor
-- Class icon and class name sit on their own line under the player's name.
A:SetClassLabel(f.classText,'HUNTER',28,-82)
assert(f.classText.text=='Hunter' and f.classText.classIcon.className=='Hunter' and f.classText.classIcon.shown)
A:SetClassLabel(f.classText,nil,28,-82)
assert(f.classText.text=='' and not f.classText.classIcon.shown)
assert(not f.comment and not f.commentBox and not f.bytes)
A:SetTagSelection(f.tagControl,{1,7})
assert(f.tagControl.count.text=='2 / 3 tags')
-- Positive/Negative choices are always visible beside the rating.
local control=f.tagControl
local count=0
for _ in pairs(control.buttons)do count=count+1 end
assert(count==32,'expected 32 active tag choices, got '..count)
assert(not control.buttons[33].enabled and control.buttons[33].alpha==0.5 and control.buttons[1].alpha==1 and control.buttons[44]==nil) -- fair-looter conflict; retired tag not offered
assert(control.buttons[1].enabled and control.buttons[7].enabled) -- selected choices stay clickable
assert(control.buttons[1].isSelected and control.buttons[1].check.shown,
 'selected choice is marked')
assert(not control.buttons[2].isSelected and not control.buttons[2].check.shown)
A:ToggleSelectionTag(control,4)
assert(#control.tags==3 and not control.buttons[3].enabled,'unselected choices disable at three tags')
A:ToggleSelectionTag(control,3)
assert(#control.tags==3) -- maximum enforced even through direct callback
-- The chosen tags are stacked vertically in the left column, one per row.
assert(control.vertical and control.tagWidth==452)
for n=1,3 do
 local chip=control.chips[n]
 assert(chip.shown~=false and chip.width==452,'chip '..n..' must span the left column')
 assert(chip.point[1]=='TOPLEFT' and chip.point[2]==control and chip.point[4]==0 and chip.point[5]==-29-(n-1)*36,
  'chip '..n..' must sit on its own row')
end
control.chips[1].remove.scripts.OnClick()
assert(#control.tags==2 and control.buttons[3].enabled)
A:ToggleSelectionTag(control,7)
assert(#control.tags==1,'clicking a selected choice removes it')
A:ToggleSelectionTag(control,7)
assert(A:ReviewTagText(33):find('|cffff5959-Ninja Looter',1,true))
assert(A:ReviewTagText(1):find('|cff59ff73+Leader',1,true))
local submitted
A.SaveOwnRating=function(_,target,score,tags)submitted=A:EncodeReviewTags(tags);return true end
A.Log=function()end
A.DisplayName=function(_,n)return n or 'Target' end
f.target={guid='Player-1-bb'};f.score=5
f.save.scripts.OnClick()
assert(submitted==A:EncodeReviewTags(f.tagControl.tags))
-- The post-party editor uses the same tag control and dirty-state comparison.
A:CreatePartyReviewWindow()
local row=A:CreatePartyReviewRow(1)
assert(not row.comment and row.tagControl)
row.score=4
A:SetTagSelection(row.tagControl,{33})
A:UpdatePartyReviewRow(row)
assert(row.dirty)
row.initialScore=4;row.initialTags=A:EncodeReviewTags({33})
A:UpdatePartyReviewRow(row)
assert(not row.dirty)
print('PASS: tag editor, Positive/Negative choices, stacked tags, three-tag limit, conflicts, removal, colours, save and party dirty state')
