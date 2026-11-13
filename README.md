# RedGuildForever

An EPGP loot addon for our guild on World of Warcraft Forever. It follows the guild loot rule book, so the addon and the Discord rules always agree.

Version 2.1.1, updated on 13 November 2026 for World of Warcraft Forever 1.60.1 (interface 16001).

## What it does

Show up and you go up the list, take loot and you go down the list.

* Raiders get a popup when loot is up for bids and click **Main spec**, **Off spec** or **Pass**
* The loot master sees every bid sorted by the rules and clicks **Award**. Several items can be up for bids at once
* **Start raid** gives the on time bonus, **End raid** gives the EP for the raid night, to everyone in the raid and on the bench
* Two raids on the same evening work, every change of every loot master counts and nobody gets the raid EP twice
* Alts share points with their main
* Weekly decay with a reminder, undo for every change, price overrides and a standings window with search
* Players without the addon whisper `ms`, `os` or `pass`, and `!ep`, `!bid`, `!top` or `!loot` to look things up
* Points are saved in the addon's own save file, shared with **Sync** and backed up by themselves
* A **Start Bidding** window to drag items in or pick them from the corpse
* A **test mode** in the settings that simulates the whole addon, so you can try everything alone
* The windows are built from Blizzard's own frame templates, so they look like the guild and character windows of the game

## Install

1. Download `RedGuildForever.zip` from CurseForge or from the [releases on GitHub](https://github.com/Celevius/RedGuildForever/releases), or build it with `./build.sh`
2. Extract it so the folder sits at `World of Warcraft\_forever_\Interface\AddOns\RedGuildForever`
3. Enable **Red Guild EPGP** on the character selection screen

Do not use the green **Code** button and **Download ZIP** on GitHub. That zip has the folder `RedGuildForever-main`, and the game only loads the addon when the folder is called `RedGuildForever` like the `.toc` file.

**Updating from version 1.7 or older?** Version 2.0 syncs in a new way and does not talk to 1.7 and older. Everyone who changes data has to update at the same time. Your points stay, they become the starting points of the new version.

## Where the points live

The points are saved in the addon's own save file, `WTF\Account\<your account>\SavedVariables\RedGuildForever.lua`. Every player keeps a copy, separate for each guild.

**Every change is kept.** The addon never stores a total. Every award, raid EP, decay, alt link and undo is kept as a change, and the points are the starting points plus all changes in the order they happened. That is why two loot masters in two raids can give out loot at the same time, and both changes count, even when they cannot reach each other during the raid.

**Sync** hands the changes to everyone online. The addon syncs by itself after login, every 15 minutes and right after every change. To sync by hand, click **Sync now** in the **Data** tab of the `/rgf` window or in the minimap menu.

* Editors send, everyone else only receives
* Both sides compare a short summary first, so only what is missing is sent
* The game takes ten addon messages at once and then one per second. The addon counts that itself, so no message is refused, and it always keeps room for bids and auctions, which go out right away
* During a boss fight the game takes no addon messages. They wait and go out after the fight
* A transfer that arrives with a piece missing is thrown away and asked for again
* The bench, the rules, fixed prices, the editor list and the history are shared too

**Safety.** If the addon starts without data, editors cannot change anything until they click **Sync** or confirm **Start fresh**. That way an empty save file can never overwrite the real points.

**Automatic backup.** Ten minutes after changes, at the end of a raid and when you log out, the addon writes a backup into a second save file of your character, `WTF\Account\<your account>\<realm>\<character>\SavedVariables\RedGuildForever.lua`. The newest three are kept. If the main save file comes back empty, the newest backup is put back by itself and sync brings the newest changes. The **Data** tab shows the date and has **Restore automatic backup**.

**Backup for Discord.** In the **Data** tab, click **Show backup**, press Ctrl C and keep the text in Discord or a text file. To restore, paste it with Ctrl V and click **Import backup**. Importing merges, nothing is counted twice. Backups of version 1.7 can be imported too.

**Coming from version 1.3 or older?** Those versions saved points in the officer notes. In the **Data** tab, click **Import officer notes** once. The button shows while the addon has no data yet. The notes are not changed, you can clear them yourself afterwards.

## The rules in the addon

All values below are the defaults from the guild rule book. The guild leader and editors can change every one of them in the **Rules** tab. The rules are saved with the guild data and shared with **Sync**, so every editor uses the same values, and the newest change wins.

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

**Raid EP once per night.** The EP for the raid night and the on time bonus count once per player in 12 hours. With two raids on one evening, a player on the bench, or an alt in the second raid, gets them once. The addon lists who already got them.

**Who may change data.** The guild leader and the **editors**. The guild leader picks the editors by hand, whatever their guild rank is, so a raid leader does not need an officer rank. See [Editors](#editors) below. Sync only accepts data from the guild leader and the editors.

## Minimap button

You never need to type a command. Click the coin button at the minimap.

* **Left click** opens the standings
* **Right click** opens a short menu with what you need during a raid. Editors get **Loot Master**, **Start raid** or **End raid** and **Undo last change**. Everyone gets **Sync now** and **Settings**, and while test mode is on there is a quick **Turn test mode off**
* Everything else, like the bench, the history, the weekly decay and the backup, is in the window
* **Drag** moves the button around the minimap
* The button can be hidden in the **Settings** tab, `/rgf minimap` brings it back. The addon is also listed in the game's addon list next to the minimap

## For raiders

* A popup shows the item, the price and your own priority. Click your choice. When several items are up for bids, the popup shows one after the other
* When an item is given out, a small popup at the top of the screen shows everyone with the addon who won it, the item and the price. It goes away after five seconds, or right away with a click. You can turn it off in the **Settings** tab with **Show a popup with the winner when loot is given out**
* When you win, the loot master's addon whispers you the item and your new priority
* `/rgf` opens the standings and `/rgf me` shows your own points. Hover a player to see the last items they got

**No addon?** Whisper the loot master, or anyone with the addon.

| Whisper | Answer |
|---|---|
| `ms`, `os`, `pass` | your bid, while bidding is open. With several items add the number, for example `ms 2` |
| `!ep` | your EP, GP, priority and place |
| `!ep Lisa` | the same for another player |
| `!bid` | what is up for bids right now, the price and the time left |
| `!top`, `!top mage` | the five highest priorities, or the five of one class |
| `!loot`, `!loot Lisa` | the last items you got, or another player got |
| `!help` | this list |

Every bid gets an answer, also when bidding is closed or nothing is open. A `+` for a raid invite gets no answer.

## For the loot master

**The raid night.**

1. Click **Start raid** in the **Raid** tab or in the minimap menu. Everyone in the raid and on the bench gets the on time bonus, and the loot list of the raid starts
2. The addon notes everyone who joins the raid
3. Click **End raid** at the end. Everyone in the raid and on the bench gets the raid EP. When players left early, the addon asks whether they get the raid EP too
4. The **Raid** tab shows the loot of the raid. **Loot list for Discord** opens it as text to copy

**Loot.**

1. Open the **Start Bidding** window: choose **Loot Master** in the minimap menu, click **Loot Master** in the `/rgf` window or type `/rgf bid`. It never opens by itself, unless you turn on **Open Start Bidding when I loot good items in a group** in the **Settings** tab
2. Drag the item from your bags onto the slot, or click an item that is still on the corpse. Items you saw on corpses this session stay in the list
3. Choose where it dropped, **Normal boss**, **End boss** or **Very rare**, and click **Start bidding**. **Bid on all** opens every rare and better item of the corpse at once, numbered 1, 2, 3 in one raid announcement
4. The **Loot Master** window shows every answer in sections, Main Spec, Off Spec, Passed and No answer yet, and marks the winner. With several items, the buttons at the top switch between them. Hover a bidder to see their last items. You get the bid popup too and can bid yourself
5. Change the price with the **Normal boss**, **End boss** and **Very rare** buttons, or type any price and click **Set**
6. Bidding closes by itself after 30 seconds, or click **Close bids**
7. On a tie the addon asks the tied players to `/roll` and marks the highest roll
8. Click **Award** next to the winner, or **Bank or Disenchant** if nobody wants it

Loot is announced in raid chat, so everyone can follow. The addon never writes in guild or officer chat.

The **Loot Master** button in the `/rgf` window and in the minimap menu opens the running bidding, or the Start Bidding window when nothing runs.

## Test mode

Turn it on in the **Settings** tab of the `/rgf` window, in the game's Options under AddOns, or with `/rgf test`. It simulates the whole addon, so you can try everything alone without a group.

* The addon works on a **copy of your data**. Your real points, bench and history stay exactly as they are
* You are in a **simulated raid** with up to 9 guild members. Start raid, End raid, raid EP, on time EP and the bench work with it
* Every bidding is answered by the simulated raid over a few seconds, one or two never answer, ties are rolled for them, and you can bid yourself
* Awards, decay, the editor, alts, undo, backup and import all work on the copy
* **Sync** is simulated, a made up editor sends one change so you see how it arrives
* Nothing is sent to other players and no chat message goes out. Messages show up only in your own chat window, marked [Test]. Real whispers get no answer while test mode is on
* Every window says **Test mode** in its title, and the minimap button turns orange
* Members can use the editor tools in test mode too, and try the editor list on the copy

**Reset test data** copies the real data again, **New simulated raid** picks other guild members. The test data stays until you reset it. Test mode cannot be switched while a real bidding runs, and the addon reminds you at login if it is still on.

## The window

`/rgf` opens the window. It has six tabs at the bottom.

* **Standings** with a search box, a class filter and **Copy for Discord**, which copies the shown list as text. Click a column header to sort. Editors get **Loot Master**, **Raid EP**, **On time EP** and **Undo** at the bottom
* **Raid** with **Start raid** and **End raid**, the bench and the loot of the raid. Editors can add their target to the bench or clear it
* **History** with every change of every editor. Editors can undo any change with **Undo** in its row, also an old one or one of another editor. Undone changes stay in the list, marked as undone
* **Rules** with every price, multiplier, EP amount, the decay, the new member limit and the bidding time. Type the new values and click **Save rules**, or press Enter. An example line shows right away what a two handed weapon from the end boss and a ring would cost. **Discard changes** shows the saved values again, **Reset to defaults** goes back to the rule book after asking. Wrong values like a starting GP of 0 are refused. Members can look at the rules but not change them. In test mode changed rules stay in the test data
* **Data** with sync, the weekly decay, the backups and the imports
* **Settings** with test mode, the minimap button, **Open Start Bidding when I loot good items in a group** (off by default), **Show a popup with the winner when loot is given out** (on by default) and the editors. These settings are only for you, except the editors

The game's Options under AddOns show the settings and the rules on one page.

## Editors

The guild leader and the editors can change all data: points, bidding and awards, the rules, decay and the backup import.

**Adding editors.** Only the guild leader adds or removes editors. Any guild rank works.

* In the `/rgf` window, **Settings** tab, section **Editors**. Type a name and click **Add** or **Remove**, or leave the box empty to use your target
* Or type `/rgf editor add Cel Dru` and `/rgf editor remove Cel Dru`. `/rgf editors` shows the list, everyone can use it

The list is saved with the guild data and shared with **Sync** and the backup. Everyone only accepts list changes the guild leader made, an editor can pass them on but cannot change the list.

**Coming from version 1.6 or older?** Until the guild leader adds the first editor, the old rank rule still applies: the guild leader and rank 1, or more ranks with `EPGP officers 2` in the **Guild Information** text. Once the list has one entry, only the list counts. To keep the current officers, click **Add the current officer ranks** once, it adds everyone the old rule allowed.

## For editors

**Editing a player.** Click a player in the standings, or type `/rgf edit Cel Dru`, without a name for your target. In the editor you can

* set exact EP and GP, or use the quick buttons like +100 EP
* add a reason, which shows up in the History tab
* link the player as an alt of a main, or make an alt a main again
* put the player on the bench or take them off

**Alts.** When you link an alt, its EP and the GP above the start move to the main. Undo takes the link back and the alt has its own points again. An alt that becomes a main again starts at 0 EP.

**Undo.** **Undo last change** takes back your newest change, also one from an earlier day. The **History** tab can undo any change.

**Weekly decay.** The **Data** tab shows when the last decay was and who ran it. A week later the addon reminds editors after login and at the end of a raid. If someone ran a decay in the last six days, also another editor, the addon warns before a second one.

| Command | What it does |
|---|---|
| `/rgf edit Cel Dru` | open the editor, without a name for your target |
| `/rgf start` | start the raid, gives the on time EP and starts the loot list |
| `/rgf end` | end the raid, gives the raid EP |
| `/rgf raid` | 100 EP to the raid and the bench, once per night |
| `/rgf ontime` | 25 EP to the raid and the bench, once per night |
| `/rgf bench` | open the bench, or `bench add Cel Dru`, `bench remove Cel Dru`, `bench clear` |
| `/rgf ep Cel Dru 50 reason` | give EP, use a minus to take |
| `/rgf gp Cel Dru 100` | give or take GP |
| `/rgf alt Cel Rog, Cel Dru` | link the alt Cel Rog to the main Cel Dru, they share points from now on |
| `/rgf unalt Cel Rog` | the alt becomes a main again |
| `/rgf decay` | weekly decay, asks before it runs |
| `/rgf undo` | undo your newest change |
| `/rgf price [item] 250` | fixed price for one item, `clear` removes it |
| `/rgf loot` | the loot of the raid, or `loot Cel Dru` for the items of a player |
| `/rgf sync` | sync the data with everyone online |
| `/rgf export` | open the Data tab with the backup |
| `/rgf discord` | the standings as text for Discord |
| `/rgf fresh` | start with empty data for a new guild |
| `/rgf bid` | open the Start Bidding window |
| `/rgf test` | turn test mode on or off |
| `/rgf settings` | open the settings |
| `/rgf log` | last changes |
| `/rgf check` | check that your game version has everything the addon needs |
| `/rgf editors` | who may change data |
| `/rgf editor add Cel Dru` | guild leader only, make a player an editor, `editor remove Cel Dru` takes it away |
| `/rgf help` | all commands |

Names work with first and last name, in any letter case. The first name alone is enough when only one guild member has it, and the start of a name works too, so `/rgf ep Ang 50` finds Anglicus Boniface. If a name fits more than one player, the addon lists them and changes nothing. Between two names a comma is always safe, for example `/rgf alt Cel Rog, Cel Dru`.

Pick one loot master per raid. Two raids at the same time each have their own loot master.

## Known limits

* The addon is tested against a simulated game and checked against the published functions of Forever 1.60.1, but the author's tests do not run inside the game. Type `/rgf check` to see whether your game version has everything the addon needs, and please report Lua errors with that report and the steps that caused them
* A save file can get lost, for example after a crash. The automatic backup in the second save file is meant for that. **Keep a backup in Discord** after big changes too
* Trial and Veteran accounts cannot send addon messages in Forever. Such a player can read the standings and bids by whisper, the popup falls back to a whisper by itself, but cannot work as an editor
* Forever blocks addon messages during boss fights. Open bidding after the boss is dead. Messages from a fight wait and go out afterwards, and whispering `ms` or `os` always works
* Every change is kept forever, so the data grows by a few hundred changes a month. A player who starts with an empty save file gets the whole history once, at one message per second. With a few thousand changes that takes around ten minutes in the background

## Changelog

Every version and its changes are listed in [CHANGELOG.md](CHANGELOG.md).

## License

Red Guild EPGP is free software under the [MIT License](LICENSE). You may use, change and share it, also in your own addons, as long as you keep the copyright notice and the license text. It comes without any warranty.

## Development

Run the tests from the repository root with Lua 5.1.

```
lua5.1 tests/run.lua
```

Build the zip for players. It lands in `dist/RedGuildForever.zip` with the folder `RedGuildForever` inside, the tests, `build.sh` and the notes for Claude stay out.

```
./build.sh
```

**Releasing a version.** Push a tag with the version, for example `git tag v2.0.1` and `git push origin v2.0.1`. The GitHub workflow runs the tests, builds the zip and attaches it to a new GitHub release, with the changelog entry as release notes. Upload that zip to CurseForge. The `.pkgmeta` file is there for the CurseForge packager, in case the project gets connected to the repository later.
