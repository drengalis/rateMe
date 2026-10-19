# Rate Me!

**A player-rating addon for World of Warcraft Forever**  
**Addon version:** 1 · **Status:** Beta — in-game testing is ongoing

Rate Me! lets you remember the players you've enjoyed grouping with (and those you haven't). Give friendly players a **1–5 star rating**, leave an optional comment, see available community ratings, and receive configurable warnings when a low-rated player joins your group.

Everything runs inside WoW. You do **not** need an account, website, or external service.

## Installation

1. Download this repository using **Code → Download ZIP**, then extract it.
2. Copy **RateMe**, **RateMeData**, and **RateMeCommunication** into your WoW Forever `Interface/AddOns` directory. Keep `RateMe/Media` intact.
3. Each folder must contain its matching `.toc` file directly, for example `Interface/AddOns/RateMeCommunication/RateMeCommunication.toc`.
4. Enable **Rate Me!**, **Rate Me! Data**, and **Rate Me! Communication** in the character-selection AddOns menu, then enter the game.
5. Click the gold star on your minimap, or type **\`/rateme\`**.

When updating, replace all three installed addon folders. The companion addon owns all persistent records in the `RateMeDB` SavedVariables table, saved by WoW in `SavedVariables/RateMeData.lua`. This unreleased storage layout starts with a fresh database and has no import or migration from earlier previews. Reload the game UI **once after replacing addon files**; you do **not** need to reload after rating someone or changing settings.

## Get started

### Rate a player

Right-click an eligible friendly player and select **Rate Me!**. You can also target them and type \`/rateme target\`.

In the rating window:

- Choose **1 to 5 stars**.
- Optionally add a short comment (up to **160 UTF-8 bytes**).
- See **your existing rating** alongside the **available community rating**.
- Save, edit, or remove your own rating whenever you like.

Only **friendly, same-faction player characters** are eligible. You cannot rate yourself, opposing-faction players, NPCs, or pets. The player being rated does **not** need to have Rate Me! installed for you to save your personal review.

### See ratings at a glance

Hover over an eligible party or raid member to see their available community stars and review count in their tooltip. The addon uses its recent local results immediately and refreshes stale information when possible.

In Rate Me! windows, scores show **five full, half, or empty stars**, followed closely by the numeric average rounded to **one decimal place**. Individual star icons round to the nearest half-star; the stored score is not rounded for calculations.

### Browse your ratings

Open \`/rateme\` or click the minimap star:

| Tab | What you'll find |
| --- | --- |
| **My Ratings** | Everyone you've personally rated. Select a player to view, edit, or remove your review. |
| **Recent Lookups** | Players whose community ratings you've recently checked. Select one to view details or refresh their rating. |
| **Settings** | Group warnings, rating highlights, post-party reminders, comment visibility, and minimap preferences. |

You can search both lists. They are always sorted by **date, newest first**. Recent Lookups retains up to **150** player entries and can show older results as **cached** rather than live.

The main window, rating editor, and reviews window arrange themselves side by side where space permits. They have opaque backgrounds and can be moved. Press **Escape** to close the most recently opened Rate Me! window.

### Rate your party when it ends

When you leave or disband a normal **party**, Rate Me! can show **Rate Your Party** with the eligible players encountered during that party, even if someone left early. Add stars and optional comments to several players, then choose **Save Ratings**.

- Existing ratings/comments are prefilled; unchanged entries are skipped.
- Select **Not Now** or press **Escape** to dismiss it.
- The automatic prompt is **on by default** and can be disabled in Settings.
- This does **not** appear after a raid.
- Use \`/rateme party\` to reopen your last party's list during the same game session.

## Settings

Open \`/rateme\` → **Settings**. Your selections are saved automatically, without needing \`/reload\`.

| Setting | What it does | Default |
| --- | --- | --- |
| **Group Rating Alerts** | Warn when someone joins your group with a personal and/or community rating at or below your selected threshold. Each source has its **own 1.0–5.0** threshold, adjustable in half-star steps. | Off; thresholds 3.0 |
| **Player Rating Highlights** | Add a soft **gold** glow for ratings **4.0+**, or **red** for ratings **below 2.0**, on supported nameplates and Blizzard group frames. Choose personal and community rating sources independently. Red wins if they disagree. | Off |
| **Post-Party Ratings** | Offer the batch-rating window after leaving a party (not a raid). | On |
| **Comment Safety — Hide written reviews by default** | Keep written reviews concealed until you choose **Show**. | Off |
| **Minimap Button** | Show or hide the gold star; drag it around the minimap to set its position. | Shown |

**Personal ratings** are always available locally. **Community warnings and highlights** require a fresh sample of directly received votes, not an old cached score. A player with no available qualifying score will not trigger a warning or glow.

Nameplate customization may be limited by the WoW client in dungeons and raids. Highlights are a local visual effect, **not** an actual 3D aura around the character.

## Comments and reporting

Open a player's **Community Reviews** to request available written comments. They are fetched only when you open the reviews window; some may be unavailable if their authors are offline.

For each received comment, you can:

- **Show/Hide** the text.
- **Block/Unblock** the reviewer locally. This hides their comments and stops requesting additional ones, but **does not** alter their numeric contribution to the community rating.
- Choose **Report** to see guidance identifying the **verified comment author**, not the player being reviewed.

**Report does not automatically submit a ticket or in-game report.** It provides attribution and instructions so you can make a report through Blizzard's supported process. It is available only when the comment has verifiable logged-message evidence.

Rate Me! has **no custom profanity dictionary** and does not claim to apply Blizzard's chat language filter inside its review windows. Comments are sanitized to prevent WoW formatting/control characters from being rendered. Written comments use Blizzard's logged addon-message transport when available; if that transport is unavailable, comments cannot be transferred.

## Minimap and slash commands

The gold minimap star opens or closes the addon on **left-click**. **Left-drag** it to move it; the position persists after logout.

| Command | Action |
| --- | --- |
| \`/rateme\` | Open or close the main window |
| \`/rateme target\` | Rate your current eligible target |
| \`/rateme reviews\` | View reviews for your current target |
| \`/rateme party\` | Reopen the last party's batch-rating window this session |
| \`/rateme minimap\` | Toggle the minimap button |
| \`/rateme minimap show\` | Show the minimap button |
| \`/rateme minimap hide\` | Hide the minimap button |
| \`/rateme peers\` | Show the number of currently known peers |
| \`/rateme debug\` | Toggle diagnostic messages |

If you hide the minimap button, **\`/rateme\` always remains available**.

## How community ratings work

Rate Me! uses an **on-demand peer-to-peer network** through WoW's built-in addon messaging. There is **no central ratings database or outside server**. Optional rating announcements use the RateMeNet custom addon channel alongside guild/group and confirmed-peer routes.

When you look up a player, your client asks reachable addon users for ratings. A review only counts in a fresh community sample if it is received **directly from its original reviewer**; another player's copied local ratings are not accepted as authoritative. Identical reviewer responses are counted once.

This means:

- The displayed community score is based on **available verified replies**, **not** every rating ever submitted.
- Review counts can change as people connect, disconnect, or become unreachable.
- Recent results can be displayed from cache but are labeled as such when stale.
- You can still create and edit **your own** ratings while offline from the rating network.
- A modified addon or multiple legitimate characters cannot be completely prevented from submitting deceptive personal reviews.

Rate Me! is intended to be a helpful personal/community reference, not a definitive verdict about another player.

## Troubleshooting

**I don't see Rate Me! in the AddOns list.** Make sure `RateMe/RateMe.toc`, `RateMeData/RateMeData.toc`, and `RateMeCommunication/RateMeCommunication.toc` exist directly under `Interface/AddOns`, rather than an extra nested \`rateMe-main/RateMe\` folder. Keep the \`Media\` files with the addon.

**The stars show empty squares or missing artwork.** Reinstall all three addon folders, including the whole \`RateMe\` folder, including \`Media\`. Rate Me! uses bundled star textures rather than Unicode star characters.

**A player has no community rating.** This can simply mean no reachable online reviewers have replied. Your personal ratings still work.

**I hid the minimap icon.** Type \`/rateme minimap show\` or open \`/rateme\` → Settings.

**Nothing happens after leaving a group.** The batch prompt applies to ordinary parties, not raids. Check **Post-Party Ratings** in Settings; if you left during combat, the popup waits until combat ends.

**Need to verify compatibility or report an issue?** See [the in-game testing checklist](RateMe/TESTING.md) and open a [GitHub issue](https://github.com/drengalis/rateMe/issues) with your WoW Forever client version, steps to reproduce, and any relevant error text. Avoid posting other players' private information or abusive comment text in public issues.

---

*Rate Me! is a community addon. Version 1 is currently a beta; actual WoW Forever client and multi-client compatibility testing is ongoing.*

## Data companion

`RateMeData` is a required companion addon. It owns the single account-wide `RateMeDB` SavedVariables table, personal ratings, preferences, community history, peers, reviewer blocks, and data classes. `RateMe` declares `## Dependencies: RateMeData, RateMeCommunication` and does not declare a separate SavedVariables table. All three addon folders must be installed side by side. The storage design is unreleased and intentionally has no legacy import or migration code.



## Current addon layout

Install all three folders together: **RateMe**, **RateMeData**, and **RateMeCommunication**. RateMeData owns RateMeDB; received reviews and fetched comments now persist across sessions and merge by reviewer/revision. Confirmed deletions are retained. A green Verified author label identifies reviews received directly from their author; source verification persists independently of freshness. Cached records do not automatically count as fresh for alerts. RateMeCommunication owns payloads, transport, discovery, throttling, lookup routing and communication diagnostics. Version 1, protocol 1 and prefix RATEME are unchanged. This unreleased storage format includes no legacy migration.

Run the Lua suites in tests/ from the repository root. See RateMe/TESTING.md for validation guidance. Install ZIPs exclude tests and TESTING.md.


## Communication preferences

Settings > Communication controls the maximum direct peers per lookup (1-20, default 7), sending rating announcements, and receiving/saving announcements. Both broadcast toggles default ON. Only announcements whose authenticated sender matches their claimed reviewer are marked verified. Numeric metadata is broadcast; comments remain on-demand. Delivery uses available custom-channel, guild/group and known-peer routes and cannot guarantee reaching every Forever addon user. See RateMe/README.md for scope and limits.
