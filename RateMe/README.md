# Rate Me! — WoW Forever addon

**Version:** 1  
**Target:** World of Warcraft Forever 1.60.1, Interface `16001`  
**Status:** Functional beta implementation; in-client testing required.

Rate Me! lets you rate friendly, same-faction player characters from 1 to 5 stars, optionally add a 160-byte comment, and view community ratings contributed by reachable online addon users. No external server, global rating database, custom chat channels, or external dependencies are required.

## Installation

Extract the ZIP into your WoW Forever AddOns directory so that the following file exists:

`World of Warcraft/_classic_beta_/Interface/AddOns/RateMe/RateMe.toc`

Enable **Rate Me!** in the character-selection AddOns list, then log into the game. The download contains both `RateMe.toc` and `RateMe_Camelot.toc` to support the client flavor's preferred naming convention.

## Usage

- **Right-click an eligible friendly player** and choose **Rate Me!**. The option only appears when a valid player unit can be identified.
- **/rateme** — open the main window (My Ratings / Recent Lookups / Settings).
- **/rateme target** — rate your current target (also useful if its context menu lacks a unit token).
- **/rateme reviews** — open community reviews for your current target.
- **Window layout** — the main browser, rating editor, and community reviews open side by side instead of on top of one another. Visible windows are centered together and automatically scaled to fit smaller game windows. They can still be moved manually.
- **Opaque dialogs** — all Rate Me! windows have solid, nontransparent backgrounds.
- **Escape** — closes the most recently opened Rate Me! window; press again to close other open windows. Escape also works while typing in Search or Comment.
- **/rateme peers** — display the number of known peers.
- **/rateme debug** — toggle diagnostic logging.
- **Minimap star** — left-click to toggle the main window, or left-drag to reposition around the minimap. Position is saved.
- **/rateme minimap** — toggle minimap icon visibility; `/rateme minimap show` and `/rateme minimap hide` are also available.

In **Rate Me! windows** (My Ratings, Recent Lookups, rating editor, and community reviews), every available score shows **five bundled stars immediately followed by its numeric value rounded to one decimal** (for example, `4.3`). Stars visually round to the nearest **half-star**, with full, half, and empty textures; the numeric value is rounded separately to 0.1 and retains the more precise average. Review counts remain visible. In game **tooltips** and low-rating chat notifications, scores remain stars-only. The exact underlying averages are retained for alerts and calculations.

In the rating editor, view current community rating alongside your own score and comment. You can save, update, or remove your rating. Your own ratings persist in SavedVariables by reviewer character, and can be browsed from **My Ratings** even when targets are offline. In **Community Reviews**, written comments can be hidden/revealed, blocked by author, or reported via a support-guidance dialog. Blocking a reviewer hides their comments locally without changing the community average. The **Recent Lookups** tab keeps up to 150 target identities and their last summary snapshots. **My Ratings** and **Recent Lookups** are automatically sorted by their displayed date (newest first), with non-clickable column headings.

## Settings — Minimap Button

Open `/rateme` > **Settings** > **Minimap Button**.

- **Show Rate Me! minimap button**: ON by default for new and existing installations.
- Uncheck to hide the button immediately, without `/reload`; check to restore it.
- Left-drag the star icon around the minimap edge to reposition it. Its position persists between sessions.
- Even when hidden, `/rateme` opens the addon and `/rateme minimap show` restores the icon.
- Minimap settings are account-wide and do not alter existing ratings or other preferences.

## Settings — Low-Rating Group Alerts

Open `/rateme` > **Settings** > **Group Rating Alerts**.

- **Enable group join warnings** is OFF by default.
- Independently select **Use my personal ratings** and/or **Use community ratings**.
- Each source has its **own threshold slider**, 1.0–5.0 stars in 0.5-star increments, default 3.0.
- Personal ratings use your current character’s saved review and work with no online reviewers.
- Community ratings use only the **fresh directly verified** sample, never stale historical snapshots.
- If **either enabled source** scores at or below its own threshold, one chat/on-screen warning is shown. If both qualify, the chat message names both sources; the player receives at most one warning until leaving/rejoining.
- No warning when the selected source has no rating. When community warnings are disabled, the alert subsystem makes no peer requests on its own.
- Existing installations keep their previous master enable toggle and community warning threshold. Personal alerts are initially disabled to preserve earlier behaviour.

## Settings — Player Rating Highlights

Open `/rateme` > **Settings** > **Player Rating Highlights**.

- **Highlight rated friendly players** is OFF by default; choose independent **personal** and/or **community** rating sources below the master switch.
- **Gold:** any enabled, available source scores **4.0 or higher**.
- **Red:** any enabled, available source scores **below 2.0**. **Red takes priority** over gold if the two enabled sources disagree.
- **No glow:** both enabled/available scores are in the 2.0–3.9 range, or there are no eligible ratings.
- Your own authored rating is always locally available. Community highlights require a fresh, verified sample; historical cache alone cannot trigger them.
- In the open world, glow surrounds the visible friendly nameplate (preferably its health bar); in parties and raids, recognized default Blizzard party/raid frames may be highlighted. Blizzard may restrict customization of friendly nameplates in PvE instances.
- Passive nameplate community lookups are rate-limited to six per minute, and are **not made** if community highlighting is disabled.
- Changing any setting updates available glows immediately. New secure-frame overlays are created only when safe outside combat.

## Settings — Comment Safety

Open `/rateme` > **Settings** > **Comment Safety**:

- There is **no bundled profanity dictionary or custom word-masking feature**. Blizzard's mature-language chat filter cannot be applied as a general API to arbitrary addon review-window text. Do not claim comments are automatically censored.
- **Hide written reviews by default** retains its previous setting (OFF for new installations). When enabled, comments begin hidden each time the Reviews window opens. Choose **Show** to display the sanitized comment, then **Hide** to conceal it again.
- **Block/Unblock** suppresses that reviewer's comments locally and prevents new comment requests to them. It does not change the aggregate numeric community rating; blocks persist in SavedVariables.
- **Report** is enabled only for a directly received `CHAT_MSG_ADDON_LOGGED` comment with consistent sender, target, revision, and exact text. It opens manual support guidance identifying the verified **comment author** (`Character-Realm`) as the player to report, and lists the reviewed player only as context. It includes the logged-message text and receipt date, plus a copyable Blizzard Support URL. It **does not** submit an in-game report or ticket; users submit their own report. A copied review or a personal local comment cannot impersonate a reportable author.
- Comments are transmitted only through `C_ChatInfo.SendAddonMessageLogged()` and processed via `CHAT_MSG_ADDON_LOGGED`. No fallback to ordinary, unlogged addon messages. Numeric ratings and peer discovery continue using regular addon messaging.
- Comments are limited to 160 UTF-8 bytes and sanitized to prevent control characters and WoW formatting codes (pipes, links, textures) from being rendered. This **is not profanity filtering**. The sanitized comment remains intact for display and reporting.

## Displayed player names

Rate Me! windows and its chat/on-screen notifications display character and realm separators as **spaces**, rather than dashes. Internal `Character-Realm` identifiers and SavedVariables keys stay unchanged so messaging and identity checks continue to work correctly. Blizzard-controlled world nameplate labels are not modified.

## How ratings are retrieved

The client advertises itself to the party, raid, instance and guild using `C_ChatInfo.SendAddonMessage` with prefix `RATEME`. Known peers can be introduced and queried through addon whispers. Requests may be forwarded at most two hops, to up to three peers per hop, with additional per-peer rate limits and bounded discovery probes. **Votes themselves are NEVER copied as authoritative data through the network.** Every counting vote must be returned by that reviewer's own online client directly to the original requester. A query yields an average of *reachable reviewer replies*, not an authoritative worldwide rating.

Rating responses include score, revision, author-submitted date and a has-comment flag. Written comments are fetched separately through direct whispers using only `C_ChatInfo.SendAddonMessageLogged`. If the logged API is absent, comments are not sent (never silently downgraded to ordinary addon messages). Total comment bytes are limited to 160. The active vote cache has a freshness lifetime of 15 minutes; a new lookup replaces that sample instead of retaining disconnected old votes. The last average persists as a clearly marked stale snapshot.

## Security and limitations

- **Identity**: WoW supplies the sender name for incoming addon whispers. The addon does not trust reviewer names in payloads. No external signature or key infrastructure is used.
- **Eligibility**: NPCs, pets, hostile units, cross-faction players and the current player are excluded when verified through unit APIs. Unverifiable remote faction and character-GUID ownership are not cryptographically provable by addons.
- **Spoofing**: A user can still edit *their own* SavedVariables or use modified addon code to submit deceptive votes as their own character; one-vote-per-Battle.net-account cannot be enforced.
- **Availability**: The online peer overlay is opportunistic. Guild and group routes do not guarantee global discovery; whispers can fail; some legitimate votes may not be counted. Requests can be forwarded maliciously, so rate limiting and request timeouts are employed.
- **Comments**: May not load if the reviewer disconnects or logged addon messages are not supported. Text is sanitized before display. Logged transport permits Blizzard to investigate reported content; it does not apply Blizzard's chat profanity filter automatically. See Comment Safety below.
- **Persistence**: Some Forever beta builds have had SavedVariables persistence issues. Test a normal logout/login and `/reload` on your build. See TESTING.md.

## Developer files

`Core.lua` (bootstrapping and unit eligibility), `Storage.lua` (SavedVariables and ratings), `CommentSafety.lua` (review visibility and blocking UI helpers), `Network.lua` (P2P protocol), `Alerts.lua` (group join detection and warnings), `Highlights.lua` (nameplate/group-frame glow), `UI.lua` (frames and dialogs), `Integration.lua` (menus/tooltips/commands).

The addon targets Lua 5.1 and does not require Ace3, LibStub, external websites or a backend.

### Star display compatibility

Star controls, tooltip icons, and the minimap icon use the bundled `Media/StarFull.tga` and `Media/StarEmpty.tga` textures rather than Unicode star characters. Keep the `Media` folder when installing or updating Rate Me!.


## Post-party batch ratings (version 1)

When you leave or your group disbands from a **party** (not a raid), Rate Me! offers a
**Rate Your Party** window with the friendly, same-faction players encountered
in that party. The addon captures their character GUIDs, names, class and faction
*before* the roster disappears. An optional comment and five clickable stars are
available for each player, and any existing rating/comment is prefilled.

- Choose stars for as many players as you want, then **Save Ratings**. Unrated
  rows and unchanged existing ratings are skipped.
- **Not Now**, the window's X, or **Escape** dismisses the popup.
- `/rateme party` reopens the most recently finished party while this character
  remains logged in. The roster is session-only and is not uploaded anywhere.
- **Settings > Post-Party Ratings** enables or disables the automatic prompt;
  enabled by default. Disable it if you prefer rating from context menus.
- Members who leave earlier in the same party are retained (up to 40 distinct
  valid player characters). Raids never trigger the popup.
- The popup opens after combat ends if your party dissolves during combat.
- This does **not** send chat messages to party members or automatically request
  ratings. Personal ratings are saved locally and served through the existing
  direct-voter protocol only when requested.

The window uses the same opaque background, star textures, and Escape handling
as existing Rate Me! windows. In-game testing on Forever is still required.

### Visual improvements

- Rating highlights now use bundled alpha-gradient TGA textures for a diffuse gold or red glow, rather than a hard rectangular outline. Nameplate glows attach to the visible health bar when the client exposes one; supported Blizzard party and raid frames use the same soft glow.
- Main window grid columns (Player, Rating, and Date/Last Checked) are right-aligned, including their headings. Numeric star ratings in the review grid are also right-aligned.
- Gold and red glow boundaries remain 4.0+ and below 2.0; personal and community sources can be toggled independently in Settings.
