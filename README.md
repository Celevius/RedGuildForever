# RedGuildForever

An EPGP loot addon for our guild on World of Warcraft Forever. It follows the guild loot rule book, so the addon and the Discord rules always agree.

Version 1.7.1, updated on 21 October 2026 for the Forever beta client (interface 16001).

## What it does

Show up and you go up the list, take loot and you go down the list.

* Raiders get a popup when loot is up for bids and click **Main spec**, **Off spec** or **Pass**
* The loot master sees every bid sorted by the rules and clicks **Award**
* EP for the raid night and the on time bonus go to everyone in the raid and on the bench
* Alts share points with their main
* Weekly decay, undo, price overrides and a standings window
* Points are saved in the addon's own save file and shared with **Sync**
* A **Start Bidding** window to drag items in or pick them from the corpse
* A **test mode** in the settings that simulates the whole addon, so you can try everything alone
* The windows are built from Blizzard's own frame templates, so they look like the guild and character windows of the game

## Install

1. Download the latest `RedGuildForever.zip` from the releases, or build it with `./build.sh`
2. Extract it so the folder sits at `World of Warcraft\_classic_beta_\Interface\AddOns\RedGuildForever`
3. Enable **Red Guild EPGP** on the character selection screen

If you download the repository as a zip from GitHub, the folder is called `RedGuildForever-main`. Rename it to `RedGuildForever`, otherwise the game does not load it.

## Where the points live

The points are saved in the addon's own save file, `WTF\Account\<your account>\SavedVariables\RedGuildForever.lua`. Every player keeps a copy, separate for each guild.

**Sync** shares the data. The addon syncs by itself a few seconds after login and after every change. To sync by hand, click **Sync now** in the **Data** tab of the `/rgf` window or in the minimap menu.

* Editors send their data, everyone else only receives it
* The newest change of each player wins, so editors can work on different computers
* An editor who has newer entries than the sender answers with his own data, so after one sync everyone online has the same data

**Safety.** If the addon starts without data, editors cannot change anything until they click **Sync** or confirm **Start fresh**. That way an empty save file can never overwrite the real points.

**Backup.** In the **Data** tab, click **Show backup**, press Ctrl C and keep the text in Discord or a text file. To restore, paste it with Ctrl V and click **Import backup**. Importing merges, the newest change of each player wins.

**Coming from version 1.3 or older?** Those versions saved points in the officer notes. In the **Data** tab, click **Import officer notes** once. The button shows while the addon has no data yet. The notes are not changed, you can clear them yourself afterwards.

## The rules in the addon

All values below are the defaults from the guild rule book. The guild leader and editors can change every one of them in the **Settings** tab under **Guild rules**. The rules are saved with the guild data and shared with **Sync**, so every editor uses the same values, and the newest change wins.

| Setting | Default |
|---|---|
| Starting GP and lowest possible GP | 100 |
| EP per raid night (raid and bench) | 100 |
| On time bonus (raid and bench) | 25 |
| Weekly decay of EP and GP | 10 percent |
| New members until | 300 EP |
| Bidding time | 30 seconds |
| Off spec costs | 0 percent of the price, so free |
| Who may change data | the guild leader and the editors, see below |

Item prices are the base price times the slot.

| Where it drops | Default base GP |
|---|---|
| Normal boss | 100 |
| End boss | 150 |
| Very rare | 200 |

| Slot | Default multiplier |
|---|---|
| Two handed weapon | 2 |
| One handed weapon, chest, legs, head | 1.5 |
| Shoulders, hands, feet, waist, trinket, ranged | 1 |
| Wrist, neck, ring, cloak, off hand, shield, relic | 0.75 |
| Items without a slot, like tokens | 1 |

Shirts and tabards are always free. A single item can also get a fixed price with `/rgf price [item] 250`, and fixed prices are shared with Sync too.

Who wins

1. Main spec always goes before off spec
2. In main spec, members with 300 EP or more go before new members
3. Then the highest priority wins, priority is EP divided by GP
4. A tie is decided by `/roll`, the addon reads the rolls and shows the winner
5. Off spec costs the off spec percent of the price, free by default. If several people want it they roll

**Who may change data.** The guild leader and the **editors**. The guild leader picks the editors by hand, whatever their guild rank is, so a raid leader does not need an officer rank. See [Editors](#editors) below. Sync only accepts data from the guild leader and the editors.

## Minimap button

You never need to type a command. Click the coin button at the minimap.

* **Left click** opens the standings
* **Right click** opens a short menu with what you need during a raid. Editors get **Loot Master**, **Give raid EP**, **Give on time EP** and **Undo last change**. Everyone gets **Sync now** and **Settings**, and while test mode is on there is a quick **Turn test mode off**
* Everything else, like the bench, the history, the weekly decay and the backup, is in the window
* **Drag** moves the button around the minimap
* The button can be hidden in the **Settings** tab, `/rgf minimap` brings it back. The addon is also listed in the game's addon list next to the minimap

## For raiders

* A popup shows the item, the price and your own priority. Click your choice
* No addon? Whisper the loot master `ms`, `os` or `pass`
* `/rgf` opens the standings and `/rgf me` shows your own points

## For the loot master

1. Open the **Start Bidding** window. It opens by itself when you loot a corpse with rare or better items in a group, or choose **Loot Master** in the minimap menu
2. Drag the item from your bags onto the slot, or click an item that is still on the corpse. Items you saw on corpses this session stay in the list
3. Choose where it dropped, **Normal boss**, **End boss** or **Very rare**, and click **Start bidding**
4. The **Loot Master** window shows every answer in sections, Main Spec, Off Spec, Passed and No answer yet, and marks the winner. You get the bid popup too and can bid yourself
5. Change the price with the **Normal boss**, **End boss** and **Very rare** buttons, or type any price and click **Set**
6. Bidding closes by itself after 30 seconds, or click **Close bids**
7. On a tie the addon asks the tied players to `/roll` and marks the highest roll
8. Click **Award** next to the winner, or **Bank or Disenchant** if nobody wants it

Loot is announced in raid chat, so everyone can follow. The addon never writes in guild or officer chat.

The **Loot Master** button in the `/rgf` window and in the minimap menu opens the running bidding, or the Start Bidding window when nothing runs.

## Test mode

Turn it on in the **Settings** tab of the `/rgf` window, in the game's Options under AddOns, or with `/rgf test`. It simulates the whole addon, so you can try everything alone without a group.

* The addon works on a **copy of your data**. Your real points, bench and history stay exactly as they are
* You are in a **simulated raid** with up to 9 guild members. Raid EP, on time EP and the bench work with it
* Every bidding is answered by the simulated raid over a few seconds, one or two never answer, ties are rolled for them, and you can bid yourself
* Awards, decay, the editor, alts, undo, backup and import all work on the copy
* **Sync** is simulated, a made up editor sends one newer change so you see how merging works
* Nothing is sent to other players and no chat message goes out. Messages show up only in your own chat window, marked [Test]
* Every window says **Test mode** in its title, and the minimap button turns orange
* Members can use the editor tools in test mode too, and try the editor list on the copy

**Reset test data** copies the real data again, **New simulated raid** picks other guild members. The test data stays until you reset it. Test mode cannot be switched while a real bidding runs, and the addon reminds you at login if it is still on.

## Settings

The **Settings** tab and the game's Options under AddOns have the same settings.

* **Test mode**, see above
* **Show the minimap button**
* **Open Start Bidding when I loot good items in a group**
* **Guild rules**, every price, multiplier, EP amount, the decay, the new member limit and the bidding time. Type the new values and click **Save rules**, or press Enter. An example line shows right away what a two handed weapon from the end boss and a ring would cost. **Discard changes** shows the saved values again, **Reset to defaults** goes back to the rule book after asking. Wrong values like a starting GP of 0 are refused. Members can look at the rules but not change them. In test mode changed rules stay in the test data

The first three settings are only for you. The guild rules are the same for the whole guild.

## Editors

The guild leader and the editors can change all data: points, bidding and awards, the rules, decay and the backup import.

**Adding editors.** Only the guild leader adds or removes editors. Any guild rank works.

* In the `/rgf` window, **Settings** tab, section **Editors**. Type a name and click **Add** or **Remove**, or leave the box empty to use your target
* Or type `/rgf editor add Cel Dru` and `/rgf editor remove Cel Dru`. `/rgf editors` shows the list, everyone can use it

The list is saved with the guild data and shared with **Sync** and the backup. Everyone only accepts list changes the guild leader made, an editor can pass them on but cannot change the list.

**Coming from version 1.6 or older?** Until the guild leader adds the first editor, the old rank rule still applies: the guild leader and rank 1, or more ranks with `EPGP officers 2` in the **Guild Information** text. Once the list has one entry, only the list counts. To keep the current officers, click **Add the current officer ranks** once, it adds everyone the old rule allowed. Every editor needs version 1.7, older versions only accept data from the officer ranks.

## For editors

**Editing a player.** Click a player in the standings, or type `/rgf edit Cel Dru`, without a name for your target. In the editor you can

* set exact EP and GP, or use the quick buttons like +100 EP
* add a reason, which shows up in the History tab
* link the player as an alt of a main, or make an alt a main again
* put the player on the bench or take them off

Every change can be undone with **Undo last change**.


| Command | What it does |
|---|---|
| `/rgf edit Cel Dru` | open the editor, without a name for your target |
| `/rgf raid` | 100 EP to the raid and the bench |
| `/rgf ontime` | 25 EP to the raid and the bench |
| `/rgf bench` | open the bench, or `bench add Cel Dru`, `bench remove Cel Dru`, `bench clear` |
| `/rgf ep Cel Dru 50 reason` | give EP, use a minus to take |
| `/rgf gp Cel Dru 100` | give or take GP |
| `/rgf alt Cel Rog, Cel Dru` | link the alt Cel Rog to the main Cel Dru, they share points from now on |
| `/rgf unalt Cel Rog` | the alt becomes a main again |
| `/rgf decay` | weekly decay, asks before it runs |
| `/rgf undo` | undo the last change of this session |
| `/rgf price [item] 250` | fixed price for one item, `clear` removes it |
| `/rgf sync` | sync the data with everyone online |
| `/rgf export` | open the Sync tab with the backup |
| `/rgf fresh` | start with empty data for a new guild |
| `/rgf bid` | open the Start Bidding window |
| `/rgf test` | turn test mode on or off |
| `/rgf settings` | open the settings |
| `/rgf log` | last changes |
| `/rgf editors` | who may change data |
| `/rgf editor add Cel Dru` | guild leader only, make a player an editor, `editor remove Cel Dru` takes it away |
| `/rgf help` | all commands |

Names work with first and last name, in any letter case. The first name alone is enough when only one guild member has it, and the start of a name works too, so `/rgf ep Ang 50` finds Anglicus Boniface. If a name fits more than one player, the addon lists them and changes nothing. Between two names a comma is always safe, for example `/rgf alt Cel Rog, Cel Dru`.

The `/rgf` window has five tabs at the bottom, **Standings**, **Bench**, **History**, **Data** and **Settings**. Editors get **Loot Master**, **Raid EP**, **On time EP** and **Undo** below the standings, the bench tab can add your target or clear the bench, and **Weekly decay** is in the **Data** tab. Click a column header to sort.

Two editors should never award or decay at the same time. Pick one loot master per raid.

## Known limits on the Forever beta

* The addon has been tested against a simulated game API, not yet inside the Forever client. Please report Lua errors with the steps that caused them
* Some players report that the beta does not load saved addon files after a restart. If that happens, the addon starts without data and asks you to sync. Points survive as long as one player with the data is online, so **keep a backup** after big changes, for example after every raid
* Forever uses the Midnight addon rules, which can block addon messages inside instances during combat. Open bidding after the boss is dead. If the popup does not show up, whispering `ms` or `os` always works

## Changelog

Every version and its changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Development

Run the tests from the repository root with Lua 5.1.

```
lua5.1 tests/run.lua
```

Build the zip for players.

```
./build.sh
```
