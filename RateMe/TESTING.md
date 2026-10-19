# Rate Me! — in-client verification checklist

This addon is a beta build. Static tests do not replace exercising Forever's live API and transport rules.

## Client launch
1. Verify `/dump select(4, GetBuildInfo())` returns `16001`; update the TOC if Forever changes it.
2. Enable Rate Me!, login, type `/rateme`, and check for Lua errors (`/console scriptErrors 1`).
3. With an eligible same-faction player targeted, try `/rateme target` and the right-click `Rate Me!` entry.
4. Right-click an NPC, a pet, yourself, and (if available) an opposite-faction player; the menu entry must not appear.
5. Rate a friendly player, update the comment and stars, then remove and re-add the rating.
6. Check that `/reload` and a normal logout/login preserve your ratings.
7. Verify My Ratings search and edit flow, and that newest ratings appear first with no sort buttons. Change the All Characters checkbox under Settings > My Ratings; confirm the list updates without a footer toggle.
8. Verify Recent Lookups, drilldown Refresh, last-checked/cached indicators, and newest lookup dates first (no sort buttons).
9. Hover a group member: tooltip should show community score, count, and own score when known.
10. Change target with rating editor open, then save; review must still be attributed to the original player.

## Independent rating sources (personal/community)

1. Upgrade over old SavedVariables. Check that existing notification/glow master switches and the community alert threshold retain their values; personal sources should default OFF and community sources ON.
2. Under Settings > Group Rating Alerts, turn notifications ON, select **personal only**, and set a personal warning threshold (e.g. 2.5). Join a group containing a character you personally rated 2/5; the alert must appear without network replies.
3. With **community only**, your locally saved rating must not be sufficient until the current community sample arrives. Old cached-only summaries must not trigger warnings.
4. With **both sources**, set different thresholds; confirm either qualifying source triggers **one** alert. The chat alert describes the source(s) that crossed their thresholds.
5. Under Player Rating Highlights, select **personal only**; 4+ glows gold, below 2 glows red even without a community sample. Select **community only** and verify fresh-sample behavior.
6. Select both glow sources, provide 5 stars personally and a fresh 1.5-star community average; **red wins**. A stale community score must not override a current personal gold score.
7. Confirm changing source toggles and thresholds takes effect immediately and retains prior ratings, comments, and minimap configuration after relogging.
8. Character names appear with a **space instead of a dash** in all Rate Me! windows, search results, review author names, and notifications. Whispers still target `Character-Realm` correctly.

## Group alert tests
1. Type `/rateme`, select **Settings**, and verify alert notifications are initially disabled and the threshold defaults to 3.0.
2. Enable warnings and set the threshold to 3.5; verify the setting changes instantly and survives logout/login without `/reload`.
3. Have a friendly party member with a fresh 3.5/5 average join: expect a chat and on-screen warning after verified ratings arrive.
4. A 3.6/5 average should not warn with threshold 3.5 (boundary is inclusive).
5. Leave a member in the group and repeat scans/refreshes: there must be no repeated alerts.
6. Have the member leave, then join again: one new warning is permitted.
7. Check raid join/leave, and a party of more than five peers; group lookups must eventually complete without flooding.
8. Disable alerts and join low-rated players: no warnings should appear.
9. With no ratings or only an old cached snapshot, verify that no warning is displayed.
10. Confirm that opposite-faction players, NPCs and self cannot trigger warnings, and that warnings do not require group members to run Rate Me! (only online reviewers need it).

## Peer test (requires 2 or more distinct client accounts/characters)
1. Both players install Rate Me!; inspect `/rateme peers` after joining the same party or guild.
2. Character A rates another friendly player, character B queries that target. A's reply should count once, B should not receive fabricated data from third parties.
3. With three online clients, verify that a 2-hop forwarded query obtains a direct reply at the original requester.
4. Have one reviewer change their rating; refresh after the update and verify the new score, no double count.
5. Disconnect a reviewer, refresh, and confirm that the new sample no longer counts an absent reviewer.
6. Open Reviews and use Fetch Comments; confirm only direct reviewer responses are accepted.
7. Try several quick mouseovers; verify that the network queue doesn't flood and only stale targets query.
8. Use `/rateme debug` and look for throttle failures or bad menu/tip compatibility on your exact build.

## Known build-sensitive behavior
- `Menu.ModifyMenu` callback tags/contextData vary by menu. `/rateme target` is a fallback.
- `TooltipDataProcessor` and `TooltipUtil` may provide unavailable/restricted unit tokens in combat.
- `C_ChatInfo.SendAddonMessageLogged` may have differing restrictions in the Forever beta.
- A peer must be actively running the addon for its authored votes to be returned.
- Offline data may be displayed only as a stale snapshot, not as a live globally verified average.

## Rating highlights (new in version 1)

1. Open `/rateme` > Settings. Confirm **Highlight rated friendly players** starts disabled on a new profile and persists after a relog.
2. Enable it. On a fresh directly verified average of **4.0** stars, a visible friendly outdoor nameplate should glow gold.
3. Confirm **1.9** stars glows red, while exactly **2.0** does not. A score of **3.9** should not glow.
4. Confirm no glow on NPCs, enemies, opposing-faction players, your own character, missing ratings, or expired/stale snapshots.
5. With Blizzard's default party/raid frames shown, confirm only eligible rated members' frames glow. On third-party unit-frame addons, no support is promised.
6. Enter a dungeon or raid. Friendly nameplates should **not** be modified there; default group frames may still glow.
7. Disable the option; verify visible glows disappear without `/reload`. Test toggling during combat and after combat ends.
8. Target/mouseover and group-join lookups should update glow after response completes. Passive nameplate lookups are throttled to six per minute.
9. Reload, logout/login, and confirm all previously saved authored ratings and alert settings remain unchanged.

WoW Forever gameplay verification is required; mocked tests cannot verify protected nameplate/unit-frame behavior or in-instance combat restrictions.

## Minimap button (version 1)

1. On a fresh profile, verify the gold star is visible beside the minimap; left-click toggles the main Rate Me! window.
2. Left-drag the star around all quadrants of the minimap. It should stay near the edge and should not open/close the window when the drag ends.
3. `/reload` and logout/login; the dragged position should persist.
4. Open `/rateme` > Settings and disable **Show Rate Me! minimap button**. The star disappears immediately.
5. Type `/rateme` to open the window while the star is hidden. Re-enable the checkbox; the star reappears at its saved location.
6. Test `/rateme minimap hide`, `/rateme minimap show`, and `/rateme minimap` (toggle) as recovery controls.
7. Update from a previous version 1 installation and verify previously saved authored ratings, alert/highlight preferences, and new minimap default visibility are retained.
8. Drag while the UI is scaled differently and confirm pointer-to-angle positioning remains correct.

Live game testing is required for drag pointer coordinate behavior, particularly with custom UI/minimap scaling.

## Window layout, backgrounds, and Escape (version 1)

1. Open `/rateme`, then open a rating editor and click Reviews. Confirm all visible Rate Me! windows are arranged **side by side**, not on top of one another.
2. Confirm that the underlying game world and other UI are **not visible through** the dialog backgrounds, including inside the rating editor and Settings tab.
3. Press **Escape** repeatedly. Confirm open Rate Me! windows close without requiring their X buttons.
4. Click into the main **Search** box and press Escape. Confirm a window closes (not only keyboard focus). Do the same while editing a **Comment**.
5. Open the game at a narrower resolution or increase UI scaling. Confirm windows resize and stay within the screen; repeat after changing the display size while windows remain visible.
6. Close the review window while the browser and editor remain open. Confirm those windows move back into a centered side-by-side arrangement.
7. Save a rating after rearranging windows, then reopen it to confirm storage and editing are unchanged.

The reduced window scale on narrow displays is intentional: it prevents overlap while allowing the three windows to be displayed at once. Actual rendering and Escape behaviour must be verified inside WoW Forever.

### Star icon rendering

- Confirm the editor displays five gold/outlined star textures rather than empty square characters.
- Change the selected score from one to five: only selected stars should be filled.
- Check a tooltip with a known rating: all five small star textures should render.
- Confirm the minimap button shows a gold star texture and remains draggable.
- Check that `RateMe/Media/StarFull.tga` and `StarEmpty.tga` are installed.

## Window score display (version 1)

- [ ] My Ratings shows five filled/empty stars followed closely by a numeric value such as `4.0`.
- [ ] Recent Lookups shows full/half/empty stars plus a one-decimal number and the vote count.
- [ ] The editor shows the community average as stars plus a one-decimal number; your own interactive star selection has an adjacent `1.0`–`5.0` number.
- [ ] Individual reviews show stars and a one-decimal number.
- [ ] For an average of 4.2, stars round to 4.0 while the number shows 4.2; for 4.3, stars round to 4.5 while the number shows 4.3.
- [ ] Player tooltips remain unchanged (stars-only).
- [ ] No score overlaps the Date column or reviewer name.


## Post-party rating popup (version 1)

1. Log in solo, form a normal two-to-five-player party with one or more friendly
   Alliance/Horde characters. Confirm no popup on join or ordinary roster changes.
2. Leave the party or have the leader disband it. Verify **Rate Me! - Rate Your
   Party** opens with those players, even though their `partyN` unit tokens have
   disappeared. Verify only eligible friendly, same-faction player characters are listed.
3. Select stars for two players, type one comment, click Save Ratings. Confirm
   both appear under `/rateme` > My Ratings, with today's date and their comments.
4. Re-form and leave another party containing someone already rated. Verify the
   stars and comment are prefilled; clicking Save without changes must not
   increment the review's revision/date. Editing a comment without changing stars
   must still save the change.
5. Invite three more members, have one leave early, then disband. The early
   leaver should still appear in the party rating list.
6. Convert a party to a **raid**, then leave/disband. No post-party popup should
   appear. Form a raid directly and disband: likewise no popup.
7. Test Escape while the comment box has focus; it should close the popup. Test
   Not Now and X; use `/rateme party` to reopen the last party manually.
8. In `/rateme` > Settings > Post-Party Ratings, disable the feature. Repeat a
   party disband; no automatic popup should appear. Confirm the setting survives
   relog and `/reload`.
9. Leave a party in combat (if possible). The popup should defer until leaving
   combat; it must not cause a protected UI error.
10. With the main browser open, trigger the party popup. Verify the two windows
    tile side by side, have opaque backgrounds, and close individually with
    Escape. Test at low resolutions / higher UI scales.
11. If the addon loads while already in a party, it should capture subsequent
    roster changes and should show the post-party prompt on departure.
12. Ensure neither the popup nor Save Ratings produces unsolicited addon
    broadcasts or normal chat messages to other players.

### Soft glows and aligned grid

1. With player-rating highlights enabled, look at a friendly player whose directly verified average is at least 4.0. Confirm a diffuse gold aura surrounds the visible nameplate health bar, rather than a sharp gold rectangle around the entire nameplate.
2. Repeat with a verified score below 2.0 and confirm the soft red aura. Confirm no glow for scores from 2.0 to below 4.0, stale or missing ratings, or when the setting is disabled.
3. Leave and reenter nameplate range and confirm the aura follows the correct player and disappears when the nameplate is removed.
4. Check supported Blizzard party/raid frames for the same soft aura where permitted; friendly world nameplate modifications in instances remain restricted.
5. In the main window, confirm Player (and class), Rating, and Date/Last Checked are all right-aligned within their grid columns.

## Comment Safety (version 1)

1. Upgrade with existing SavedVariables and confirm the obsolete `filterComments` flag is removed, the hide-by-default setting is preserved, and authored reviews, alert/glow settings, and reviewer blocks are unchanged.
2. Obtain a direct, logged written review. An ordinary `CHAT_MSG_ADDON` comment packet must not populate comment text; only `CHAT_MSG_ADDON_LOGGED` should be accepted.
3. Review content is **not masked by any local profanity dictionary**. Verify that Show displays the original sanitized text without rewriting normal wording.
4. Enable Hide written reviews by default. Reviews should initially be hidden; Show reveals and Hide conceals. Closing/reopening Reviews resets per-session visibility. Disable the setting to show comments initially.
5. Click Block: the reviewer's text must be hidden, Show disabled, and new comment fetches must skip them. Unblock restores the normal hide/show behavior. The numeric community average stays unchanged. Relog to verify the block persists.
6. Click Report on a fetched comment and verify the dialog explicitly states it does not submit a ticket. Reviewer/target/date and support URL must be selectable/copyable; Escape closes it.
7. With `C_ChatInfo.SendAddonMessageLogged` absent, requested comments must not fall back to `SendAddonMessage`. Numeric votes and peer discovery should still work.
8. Test non-ASCII comments, the 160-byte UTF-8 limit, and stripping of WoW formatting/control codes.
9. Open Settings at a low resolution, scroll to Comment Safety, and verify there is **no** language-filter checkbox; changing hide-by-default updates an open Reviews window without `/reload`.

## Report the actual comment author (version 1)

1. Character Alice rates a third player Bob, including an optional written comment. Alice sends the comment directly to Carol using logged addon whisper transport.
2. In Carol's Community Reviews window for Bob, choose Report on Alice's comment. The dialog must prominently show **Alice-Realm as the player to report**, never Bob-Realm or a peer that relayed the rating query.
3. Verify the exact logged packet and a receipt timestamp are included; the reviewed character is listed only as context. The reported character identifier retains the canonical `Character-Realm` dash.
4. A non-logged, spoofed, wrong-sender, wrong-target, wrong-revision, or unsolicited comment must not become reportable or overwrite legitimate evidence.
5. A personally authored comment and any old cached comment lacking a captured logged source must have Report disabled.
6. The dialog must clearly state that it provides guidance only; the user submits the Blizzard Support ticket.
7. Verify that requerying and switching reviewed players never reuses the previous review's report author.

## Scalable network lookup regression (version 1)

The standalone protocol regression harness lives at `tests/network_tests.lua` in the GitHub repository. Run it from the repository root with `texlua tests/network_tests.lua` (Lua 5.3 is sufficient for this mock test; actual Forever testing remains necessary).

1. Install the current addon on **all** test clients. The addon uses version 1 and the `RATEME` addon-message prefix throughout development; keep testers on the same build.
2. In a populated guild, use `/rateme netstats`, request one player rating and verify guild and party/raid traffic is HELLO discovery only. Rating queries must be direct addon whispers.
3. Confirm the initial wave queues up to three direct queries, expands about four seconds later only if fewer than five verified votes have arrived, and may expand again around nine seconds. No more than seven initial seed queries per lookup; with honest, unique peers the two-hop forwarding tree reaches no more than 91 query recipients.
4. Verify that repeated mouseovers or forced refreshes during the same active lookup do not start a second query for the same GUID. The lookup completes in approximately 15 seconds.
5. Check that duplicate relayed query IDs forward only once per peer; a guild-wide `Q` packet must be ignored. Valid returned votes are direct from original reviewers, and at most 100 distinct remote reviewers can contribute to one request.
6. Confirm the client enforces per-peer, per-origin, and global inbound limits, prunes expired counters, and avoids a guild-wide acknowledgement storm when many addon users join simultaneously.
7. A newer revision supersedes an earlier one; a deletion tombstone must not be revived by an older rating reply. Verify comment traffic still uses logged whisper messages only.
8. Test 5 simultaneous different-target lookups, queue throttling, retries, client disconnects, no known peers and peers that arrive after a query starts. Inspect `/rateme netstats` for queue size, sent/received counts, and drops.

## Multiline rating editor (local preview)

1. Open **Right-click → Rate Me!** and type a long comment. It should wrap within a visible, opaque rectangular text field instead of appearing outside a single-line input strip.
2. Press Enter to create several lines. Confirm the viewport stays fixed, the text scrolls to keep the caret visible, and the mouse wheel scrolls within the text field.
3. Confirm the byte count is right-aligned **immediately below the comment field**, with Save/Reviews/Cancel below it and no overlap. Test an empty comment, a full 160-byte comment, and a pasted comment exceeding 160 bytes.
4. Save, reopen the rating editor and check that intentional line breaks persist. On a second updated client, fetch the comment and confirm its line breaks and logged-message report author remain intact.
5. Press Escape while editing: the current Rate Me! window should close.

Offline tests: `tests/editor_multiline_tests.lua`, `tests/network_tests.lua`, and `tests/settings_ui_tests.lua`. Real Forever client rendering and multi-client logged messaging still need verification.

## Compact Settings and visible comment scrollbar (local preview)

1. Open `/rateme` > Settings and confirm there is no separate **Preferences** heading/introduction. The six functional panels (starting with My Ratings) start near the top, remain opaque, are visually separated, and are reachable by scrolling at common UI scales.
2. Confirm the checkboxes describe their effect directly. The personal/community controls remain indented under their respective master switches and dim when disabled. Existing preference values survive an update.
3. Confirm there are **no help icons** or explanatory subtitles directly beneath the six section headings. The expanded checkbox labels remain self-explanatory; the colour legend and concise notes under individual controls remain.
4. In the rating editor, confirm a **visible vertical scrollbar** sits inside the comment field at its right edge. Write enough text to wrap past the fixed-height viewport; scroll by mouse wheel, scrollbar arrows, and thumb drag. Text must not render behind the scrollbar or outside the field.
5. Confirm the 160-byte count remains immediately beneath the comment field and the action buttons do not overlap it, including at smaller window sizes.

## Settings panel width and headers (local preview)

- [ ] All six Settings panels extend close to the right edge of the scrollable area, with even horizontal margins; none run underneath the scrollbar.
- [ ] Headings are plain gold text, with no narrow decorative bar or unexpected glyph to their left.
- [ ] Scroll the entire Settings page and verify panels have no overlaps and controls remain clickable.
- [ ] Resize/change UI scale, then reopen Settings and confirm panel widths track the content area.
- [ ] Alerts and Highlights source toggles still enable/disable dependent threshold controls as before.

## Player-list pagination and footer layout (version 1 local preview)

1. In both player lists, verify **Search** sits at the bottom left, close to its label, with an **X** button on the right. There must be no duplicate Search field near the top and no other list-footer buttons.
2. Settings hides list-only controls. Confirm there are **no All Characters or Refresh Selected Target** buttons in either list. Refresh remains available in the selected player’s drilldown.
3. Populate 45 personal ratings and confirm page 1 has 20, page 2 has 20, and page 3 has 5 entries. Previous is disabled on page 1; Next is disabled on page 3.
4. Verify both lists sort by date newest-first over their **full dataset**, then display the chosen page. Paging must not reorder or network-query entries.
5. Search for an entry originally on page 3: it must appear on page 1 of the filtered results. Clear search to restore the entire list and reset to page 1.
6. In Settings > **My Ratings**, toggle **Show ratings from all my characters in My Ratings** while My Ratings is on a later page; returning to My Ratings must show page 1 with the updated list. Do not change authorship or saved ratings. Changing tabs must never render stale rows from another list.
7. Verify an empty search result shows `0 players`, `Page 1 of 1`, no rows, and disabled Previous/Next buttons.
8. Change pages after scrolling down and verify the new page begins at the top. A background rating refresh on the same page should not change scroll position.
9. Confirm Player, Rating, and Date/Last checked headings remain right-aligned with their row values.


## Main-window header navigation (version 1 local preview)

1. Open `/rateme`: **Rate Me!** is at upper left, with **My Ratings**, **Recent Lookups**, and **Settings** in one row to its right. The close button remains unobstructed.
2. The tagline **Reputation earned. Reputation shared.** appears left-aligned to the exact same X position as the title, without touching the tab controls. There is no second row of tab buttons.
3. Switch through all three tabs. The correct content and disabled active-tab state should remain intact; the 20-row list paging, search footer, and Settings scroll panel should behave as before.
4. Open the editor or reviews window alongside the main window; the title-bar buttons must remain clickable and not overlap the window border/close control after automatic layout scaling.

### Numeric nameplate badge preview (version 1)

- Enable Player Rating Highlights, then enable the separate nameplate star badge while leaving glow disabled. Verify the star appears alongside visible eligible friendly player nameplates without requiring glow.
- Try personal-only, community-only, and both sources. With both enabled, fresh community takes precedence; if unavailable, personal can be shown. Never display stale community samples as fresh.
- Confirm a one-decimal numeric label inside the bundled star (gold 4.0+, red below 2.0, neutral otherwise), and that hiding the nameplate, disabling the option, changing zones, or changing unit removes/reuses the badge correctly.
- Confirm no NPC, enemy, self, or prohibited PvE nameplate badge, and no protected-frame anchors changed in combat. Verify actual Forever rendering in game; offline mock checks cannot establish nameplate compatibility.

## Main-window section dividers (version 1 local preview)

1. Open `/rateme` > My Ratings. A thin muted-grey horizontal line should separate the title/navigation row from the player list, and another should separate the list from pagination and Search. Lines should have matching left/right insets.
2. Switch to Recent Lookups: both rules should remain in the same positions, without overlapping column headers, scrollbar, pager, or clear-search control.
3. Switch to Settings: only the upper/title divider should remain. The lower list/footer divider must hide so it does not cross Settings panels. Return to a list: the lower divider reappears.
4. Test at non-default UI scale to confirm that the rules stay attached to the main window and do not appear as stray characters or glyphs.

## Main window visual sections (v1 preview)

1. On both My Ratings and Recent Lookups, verify a full-width subtle rule separates the title/navigation from the content area.
2. Verify the column headings are separated from the scrolling list by a lighter, narrower rule without overlapping the first player row.
3. Verify the pager, Search box and clear X sit on a slightly darker footer, below a separate rule. None of the rules or footer background should intercept clicks.
4. Switch to Settings: the header rule remains, but the list-specific column rule, paging footer and footer divider disappear. Switch back and confirm they return.
5. Verify the borders, scrollbar, pagination, column alignment and Search controls remain unchanged at different UI scales.

## Current list, badge and timestamp acceptance checks

1. My Ratings and Recent Lookups show 20 entries per page, independent pagers, newest first, and search applies across the complete list before pagination. The page indicator and right-aligned player count share the pager row.
2. List headers align horizontally with name, score and timestamp cells. Row shading reaches the usable scroll content edge beside the scrollbar, even immediately on first open or after UI scaling changes.
3. Search label sits with a little gap to the input border. Clear X is aligned to the visible textbox and is disabled when empty. The footer has a divider below pager, before Search. Settings hides list-only controls.
4. Check Settings > My Ratings > All Characters, with two characters contributing authored ratings. Confirm toggling updates the saved view preference, not the underlying records.
5. Rating and lookup times display the local client's `YYYY-MM-DD hh:mm AM/PM` format; report evidence includes seconds. The database keeps timezone-neutral Unix epoch seconds; a different client timezone must not shift the underlying stored timestamp.
6. A 32px round minimap icon uses its own transparent round texture and a centred 25px gold star, retaining click/drag/visibility functionality.
7. The independent nameplate badge is positioned left of the actual health bar, shows a 1-decimal score in 11pt outline text centred in the star, and preserves community-first/personal fallback, gold/red/neutral colour and combat-safe frame lifecycle.
8. Enter two-line comments and scroll them within the visible comment box. Newlines survive saved comments and logged transport; the 160-byte limit counts UTF-8 bytes.

All rendering, WoW UI template metrics, game timestamps and nameplate positioning require a real WoW Forever client check.


## v1 rolling-upgrade compatibility
- Run `tests/backward_compatibility_tests.lua` against the upgraded source.
- A newer client must accept legacy v1 Q/R packets and respond using the unchanged v1 layout to a peer that has not advertised capabilities.
- Newer codecs must be selected per peer only after K|1|... capability negotiation. Missing/unknown codecs fall back to v1 or are ignored.
- The unreleased RateMeData schema starts fresh, has no legacy import or migration code, and rejects unfamiliar future schema values without modifying saved data.

## Companion data-addon verification

- Install `RateMe/` and `RateMeData/` side by side; RateMe must load after its required companion.
- Only `RateMeData` declares `## SavedVariables: RateMeDB`, producing `SavedVariables/RateMeData.lua`.
- Personal ratings, settings, reviewer blocks, recent community summaries and peer records live in that single table. The main addon's storage is a binding layer only.
- Run `tests/data_subaddon_tests.lua` and `tests/debug_activity_tests.lua` along with existing network, UI and payload tests. There is no legacy import or schema migration in this unreleased layout.
