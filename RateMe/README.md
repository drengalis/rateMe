# Rate Me! — WoW Forever

Rate friendly, same-faction players with 1–5 stars and up to three predefined tags. Reputation earned. Reputation shared.

## Installation

Copy all three folders into Interface/AddOns: **RateMe**, **RateMeData**, and **RateMeCommunication**. Keep RateMe/Media intact and enable all three addons. Reload once after replacing files. Use `/rateme`, the minimap star, or a friendly player's context menu.

## Reviews and tags

Written comments have been removed. In the rating editor, click **Add Tag** to open separate Positive and Negative lists. Select up to three tags TOTAL, mixing either type. Selected tags appear beneath your rating with an X to remove each. Positive labels use a green + prefix; negative labels use a red - prefix. Direct opposites are mutually exclusive. The post-party rating editor uses the same selector. Community Reviews shows each author's tags and a Hide tags/Show tags control for that reviewer.

### Permanent IDs

The authoritative registry is RateMeData/Tags.lua. IDs MUST NEVER be renumbered, reassigned or reused. Retire entries in place with retired=true; never delete their definitions. Preserve the encoder alphabet and ID-to-byte mapping. IDs do not depend on picker order or display text. Gaps are reserved for future additions. If the encoding capacity is exhausted, introduce a new encoding rather than reuse old IDs.

| ID | Positive | ID | Negative |
|---:|---|---:|---|
| 1 | +Leader | 33 | -Ninja Looter |
| 2 | +Team Player | 34 | -Toxic |
| 3 | +Helpful | 35 | -Griefer |
| 4 | +Skilled | 36 | -Frequently AFK |
| 5 | +Reliable | 37 | -Abandons Groups |
| 6 | +Patient | 38 | -Uncooperative |
| 7 | +Fair Looter | 39 | -Ignores Mechanics |
| 8 | +Good Communicator | 40 | -Reckless Pulls |
| 9 | +Well Prepared | 41 | -Unprepared |
| 10 | +Knows Mechanics | 42 | -Poor Communication |
| 11 | +Protects Teammates | 43 | -Breaks Crowd Control |
| 12 | +Good Sportsmanship | 44 | -Disrespects Loot Rules |

## Storage and verification

RateMeData exclusively owns RateMeDB, saved by WoW in WTF/Account/<Account>/SavedVariables/RateMeData.lua. Personal reviews and received community records persist across logout/reload. One record is kept per target/reviewer; newer revisions replace older records, and deletions retain tombstones. Missing/offline authors do not erase cached reviews. Recent Lookups is capped at 150 identities; pruning that list does not erase review records. Persistent community storage has no automatic age/count eviction.

A complete tag selection is stored in a single string of 0–3 ASCII bytes, one permanent ID per character, without repeating labels or colours. An empty string means the author selected no tags; a missing field means no tag metadata has arrived. Invalid, duplicate, excessive and contradictory tags are rejected.

The green Verified author label means the rating was received directly from its original author's authenticated WoW sender. This source status survives reloads; freshness is tracked separately for 15 minutes within the session. Cached reviews remain visible but do not count as fresh for alerts/highlights. Verification is not a cryptographic signature, a guarantee of truthful reviews, or protection from edits to a user's own SavedVariables.

No import, comment conversion, database migration or settings migration is included in this unreleased format. No old comments are converted into tags. Addon and protocol versions remain 1; prefix remains RATEME.

## Communication

Settings > Communication controls maximum direct peers per lookup (1–20, default 7) and independent send/receive broadcast toggles (both default ON). Lookup waves may stop expanding after sufficient replies. Each root peer can forward under the existing two-hop, three-way bound; default seven roots give at most 91 honest query recipients, with a 100-reviewer response cap. Queries expire after about 15 seconds. Paging and search do not generate lookups.

New/edited/removed ratings coalesce for three seconds before announcement. Broadcasts attempt the temporary RateMeNet custom addon channel, guild/group routes and recently confirmed peers (directory capped at 120). Forever channel/realm restrictions, unavailable users, throttling and bounded queues can prevent delivery; successful enqueue does not prove receipt. There is no guaranteed global channel, external service or ordinary-chat payload fallback. Send/receive preferences apply independently; disabling broadcasts does not disable explicit lookups.

Legacy numeric R and B|1 shapes are unchanged, with the former comment-present flag always zero. The additive T|1 packet carries a request ID (or - for broadcasts), target GUID, revision and at most three encoded tag bytes. Old clients ignore T and continue exchanging numeric ratings. Tags are attached only to a directly verified record from the SAME sender at the SAME revision. Lookup tag packets must match an active/recent query; broadcast tag packets respect the receive toggle. Bounded, short-lived buffering handles reordered score/tag packets. Duplicate/conflicting same-revision metadata and stale updates are rejected. No comments are stored, requested, displayed or transmitted by this build.

## Other features

My Ratings and Recent Lookups have search, a clear button and 20-player pages. Settings includes account-character filtering, group rating alerts, frame glows, nameplate rating stars, post-party prompts, minimap controls, communication and optional readable diagnostics. Indicators are opt-in; personal ratings remain locally available. Displayed timestamps use local time with AM/PM; stored timestamps are UTC-based epoch seconds.

## Architecture and tests

RateMe owns UI and game integration. RateMeData owns data classes, storage, settings, review tags and the permanent registry. RateMeCommunication owns payloads, transport, discovery, broadcasts and tag-message validation. Its companion is dormant until RateMe binds and initializes it. Neither RateMe nor RateMeCommunication declares SavedVariables.

Regression suites live only in tests/ in the GitHub repository; see RateMe/TESTING.md. Install ZIPs contain only the three addon folders and exclude tests and TESTING.md. In-game rendering and mixed-client delivery must also be tested in WoW Forever.


## Sharing accumulated reviews

Lookups now request cached reviews as well as direct-author replies. A peer immediately returns its current character's own review and saved reviews for the target, then asks up to three other peers for additional saved records. It merges arriving records locally and streams new results back to its requester. That parent can merge and forward them again. Tags, revisions, original authors and removal tombstones travel with each record. An original reviewer can therefore be offline while a peer supplies a saved copy.

The additive S (shared lookup) and V (shared review) messages use explicit, temporary parent/child routes and fresh child request IDs. Responses must match an active lookup/route, expected peer and target. Duplicates are collapsed by target/original reviewer identity. No forwarded verification flag is trusted: only an authenticated sender matching the original reviewer establishes direct verification for that recipient. Rows and tooltips label other copies **Peer supplied**, name the supplying peer and show receipt time. Community averages include available peer-supplied records with their count disclosed; fresh-only alerts and highlights exclude them.

Locally verified records—including verified deletions—take precedence over forwarded claims. Newer peer copies replace older unverified copies; conflicting equal revisions are rejected. The actual author can replace an unverified copy even when a peer supplied an artificially higher revision. Receiving a review directly does not carry over unverified tags; the author's complete tag set must also be received. Forwarded tombstones prevent older unverified records from returning, but cannot erase a locally verified record without direct author confirmation.

Legacy Q/R lookups remain unchanged for older clients; S/V supplement them and are safely ignored by clients without this feature. Both paths use the configured root-peer limit. Each shared tree has at most two forwarding hops with fanout three; overlapping Q and S trees can generate additional traffic. Each relay streams at most 100 packets per request, the root accepts at most 100 distinct shared authors in addition to the existing direct-reply cap, and outgoing/inbound limits still apply. At most 32 shared relay routes and 256 recent request IDs are retained in memory with expiry. These are defensive bounds, not a guarantee of finding all reviews across 5,000 users. Larger/popular results may require another lookup; persistent merging retains progress.

Only review data and provenance are saved; temporary reverse routes expire. No database migration, version change, new prefix, external server or publication step is introduced by this feature.
