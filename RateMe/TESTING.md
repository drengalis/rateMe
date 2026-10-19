# Rate Me! verification

Run every tests/*tests.lua suite from the repository root with Lua 5.3+ or texlua. The production code uses Lua 5.1-compatible syntax. Frame mocks exercise UI behavior; they do not prove actual WoW rendering or transport delivery.

- tags_tests.lua locks permanent IDs and the wire byte mapping; checks tag validation, compact storage, reordered announcements, author matching, revision immutability, reload persistence and legacy numeric interoperability.
- tag_editor_tests.lua covers Add Tag, separate polarity choices, maximum selection, conflicting tags, removal, colour markup, individual saves and party dirty-state tracking.
- broadcast_tests.lua covers routes, coalescing, settings, authenticated authorship, duplicate delivery and deletions during lookups.
- persistent_lookup_tests.lua covers cached records, serialized reloads, revision merges, tombstones and freshness.
- communication_subaddon_tests.lua covers dependency loading, dormant companions, API binding and event routing.
- Other suites cover settings, pagination, alignment, badges, activity logging and backward-compatible payload negotiation.

In game, test a fresh prerelease DB (no migration/conversion exists). Submit mixed positive/negative tags, reopen and edit the review, and verify a three-tag limit. Test party saves and removing tags. Verify colours, picker columns, wrapping, Escape handling and window positioning.

Use two updated clients: retrieve tags via a lookup and via a broadcast; test out-of-order metadata, edits and deletions. Disable broadcast receipt and verify explicit lookup tags still arrive. Reload and confirm saved tags and Verified author status remain while freshness expires independently. Test with an older v1 client: numeric ratings work; no comments are sent, and extra tag packets are ignored. Test custom-channel, guild/group and known-peer transport separately, including different backend realms. No universal delivery guarantee is made.

Do not include tests/ or TESTING.md in installation ZIPs.
