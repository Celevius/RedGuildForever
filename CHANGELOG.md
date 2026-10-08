# Changelog

All changes to Red Guild EPGP, newest version first.

## 1.1.0 (8 October 2026)

### Changed
* All windows are now built from Blizzard's own frame templates, so they use the Forever artwork and look like the guild and character windows
* The standings window has three tabs at the bottom, **Standings**, **Bench** and **History**. The separate bench window is gone
* Column headers in the standings can be clicked to sort
* The standings window shows your own priority next to the portrait and has a **Show everyone** checkbox
* The loot master window shows the item icon in the portrait and the item in a real item slot with quality border and tooltip
* The bid popup looks like the Need or Greed window, with an item slot, a gold timer bar and the buttons Main Spec, Off Spec and Pass
* The bid popup plays the raid warning sound when it opens
* Windows play the normal open, close and tab sounds of the game

### Added
* Safe fallbacks for every template, so a missing template gives a plain window instead of an error

## 1.0.1 (8 October 2026)

### Fixed
* Errors on login saying "Attempt to register unknown event RGF_READY" and "RGF_POINTS_CHANGED". These stopped the points and the standings window from loading
* The addon no longer overwrites the game's global slash command list, which could interfere with Blizzard's own slash commands

## 1.0.0 (8 October 2026)

### Added
* EPGP loot system following the guild loot rule book
* Points stored in guild officer notes, so they survive the Forever beta bug that forgets addon data after logout
* Bid popup for raiders with Main spec, Off spec and Pass, and whisper bids `ms`, `os` and `pass` for players without the addon
* Loot master window with all bids sorted by the rules and an Award button per bidder
* Main spec before off spec, new members below 300 EP after regulars, ties decided by `/roll`
* Off spec items and items for the guild bank or disenchanting cost 0 GP
* Item prices from the base price times the slot, with fixed prices per item
* Raid EP and on time bonus for the raid and the bench
* Alts share their points with the main
* Weekly decay with a GP floor of 100, and undo for changes made in the current session
* Standings sent by officers to members who cannot read officer notes
* Slash commands `/rgf` and `/epgp`
