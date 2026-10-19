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
 function x:SetClampedToScreen()end
 function x:SetMovable()end
 function x:EnableMouse()end
 function x:RegisterForDrag()end
 function x:SetScript(n,v)self.scripts[n]=v end
 function x:Hide()self.shown=false end
 function x:Show()self.shown=true end
 function x:IsShown()return self.shown end
 function x:SetAllPoints()end
 function x:SetColorTexture(...)self.color={...} end
 function x:SetBackdrop(b)self.backdrop=b end
 function x:SetBackdropColor(...)self.background={...} end
 function x:SetBackdropBorderColor(...)self.border={...} end
 function x:SetAlpha()end
 function x:SetText(t)self.text=t;if self.kind=='EditBox' and self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
 function x:GetText()return self.text end
 function x:SetJustifyH(v)self.justify=v end
 function x:SetFontObject(v)self.font=v end
 function x:SetTextColor(...)self.textcolor={...} end
 function x:SetTexture(t)self.texture=t end
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
local chunk=assert(loadfile('RateMe/UI.lua'));chunk('RateMe',A)
local store=dofile('tests/load_data_addon.lua')
store:Bind(A)
A:CreateEditorWindow()
local f=A.editor
assert(not f.comment and not f.commentBox and not f.bytes)
A:SetTagSelection(f.tagControl,{1,7})
assert(f.tagControl.count.text=='2 / 3 tags')
A:OpenTagPicker(f.tagControl)
local picker=A.tagPicker
local count=0
for _ in pairs(picker.buttons)do count=count+1 end
assert(count==24)
assert(not picker.buttons[33].enabled and not picker.buttons[44].enabled) -- fair-looter conflicts
A:TogglePickerTag(4)
assert(#f.tagControl.tags==3 and not f.tagControl.add.enabled)
A:TogglePickerTag(3)
assert(#f.tagControl.tags==3) -- maximum enforced even through direct callback
f.tagControl.chips[1].scripts.OnClick()
assert(#f.tagControl.tags==2 and f.tagControl.add.enabled)
assert(A:ReviewTagText(33):find('|cffff5959-Ninja Looter',1,true))
assert(A:ReviewTagText(1):find('|cff59ff73+Leader',1,true))
local submitted
A.SaveOwnRating=function(_,target,score,tags)submitted=A:EncodeReviewTags(tags);return true end
A.Log=function()end
A.DisplayName=function(_,n)return n or 'Target' end
f.target={guid='Player-1-bb'};f.score=5
f.save.scripts.OnClick()
assert(submitted==A:EncodeReviewTags(f.tagControl.tags))
-- The post-party editor uses the same picker, tags and dirty-state comparison.
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
print('PASS: tag editor, split picker, three-tag limit, conflicts, removal, colours, save and party dirty state')
