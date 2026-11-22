-- Window chrome, remembered window placement, Reset to Default and the
-- remove-rating confirmation, with a lightweight stand-in for WoW frames.
unpack = table.unpack or unpack
UISpecialFrames = {}
STANDARD_TEXT_FONT = 'Fonts\\FRIZQT__.TTF'
CANCEL = 'Cancel'
local popups = {}
StaticPopupDialogs = {}
function StaticPopup_Show(name, ...) popups[#popups+1] = {name=name, args={...}} end
function InCombatLockdown() return false end
C_Timer = {After=function() end, NewTicker=function() end}

local function frame(kind, name, parent, template)
    local x = {kind=kind, name=name, parent=parent, template=template, scripts={}, shown=true,
        checked=false, value=0, scale=1, level=1, width=0, height=0}
    function x:SetSize(w, h) self.width, self.height = w, h end
    function x:SetWidth(w) self.width = w end
    function x:SetHeight(h) self.height = h end
    function x:GetWidth() return self.width end
    function x:GetHeight() return self.height end
    function x:SetScale(s) self.scale = s end
    function x:GetScale() return self.scale end
    function x:ClearAllPoints() self.point = nil end
    function x:SetPoint(...) self.point = {...} end
    function x:GetLeft() return self.left end
    function x:GetTop() return self.top end
    function x:SetResizable(v) self.resizable = v end
    function x:IsResizable() return self.resizable == true end
    function x:SetResizeBounds(...) self.bounds = {...} end
    function x:SetFrameStrata(v) self.strata = v end
    function x:GetFrameStrata() return self.strata or 'MEDIUM' end
    function x:SetFrameLevel(v) self.level = v end
    function x:GetFrameLevel() return self.level end
    function x:SetToplevel(v) self.toplevel = v end
    function x:Raise() self.raised = (self.raised or 0) + 1 end
    function x:StartSizing(point) self.sizing = point end
    function x:StopMovingOrSizing() self.sizing = nil end
    function x:SetScript(k, fn) self.scripts[k] = fn end
    function x:GetName() return self.name end
    function x:SetText(t) self.text = t end
    function x:GetText() return self.text or '' end
    function x:GetStringWidth() return #(self.text or '') * 7 end
    function x:GetStringHeight() return 14 end
    function x:SetChecked(v) self.checked = v and true or false end
    function x:GetChecked() return self.checked end
    function x:SetEnabled(v) self.enabled = v and true or false end
    function x:SetValue(v) self.value = v; if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end end
    function x:GetValue() return self.value end
    function x:IsShown() return self.shown end
    function x:Show()
        if not self.shown then self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
    end
    function x:Hide()
        if self.shown then self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
    end
    function x:SetShown(v) if v then self:Show() else self:Hide() end end
    function x:CreateTexture() return frame('Texture', nil, self) end
    function x:CreateFontString() return frame('FontString', nil, self) end
    -- Other setters (textures, fonts, backdrops, colours) are accepted and ignored.
    -- Only method-style names: real fields such as CloseButton must stay nil.
    return setmetatable(x, {__index=function(_, key)
        if type(key) == 'string' and (key:match('^Set') or key:match('^Enable') or key:match('^Register')
            or key:match('^Disable') or key == 'UpdateScrollChildRect') then
            return function() end
        end
    end})
end
function CreateFrame(kind, name, parent, template)
    local f = frame(kind, name, parent, template)
    if name then _G[name] = f end
    return f
end
UIParent = frame('Frame', 'UIParent')
UIParent.width, UIParent.height = 1920, 1080
GameTooltip = frame('GameTooltip', 'GameTooltip')

-- Real settings storage and defaults from RateMeData.
local A = {myName='Me-Realm', myGuid='Player-1-aa', myFaction='Alliance', protocol='1'}
function A:Now() return 0 end
function A:Stamp() return 1800000000 end
function A:Key(n) return type(n) == 'string' and n:lower() or nil end
function A:DisplayName(n) return (n:gsub('%-', ' ')) end
function A:ValidateStoredTarget(t) return t.faction == 'Alliance' and t.guid ~= self.myGuid end
function A:CleanName(n) return type(n) == 'string' and n or nil end
function A:RestoreCommunityLookups() end
local logs = {}
function A:Log(m) logs[#logs+1] = m end
local counters = {alert=0, highlights=0, communication=0, minimap=0}
function A:OnAlertSettingsChanged() counters.alert = counters.alert + 1 end
function A:OnHighlightSettingsChanged() counters.highlights = counters.highlights + 1 end
function A:OnCommunicationSettingsChanged() counters.communication = counters.communication + 1 end
RateMeDB = nil
local store = dofile('tests/load_data_addon.lua')
store:Bind(A)
A:InitializeStorage()
assert(loadfile('RateMe/UI.lua'))('RateMe', A)
-- UI.lua defines the real minimap functions; replace them after loading.
function A:PositionMinimapButton() counters.minimap = counters.minimap + 1 end
function A:SetMinimapVisible(v) self.db.settings.minimapVisible = v end
A:CreateMainWindow()
A:CreateSettingsPanel()
A:CreateEditorWindow()
local main, editor = A.main, A.editor

-- Chrome: the game's normal window layer, top-level, standard close button.
for _, f in ipairs({main, editor}) do
    assert(f.strata == 'MEDIUM' and f.toplevel == true, 'windows use the MEDIUM layer and come to the front on click')
    assert(f.CloseButton and f.CloseButton.scripts.OnClick, 'close button')
end
main:Show()
assert(main.raised and main.raised >= 1, 'a window comes to the front when it opens')
main.CloseButton.scripts.OnClick(); assert(not main:IsShown(), 'X hides the window')
assert(main.resizable and main.bounds[1] == 770 and main.bounds[2] == 420, 'main window resizable from its design width')
assert(not editor.resizable, 'rating window keeps a fixed size')
print('PASS: MEDIUM layer, top-level, raise on open, close button, resize bounds')

-- Unplaced windows are laid out automatically, centred on the screen.
main:Show()
assert(main.point[1] == 'LEFT' and main.point[2] == UIParent and main.point[3] == 'CENTER', 'automatic layout')
-- Dragging saves the position; resizing saves the size as well.
main.left, main.top = 100, 700
main.scripts.OnDragStop(main)
local saved = A.db.windows.RateMeMainWindow
assert(saved and saved.left == 100 and saved.top == 700 and saved.scale == 1, 'position saved after a drag')
assert(saved.width == 770 and saved.height == 565, 'size saved for a resizable window')
main:SetSize(900, 600); main.left, main.top = 120, 710
main.resizeGrip.scripts.OnMouseDown(main.resizeGrip, 'LeftButton'); assert(main.sizing == 'BOTTOMRIGHT')
main.resizeGrip.scripts.OnMouseUp(main.resizeGrip)
saved = A.db.windows.RateMeMainWindow
assert(saved.width == 900 and saved.height == 600 and saved.left == 120, 'size saved after resizing')
-- Reopening restores both, and the remembered window is left out of the automatic row.
main:Hide(); main:SetSize(770, 565); main:Show()
assert(main.width == 900 and main.height == 600, 'size restored on reopen')
assert(main.point[1] == 'TOPLEFT' and main.point[2] == UIParent and main.point[3] == 'BOTTOMLEFT'
    and main.point[4] == 120 and main.point[5] == 710, 'position restored on reopen')
editor:Show()
assert(editor.point[1] == 'LEFT' and editor.point[3] == 'CENTER', 'unplaced windows are still laid out automatically')
assert(main.point[1] == 'TOPLEFT', 'remembered window keeps its place when another opens')
-- A fixed-size window saves only its position.
editor.left, editor.top = 300, 500
editor.scripts.OnDragStop(editor)
assert(A.db.windows.RateMeEditorWindow.width == nil, 'no size saved for a fixed-size window')
editor:Hide()
print('PASS: automatic layout, saved position and size, restore on reopen, fixed-size windows')

-- Reset to Default asks first; nothing changes until it is confirmed.
local settings = A.db.settings
settings.debug, settings.confirmRemoveRating, settings.lookupPeerCount, settings.lowRatingThreshold = true, false, 15, 1.5
A:ConfirmResetToDefaults()
assert(#popups == 1 and popups[1].name == 'RATEME_RESET_DEFAULTS', 'confirmation shown')
local dialog = StaticPopupDialogs.RATEME_RESET_DEFAULTS
assert(dialog.button1 == 'Reset' and dialog.hideOnEscape and dialog.showAlert and dialog.text:find('Your ratings are kept', 1, true))
assert(not dialog.OnShow and not dialog.OnHide, 'stock popup behaviour, no layer workaround')
assert(settings.debug == true and A.db.windows.RateMeMainWindow, 'nothing reset before confirming')
local authored = A.db.authored
dialog.OnAccept()
settings = A.db.settings
assert(settings.debug == false and settings.confirmRemoveRating == true, 'settings back to defaults')
assert(settings.lookupPeerCount == 7 and settings.lowRatingThreshold == 3 and settings.minimapVisible == true)
assert(next(A.db.windows) == nil, 'remembered window placement cleared')
assert(main.width == 770 and main.height == 565, 'resizable window back to its design size')
assert(main.point[1] == 'LEFT' and main.point[3] == 'CENTER', 'window back in the automatic layout')
assert(A.db.authored == authored, 'ratings are kept')
assert(counters.alert >= 1 and counters.highlights >= 1 and counters.communication >= 1 and counters.minimap >= 1,
    'restored settings take effect immediately')
assert(A.main.settingsPanel.content.debug:GetChecked() == false, 'Settings checkboxes redrawn')
assert(logs[#logs]:find('reset', 1, true))
-- The Settings button goes through the confirmation.
popups = {}
A.main.settingsPanel.content.resetDefaults.scripts.OnClick()
assert(#popups == 1 and popups[1].name == 'RATEME_RESET_DEFAULTS', 'Reset to Default button asks first')
print('PASS: Reset to Default confirmation, settings and windows restored, ratings kept')

-- Removing a rating asks first (default on), with "Don't ask again".
local removed = {}
function A:DeleteOwnRating(target) removed[#removed+1] = target; return true end
local target = {guid='Player-1-bb', name='Target-Realm', faction='Alliance'}
editor.target = target; editor:Show()
editor.remove.scripts.OnClick()
local confirm = A.removeConfirm
assert(confirm and confirm:IsShown() and #removed == 0, 'confirmation shown before removing')
assert(confirm.text.text == 'Remove your rating for Target Realm?', 'question only: '..tostring(confirm.text.text))
assert(confirm.dontAsk:GetChecked() == false, '"Don\'t ask again" starts unticked')
-- One bottom row: checkbox on the left; Remove then Cancel on the right, not overlapping.
local accept, cancel = confirm.accept.point, confirm.cancel.point
assert(confirm.dontAsk.point[1] == 'BOTTOMLEFT' and confirm.dontAsk.point[2] == confirm, 'checkbox bottom-left')
assert(cancel[1] == 'BOTTOMRIGHT' and cancel[2] == confirm and accept[1] == 'BOTTOMRIGHT' and accept[2] == confirm,
    'buttons bottom-right')
-- Offsets are from the right edge: Remove's right edge must be left of Cancel's left edge.
assert(accept[5] == cancel[5], 'Remove and Cancel on the same row')
assert(accept[4] <= cancel[4] - confirm.cancel.width, 'Remove sits left of Cancel without overlapping')
local inSpecial = false
for _, n in ipairs(UISpecialFrames) do if n == 'RateMeRemoveRatingConfirm' then inSpecial = true end end
assert(inSpecial, 'Escape closes the confirmation')
confirm.cancel.scripts.OnClick()
assert(not confirm:IsShown() and #removed == 0 and editor:IsShown(), 'Cancel removes nothing')
editor.remove.scripts.OnClick(); confirm.accept.scripts.OnClick()
assert(#removed == 1 and removed[1] == target and not editor:IsShown(), 'Remove deletes and closes the rating window')
assert(A.db.settings.confirmRemoveRating == true, 'setting unchanged without the checkbox')
-- The confirmation removes the player it was opened for, even if the editor moved on.
local other = {guid='Player-1-cc', name='Other-Realm', faction='Alliance'}
editor.target = target; editor:Show(); editor.remove.scripts.OnClick()
editor.target = other
confirm.accept.scripts.OnClick()
assert(removed[2] == target and editor:IsShown(), 'removes the original player; editor showing someone else stays open')
-- Ticking the box and confirming turns the setting off; Cancel never does.
editor.target = target
editor.remove.scripts.OnClick(); confirm.dontAsk:SetChecked(true); confirm.cancel.scripts.OnClick()
assert(A.db.settings.confirmRemoveRating == true, 'Cancel ignores the checkbox')
editor.remove.scripts.OnClick(); assert(confirm.dontAsk:GetChecked() == false, 'checkbox resets each time')
confirm.dontAsk:SetChecked(true); confirm.accept.scripts.OnClick()
assert(A.db.settings.confirmRemoveRating == false and #removed == 3, '"Don\'t ask again" turns the setting off')
assert(A.main.settingsPanel.content.confirmRemoveRating:GetChecked() == false, 'Settings checkbox follows')
-- With the setting off, Remove deletes straight away.
editor.target = target; editor:Show(); confirm:Hide()
editor.remove.scripts.OnClick()
assert(#removed == 4 and not confirm:IsShown(), 'no confirmation when the setting is off')
print('PASS: remove confirmation (default on), cancel, original target, "Don\'t ask again", setting off')

-- The party rating window shows each player's class next to their name.
A:CreatePartyReviewWindow()
A:OpenPartyReview({
    {guid='Player-1-dd', name='Kirikou-John', class='PRIEST', faction='Alliance'},
    {guid='Player-1-ee', name='Nameless-Realm', faction='Alliance'},
})
local party = A.partyReview
assert(party.rows[1].nameText.text == 'Kirikou John  •  PRIEST', 'name and class: '..tostring(party.rows[1].nameText.text))
assert(party.rows[2].nameText.text == 'Nameless Realm', 'no class: name only')
print('PASS: party rating window shows "Name  •  CLASS"')

-- Windows keep the "name came from the game" mark when they copy a player.
function A:Query() return true end
A:OpenEditor({guid='Player-1-ff', name='Game-Name', faction='Alliance', class='MAGE', fromGame=true})
assert(A.editor.target.fromGame == true, 'rating window keeps the game-name mark')
A:OpenEditor({guid='Player-1-fe', name='Other-Name', faction='Alliance', class='MAGE'})
assert(not A.editor.target.fromGame, 'and does not invent one')
print('PASS: rating window keeps the game-name mark')

-- Lookups the player starts always run, whatever the automatic-lookup settings.
A.db.settings.lookupOnHover, A.db.settings.ratingHighlights, A.db.settings.lowRatingAlerts = false, false, false
local queried = {}
function A:Query(t, force, interactive) queried[#queried + 1] = {force = force, interactive = interactive}; return true end
A:CreateReviewsWindow()
local player = {guid='Player-1-fd', name='Some-Player', faction='Alliance', class='MAGE', fromGame=true}
A:OpenEditor(player)
A:OpenReviews(player)
A.reviews.refresh.scripts.OnClick()
assert(#queried == 3, 'rating window, reviews window and Refresh each look the player up: '..#queried)
assert(queried[1].interactive and queried[2].interactive and queried[3].interactive and queried[3].force,
    'started by the player: never held back; Refresh forces a new lookup')
-- The Settings checkbox controls the hover setting.
local box = A.main.settingsPanel.content.lookupOnHover
box:SetChecked(true); box.scripts.OnClick(box)
assert(A.db.settings.lookupOnHover == true, 'checkbox turns hover lookups on')
box:SetChecked(false); box.scripts.OnClick(box)
assert(A.db.settings.lookupOnHover == false, 'and off')
print('PASS: windows and Refresh always look up; Settings checkbox controls hover lookups')

-- Community Reviews shows 20 reviews per page, most useful first.
function A:DateText(n) return tostring(n) end
function A:WindowScoreText(n) return tostring(n) end
function A:ScoreText() return '' end
local paged = {guid='Player-1-pg', name='Paged-Player', faction='Alliance', class='MAGE', fromGame=true}
local votes = {}
local function letters(i) return string.char(97 + math.floor((i - 1) / 26)) .. string.char(97 + (i - 1) % 26) end
for i = 1, 45 do
    votes['peer' .. letters(i) .. '-realm'] = {sender='Peer' .. letters(i) .. '-Realm', score=3, rev=1, date=1000 + i, via='Relay-Realm'}
end
votes['verified-realm'] = {sender='Verified-Realm', score=4, rev=1, date=10, verifiedAt=1}
votes['me-realm'] = {sender='Me-Realm', score=5, rev=1, date=5}
A.runtime.cache[paged.guid] = {votes=votes}
A:OpenReviews(paged)
local rv = A.reviews
assert(rv.pageIndicator.text == 'Page 1 of 3', 'pages: ' .. tostring(rv.pageIndicator.text))
assert(#rv.rows == 20, 'at most 20 rows are created: ' .. #rv.rows)
assert(rv.rows[1].reviewer == 'me-realm' and rv.rows[2].reviewer == 'verified-realm',
    'your review first, then verified ones')
assert(rv.rows[3].vote.date == 1045 and rv.rows[4].vote.date == 1044, 'then unverified, newest first')
assert(rv.previousPage.enabled == false and rv.nextPage.enabled == true)
rv.nextPage.scripts.OnClick()
assert(rv.pageIndicator.text == 'Page 2 of 3' and rv.rows[1].vote.date == 1027 and #rv.rows == 20)
rv.nextPage.scripts.OnClick()
local visible = 0
for _, row in ipairs(rv.rows) do if row.shown then visible = visible + 1 end end
assert(rv.pageIndicator.text == 'Page 3 of 3' and visible == 7 and rv.nextPage.enabled == false, 'last page: 7 reviews')
rv.previousPage.scripts.OnClick()
assert(rv.pageIndicator.text == 'Page 2 of 3')
-- Opening another player starts at page 1.
A:OpenReviews(player)
assert(rv.page == 1 and rv.pageIndicator.text == 'Page 1 of 1')
print('PASS: Community Reviews pages of 20; own, verified, then unverified, newest first')
