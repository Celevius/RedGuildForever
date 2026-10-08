# Changelog

All changes to Red Guild EPGP, newest version first.

## 1.4.0 (8 October 2026)

### Added
* **Start Bidding** window, no typing needed. Drag an item from your bags onto the slot, or click an item that is still on the corpse. Items seen on corpses this session stay in the list
* The Start Bidding window opens by itself when an officer loots a corpse with rare or better items in a group
* **Test mode** for the loot master window. Works alone, guild members send fake bids, ties are rolled for them, nothing is sent and no points change. Members can use it too
* **Sync** button in the `/rgf` window, the new **Sync** tab and the minimap menu. Officers share their data, the newest change of each player wins
* **Sync** tab with the state of the data, **Show backup** and **Import backup** to keep a text copy outside the game, **Import officer notes** for data from older versions, and **Start fresh** for a new guild
* The guild leader can let more ranks change data by writing `EPGP officers 2` into the guild information
* Commands `/rgf test`, `/rgf export`, `/rgf fresh`, and `/rgf bid` without an item opens the Start Bidding window

### Changed
* Points are no longer saved in the officer notes. They are saved in the addon's own save file, every player keeps a copy per guild
* Every change records the server time and who made it, so sync knows which change is newer
* Who may change data now depends on the guild rank, guild leader and rank 1 by default
* The Refresh button is now **Sync**
* Minimap menu has **Start bidding**, **Test the loot master window**, **Sync with everyone online** and **Backup and sync**

### Fixed
* Officers cannot change points while no data is loaded, so an empty save file can never overwrite the real points

## 1.3.0 (8 October 2026)

### Added
* Player editor for the guild leader and officers. Click a player in the standings, use **Edit target** in the minimap menu, or type `/rgf edit Cel Dru`
* In the editor you can set exact EP and GP, use quick buttons like +100 EP, add a reason that shows up in the history, link or unlink an alt and put the player on or off the bench. Every change can be undone
* The loot master window shows every answer in sections, **Main Spec**, **Off Spec**, **Passed** and **No answer yet**, with a count for each and the winner marked
* The loot master can type any price for the current item
* The loot master gets the bid popup himself and can bid on items like everyone else

### Changed
* Players who pass now stay visible to the loot master instead of disappearing from the list
* The loot window is called **Loot Master** and is a bit larger

### Removed
* The message in guild chat after the weekly decay. The addon never writes in guild or officer chat anymore, loot announcements stay in raid chat

## 1.2.0 (8 October 2026)

### Added
* Minimap button. Left click opens the standings, right click opens a menu with every action, drag it to move it around the minimap
* The menu has Standings, Bench, History, My points and Refresh for everyone, and for officers Give raid EP, Give on time EP, Add target to bench, Clear bench, Weekly decay and Undo last change
* The tooltip of the button shows your priority, your EP and GP and how many players are on the bench
* Red Guild EPGP is listed in the game's addon list next to the minimap, with the same left and right click, even when the minimap button is hidden
* `/rgf minimap` shows or hides the minimap button

## 1.1.1 (8 October 2026)

### Fixed
* Names with a first and last name like "Cel Dru" now work everywhere. Before, the space was removed and the addon could not find these players in the guild, the raid, whispers or rolls
* Alts of mains with two part names, the officer note now reads for example `@Cel Dru`

### Changed
* Slash commands accept names with several words, for example `/rgf ep Cel Dru 50`
* The first name alone is enough when only one guild member has it, and typing the start of a name works in commands
* When a typed name fits more than one player, the addon lists them and changes nothing
* `/rgf alt` takes two names, a comma between them is always safe, for example `/rgf alt Cel Rog, Cel Dru`
* Bid whispers go to the loot master with the name exactly as the game reported it

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
