# Rate Me! — WoW Forever

Rate the players you group with, and see how other players have rated them.

Give friendly, same-faction players 1–5 stars and up to three tags such as **+Helpful** or **-Ninja Looter**. Ratings are shared between Rate Me! users, so you can check a player's reputation before you invite them or join their group.

*Reputation earned. Reputation shared.*

> Rate Me! is in beta. Things may change between versions.

## Installing

1. Download the latest version.
2. Copy all three folders, **RateMe**, **RateMeData** and **RateMeCommunication**, into `World of Warcraft\_forever_\Interface\AddOns`.
3. Make sure all three are enabled in the AddOns list on the character screen.

When updating, replace all three folders, then type `/reload` or log in again.

## Rating a player

Open the rating window in any of these ways:

- Right-click a friendly player (their portrait, a party or raid frame, or their name in chat) and choose **Rate Me!**.
- Target the player and type `/rateme target`.
- Click the player in **My Ratings** in the main window.

The window shows the player's name, with their class icon and class underneath, and their community rating, which fills in as replies come back from other Rate Me! users.

Choose 1–5 stars, then pick up to three tags from the Positive and Negative lists. Each positive tag is shown beside its opposite, for example **+Fair Looter** next to **-Ninja Looter**, and you can't choose both. The most commonly used pairs are listed first. Tags you've chosen turn yellow with a check mark, and tags you can't choose right now are faded. Click **Save Rating** when you're done.

To change a rating, open the window again. **Remove** deletes your rating. By default you're asked to confirm first, and you can tick "Don't ask again" in that box to skip the question.

### Tags

| Positive | Negative |
|---|---|
| +Leader | -Poor Leadership |
| +Team Player | -Uncooperative |
| +Helpful | -Elitist |
| +Skilled | -Underperforms |
| +Reliable | -Abandons Groups |
| +Patient | -Impatient |
| +Fair Looter | -Ninja Looter |
| +Good Communicator | -Poor Communication |
| +Well Prepared | -Unprepared |
| +Knows Mechanics | -Ignores Mechanics |
| +Uses Crowd Control | -Ignores Crowd Control |
| +Good Sportsmanship | -Toxic |
| +Shares Resources | -Resource Hog |
| +Responsive | -Frequently AFK |
| +Careful Pulls | -Reckless Pulls |

Reviews written with older versions may still show **-Griefer** or **-Disrespects Loot Rules**. These tags can no longer be chosen.

## Rating your party

When you leave a party, a window opens listing the players you grouped with so you can rate them all at once. Click a player to choose their tags in the panel on the right. Anyone you leave unrated is skipped. Guild members aren't included.

- **Not Now** or Escape closes the window. Type `/rateme party` to bring it back.
- If you go through a loading screen (a hearthstone or a portal, for example) while the window is open, it reopens afterwards with your choices kept.
- You can turn this window off in Settings.

## Seeing other players' ratings

- **Tooltips:** hover over a player to see your rating and the community rating.
- **Community Reviews:** shows every review of a player, with each reviewer's stars and tags. Target the player and type `/rateme reviews`, or click the player in **Recent Lookups**. **Hide tags** hides one reviewer's tags if you don't want to see them.
- **Highlights (optional):** a gold or red glow on player frames, a star with the rating beside nameplates, and a star with the rating before chat messages.
- **Group alerts (optional):** a warning when a low-rated player joins your group.

### Verified and unverified reviews

A review is **Verified** when it came directly from the player who wrote it. A review passed along by another Rate Me! user is shown as **Peer supplied** (unverified). This lets you still see ratings when the original reviewer is offline.

Community scores count only verified reviews and your own. Unverified reviews are listed but not counted, and the number of them is shown beside the score. Unverified reviews are deleted after 90 days.

Verified means the review came from that character. It doesn't mean the review is fair or true. Each character counts as a separate reviewer, so someone with several characters can rate a player more than once.

## The main window

Type `/rateme` or click the star on your minimap. The window has four tabs:

- **My Ratings:** every player you've rated, with search. Click a player to change your rating.
- **Recent Lookups:** players you recently looked up or rated. Click a player to see their Community Reviews.
- **Recent Players:** the last 150 players you've grouped with, in a party or raid, with your rating of each. Players in your current group are listed first as "In your group". Click a player to rate them. The list is kept between sessions.
- **Settings:** see below.

Each player has a round class icon beside their name. Hover over it to see the class. Rating numbers are coloured from red (1) through yellow (3) to green (5).

All Rate Me! windows can be moved and resized, and they remember their position and size.

## Settings

- **My Ratings:** show ratings from all your characters, and ask for confirmation before removing a rating.
- **Group Rating Alerts:** warn when a low-rated player joins your group. Choose whether to check your own ratings, community ratings or both, and the rating that triggers a warning.
- **Player Rating Highlights:** turn on frame glows, nameplate stars and chat stars, and choose whether they use your own ratings, community ratings or both. Gold means 4.0 or higher and red means below 2.0.
- **Post-Party Ratings:** open the party window when you leave a party.
- **Minimap Button:** show or hide the minimap star. Drag it to move it.
- **Communication:**
  - Share your new, changed and removed ratings with other users.
  - Receive ratings shared by other users.
  - Look up a player's ratings when you hover over them.
  - Set how many players are asked at once when looking someone up.
- **Diagnostics:** show Rate Me! activity in chat, to help with troubleshooting.
- **Reset to Default:** restores every setting and all window positions and sizes. Your ratings are kept.

## Commands

| Command | What it does |
|---|---|
| `/rateme` | Open the main window |
| `/rateme target` | Rate your current target |
| `/rateme reviews` | Show Community Reviews for your current target |
| `/rateme party` | Reopen the rating window for your last party |
| `/rateme partytest` | Preview the party window with example players (nothing is saved) |
| `/rateme minimap show` / `hide` | Show or hide the minimap button |
| `/rateme peers` | Show how many other Rate Me! users you're connected to |
| `/rateme netstats` | Show communication statistics |
| `/rateme debug` | Turn activity messages in chat on or off |
| `/rateme help` | List the commands |

## How sharing works

Rate Me! has no server. Ratings travel directly between players who have the addon, using the game's own addon messages. When you look up a player, Rate Me! asks other users it knows about, starting with your friends and guild members. They reply with the ratings they have. When you save a rating, it's announced to other users.

This means:

- The more people who use Rate Me!, the more ratings you'll see.
- A lookup may not find every rating that exists, especially for players few people have met.
- Lookups and announcements are rate-limited, so the game doesn't disconnect you for sending too many messages.

## Your data

Your ratings and the ratings you receive are saved on your computer, in `WTF\Account\<your account>\SavedVariables\RateMeData.lua`. They're kept when you log out or reload. Back up that file if you want to keep your ratings safe.
