# Changelog

All changes to Red Guild EPGP, newest version first.

## 2.4.0 (13 November 2026)

### Added
* **Loot history**, a tab of its own for everyone. Every item with the date, the winner, main spec or off spec, the price and how many players wanted it. Click an item to see everyone who bid: their answer, their priority at that moment and their roll
* Items that went to the bank or the disenchanter are in the loot history too
* **Search** by item or player (as winner and as bidder), a **time** button for all time, 7 days or 30 days, and **Only mine** for the items you won or bid on
* Editors can take an award back from the loot history with **Take back**
* The bids of every item are now kept and shared with Sync and the backup

### Changed
* The History tab is now the **EPGP history**. It shows EP and GP changes, decay, edits, alt links and undos, with a search box. GP from loot is left out unless you tick **Also show GP from loot**
* The tabs are Standings, Loot history, Raid, EPGP history and Data. Members get the first two
* Editors on 2.3 or older still sync points with 2.4. They do not get the loot records, so their loot history stays without bids until they update

## 2.3.0 (13 November 2026)

### Added
* **One Loot Master window.** The Start Bidding window and the Loot Master window are one window now: the items of the corpse and the running biddings on the left, the full list of bids for the chosen item on the right
* **One button for the next step.** A big button always does what comes next: Start bidding, Close bids now, then for example "Award to Lisa (main spec, 100 GP)". Everyone else in the list still has an Award button
* **Alt click an item** in your bags or in the loot window to choose it for bidding
* The addon **asks before it awards** an item. Both can be turned off in the game's Options
* **Bid cards.** Raiders get a small card above the action bars for each item, instead of a window in the middle of the screen. Several items stack, each with its own timer bar
* The card shows **your priority now and after a win**
* When the game knows that your character **cannot use the item**, the card says so and Main Spec is greyed out
* The bid cards and the winner popup **can be dragged anywhere**, the place is remembered. `/rgf resetpos` puts them back
* **Key bindings** for Main Spec, Off Spec, Pass, the standings and the Loot Master window, in the game's key binding settings under Red Guild EPGP
* **Your own row** is always at the top of the standings, with your place
* **Class icons** in the standings, a place number, and a bar that shows each priority against the best one
* **Tooltips on the buttons.** The EP buttons list who would get the EP and who already got it, Undo shows what it would take back
* A short **welcome** the first time the addon runs, `/rgf welcome` shows it again

### Changed
* **Members only see the standings.** The Raid, History and Data tabs are for editors
* The EP buttons say what they give, for example **+100 EP raid**, and follow the guild rules
* Paragraphs of explanation became a small **i** next to the heading, with the text in a tooltip
* The Loot Master window no longer comes back with every bid after you closed it. It comes up when bidding starts and closes when nothing is left to do
* Less chat: a manual sync prints one line instead of two, and the hint about changing a bid comes once per session

## 2.2.1 (13 November 2026)

### Changed
* The bid popup closes as soon as you click **Main Spec** or **Off Spec**, before it stayed open until the item was given out. With several items it goes on with the next one. A chat line confirms your bid

### Added
* `/rgf rebid` shows the bid popup again, to change a bid while bidding is open

## 2.2.0 (13 November 2026)

### Changed
* **Settings and rules moved to the game's Options.** They are under Options, AddOns, **Red Guild EPGP**: the settings on the first page, the **Guild rules** on a page below it. The addon window no longer has the Rules and Settings tabs, it keeps Standings, Raid, History and Data
* `/rgf settings` and **Settings** in the minimap menu open the game's Options on the addon's page

### Added
* `/rgf rules` and **Guild rules** in the minimap menu open the rules page
* During a fight the game does not let addons open the Options. The addon then says where to click instead of failing

## 2.1.1 (13 November 2026)

### Added
* `/rgf check` prints which game version runs, whether every game function the addon needs is there, and the state of your data. Paste it into a bug report

### Changed
* The addon is now for the released game, World of Warcraft Forever 1.60.1. The texts no longer speak of the beta, and the install folder is `_forever_`
* During a boss fight the game takes no addon messages. The addon now asks the game about that and waits, instead of trying and failing

### Fixed
* **Sync could lose messages in the released game.** The game takes ten addon messages at once and then one per second, the addon sent about three per second and gave a refused message up after three tries. It now counts the allowance itself, never sends more, and tries a refused message again for up to ten minutes
* A long sync could use up the allowance, so the start or the end of an auction was refused and lost. Sync now leaves room for auction messages, and a refused auction message goes out first as soon as the game allows it

## 2.1.0 (13 November 2026)

### Added
* **Winner popup.** When the loot master awards an item, everyone in the raid with the addon sees a small popup at the top of the screen with the winner, the item, main spec or off spec and the price. It goes away after five seconds or with a click, several awards in a row are shown one after the other
* **Show a popup with the winner when loot is given out** in the Settings tab turns it off for you. It is on by default

### Changed
* The message that ends an auction now carries the price, the spec and the item. Players on 2.0 still work with a loot master on 2.1, they only do not get the popup

## 2.0.2 (4 November 2026)

### Changed
* The Start Bidding window no longer opens by itself when you loot. Open it from the minimap menu, the Loot Master button or `/rgf bid`. The items of the corpse are listed there as before. Who wants the old way turns on **Open Start Bidding when I loot good items in a group** in the Settings tab

## 2.0.1 (3 November 2026)

### Changed
* The addon is now free software under the MIT License. The `LICENSE` file is in the repository and in the zip, the `.toc` file names the license, and every Lua file starts with a license line

## 2.0.0 (21 October 2026)

### Added
* **Every change is kept.** Awards, raid EP, decay, alt links and undo are stored as changes, and the points are computed from them. Two loot masters in two raids at the same time both count, also when they could not reach each other during the raid
* **Raid nights.** **Start raid** gives the on time bonus and starts the loot list, **End raid** gives the raid EP. Players who left early are offered the raid EP too. New Raid tab with the bench and the loot of the raid, `/rgf start`, `/rgf end`
* **Raid EP once per night.** The raid EP and the on time bonus count once per player in 12 hours, so the bench or an alt in a second raid never gets them twice
* **Several items at once.** **Bid on all** in Start Bidding opens every rare and better item of the corpse, numbered in one raid announcement. The Loot Master window switches between them, the bid popup shows one after the other, raiders without the addon whisper `ms 2`
* **Whisper commands** for players without the addon: `!ep`, `!ep Name`, `!bid`, `!top`, `!top mage`, `!loot`, `!loot Name` and `!help`. Every addon user with data answers
* Every whisper bid gets an answer, also when bidding is closed or nothing is open. A `+` for a raid invite gets none
* The winner gets a whisper with the item and the new priority
* **Loot history.** The last items of a player show in the standings tooltip and when you hover a bidder in the Loot Master window. `/rgf loot` and **Loot list for Discord**
* **Automatic backups** in a second save file of the character, ten minutes after changes, at the end of a raid and when logging out. If the main save file comes back empty, the newest backup is put back by itself. **Restore automatic backup** in the Data tab
* **Undo for every change.** **Undo last change** also works for changes of an earlier day, the History tab can undo any change of any editor
* **Weekly decay reminder** after login and at the end of a raid, and a warning before a second decay in the same week, also when another editor ran the first one
* **Rules tab.** The guild rules have their own tab, the Settings tab keeps test mode, the interface and the editors
* **Search and class filter** in the standings, and **Copy for Discord** for the shown list, also `/rgf discord`
* A window with text to copy for Discord

### Changed
* **New sync.** Both sides compare a short summary and only what is missing is sent. Sync messages go out a few per second instead of all at once, a transfer with a missing piece is asked for again, and the addon syncs every 15 minutes. Version 2.0 does not talk to 1.7 and older, everyone who changes data has to update at the same time
* The bench is shared with Sync, so every loot master sees the same bench. The bench of this computer moves over by itself
* The History tab shows every change of every editor, shared with Sync
* A linked alt brings its EP and the GP above the start to the main, before they were dropped. Undo takes the link back
* The minimap menu has **Start raid** and **End raid** instead of the two EP entries
* Backups contain every change. Backups of version 1.7 can still be imported

### Fixed
* Changes made at the same time on two computers could overwrite each other, now both count
* With two raids on one evening the bench could get the raid EP twice
* A big guild could lose sync messages because they all went out at once

## 1.7.1 (21 October 2026)

### Changed
* **Shorter minimap menu.** Right click only shows what is needed during a raid: Loot Master, Give raid EP, Give on time EP and Undo for editors, Sync now and Settings for everyone. Standings, bench, history, decay, backup, the editor and hiding the button are in the window, a left click opens it
* The **Sync** tab is now called **Data**, and **Weekly decay** moved there from the bottom of the standings. It is a once a week action and sat too close to Raid EP
* The bottom of the window only has buttons for editors: Loot Master, Raid EP, On time EP and Undo. The separate Sync button is gone, sync runs by itself and Sync now is in the Data tab and in the menu
* **Import officer notes** only shows while the addon has no data, it is only needed once when coming from version 1.3

## 1.7.0 (21 October 2026)

### Added
* **Editors.** The guild leader picks by hand who may change data, whatever their guild rank is, so raid leaders do not need an officer rank. Add and remove them in the new **Editors** section of the Settings tab, or with `/rgf editor add Name` and `/rgf editor remove Name`. `/rgf editors` shows the list
* **Add the current officer ranks** fills the list once with everyone the old rank rule allowed
* Every editor change is listed in the History tab

### Changed
* Editors can do everything officers could do before: change points, run the bidding, award loot, change the rules, decay and import
* The editor list is saved with the guild data and shared with Sync and the backup. Everyone only accepts list changes made by the guild leader, an editor can pass them on but never make them
* Once the guild leader added the first editor, only the list counts and the guild rank or `EPGP officers 2` in the guild information no longer decides. Until then the old rank rule still applies, so nobody is locked out by the update
* Data from players who are no editors is ignored by Sync, as before with members
* Messages and the minimap menu say editor instead of officer

## 1.6.0 (12 October 2026)

### Added
* **Guild rules** in the Settings tab and in the game's Options. The guild leader and officers can change every price, slot multiplier, EP amount, the starting GP, the weekly decay, the new member limit and the bidding time
* Off spec can cost a part of the price. The default stays 0 percent, so off spec is still free
* An example line in the settings shows right away what a two handed weapon from the end boss and a ring cost with the typed values
* **Save rules**, **Discard changes** and **Reset to defaults**, the reset asks first. The settings show who changed the rules last
* Every rule change is listed in the History tab

### Changed
* The rules are saved with the guild data and shared with Sync and the backup. Every officer uses the same values and the newest change of each rule wins
* Fixed prices for single items are now shared with Sync too, also when a fixed price is cleared. Fixed prices from older versions move over by themselves
* In test mode changed rules stay in the test data
* The settings page scrolls, because it got longer

### Fixed
* Wrong values from Sync, like a starting GP of 0, are ignored, so a broken setting can never reach the whole guild

## 1.5.1 (8 October 2026)

### Fixed
* Your own character was shown as "Cel-Dru" instead of "Cel Dru". Forever returns the first and the last name separately where other clients return the name and the realm, and the addon took the last name for a realm. Because of that your own character was not matched to the guild, so it could miss raid EP and its bids were listed under the wrong name
* The same fix for your target (Edit target, Add target to bench) and for party members
* Names written with a dash, like "Cel-Dru", are now matched to the guild member "Cel Dru" everywhere, also in whispers and messages from other players

## 1.5.0 (8 October 2026)

### Added
* **Settings** tab in the `/rgf` window, and the same settings in the game's Options under AddOns
* Settings for test mode, the minimap button and opening Start Bidding automatically when looting
* **Loot Master** button in the `/rgf` window and the minimap menu. It opens the running bidding, or the Start Bidding window when nothing runs
* `/rgf settings` opens the settings

### Changed
* **Test mode** is now a setting and simulates the whole addon instead of only the loot window. It works on a copy of the data with a simulated raid, so raid EP, bench, decay, the editor, alts, undo, bidding, rolls, awards, backup and sync can all be tried alone
* In test mode nothing is sent to other players, no chat message goes out and real data from other players is ignored. Your real points, bench and history are never touched
* Sync in test mode is simulated, a made up officer sends one newer change
* Every window shows **Test mode** in its title, the minimap button turns orange, and the menu has a quick **Turn test mode off**
* Members can try the officer tools in test mode
* Test mode cannot be switched while a real bidding runs, and the addon reminds you at login when it is still on
* `/rgf test` now turns test mode on or off

### Removed
* The test checkbox in the Start Bidding window and the menu entry **Test the loot master window**, both replaced by the setting

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
