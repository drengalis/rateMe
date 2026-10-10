# Rate Me!

A peer-to-peer player-rating addon for World of Warcraft Forever. **Addon version: 1** (in-client validation ongoing).

## Install

Copy the [`RateMe`](RateMe/) directory from this repository into your World of Warcraft Forever `Interface/AddOns/` folder, preserving its `Media` subfolder. Enable **Rate Me!** at character selection and use `/rateme` in game. The folder must contain `RateMe.toc`.

See [full addon documentation](RateMe/README.md) and [testing checklist](RateMe/TESTING.md).

## Status

This implementation has passed offline Lua syntax and simulated regression checks; real WoW Forever client and multi-client protocol testing are still required. Ratings are decentralized and only directly received online reviewer responses count as verified ratings. Written comments use logged addon messages when supported. There is no central database or profanity word list.

No license is granted by this README; repository licensing may be added separately by the maintainer.
