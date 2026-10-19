-- Offline UI regression: multiline input must not use single-line artwork or
-- spill text out of its viewport. Comment bytes sit directly below the field.
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
A:CreateEditorWindow()
local f=A.editor
assert(f.comment.template==nil,'Do not use InputBoxTemplate for multiline reviews')
assert(f.comment.multiline==true and f.comment.parent==f.commentScroll)
assert(f.commentScroll.parent==f.commentBox and f.commentScroll.scrollChild==f.comment)
assert(f.commentScroll.template=='UIPanelScrollFrameTemplate' and f.commentBar,'Editor must expose a standard vertical scrollbar')
assert(f.commentBar.shown and f.commentBar.parent==f.commentScroll)
assert(f.commentScroll.point[1]=='BOTTOMRIGHT' and f.commentScroll.point[2]==f.commentBox and f.commentScroll.point[4]==-33 and f.commentScroll.point[5]==8)
assert(f.comment.width==382,'Reserve enough width to prevent writing behind the scrollbar')
assert(f.commentBox.background[4]==1 and f.commentScroll.wheel)
assert(f.bytes.point[2]==f.commentBox and f.bytes.point[3]=='BOTTOMRIGHT')
assert(f.bytes.point[4]==-3 and f.bytes.point[5]==-4,'Counter must be directly under writing area')
assert(f.commentBox.point[5]==-339 and f.commentBox.height==85)
assert(f.save.point[5]==-463,'Save controls should remain below comment/counter')
f.comment:SetText('First line\nSecond line')
assert(f.comment:GetText()=='First line\nSecond line' and f.bytes.text=='22 / 160 bytes')
f.comment.scripts.OnEnterPressed(f.comment)
assert(f.comment:GetText()=='First line\nSecond line\n' and f.bytes.text=='23 / 160 bytes')
f.comment.scripts.OnCursorChanged(f.comment,0,-120,0,14)
assert(f.commentScroll.scroll>0,'Caret follows downward multiline text')
f.comment:SetText(string.rep('x',162))
assert(#f.comment:GetText()==160 and f.bytes.text=='160 / 160 bytes')
f.comment.scripts.OnEscapePressed(f.comment)
assert(f.comment.cleared and not f:IsShown())
print('PASS: multiline editor is clipped and scrollable; counter is directly below; Enter, byte cap, caret, Escape')
-- Storage should keep intentional line breaks and still strip pipes/control chars.
local S = dofile('tests/load_data_addon.lua')
local storage=assert(loadfile('RateMe/Storage.lua'));storage('RateMe', A)
assert(A:SanitizeComment('First\r\nSecond|T\9ok')=='First\nSecondT ok')
print('PASS: newline-preserving comment sanitization and WoW formatting protection')
