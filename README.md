# RedGuildForever

An EPGP loot addon for our guild on World of Warcraft Forever. It follows the guild loot rule book, so the addon and the Discord rules always agree.

Version 1.1.1, updated on 8 October 2026 for the Forever beta client (interface 16001).

## What it does

Show up and you go up the list, take loot and you go down the list.

* Raiders get a popup when loot is up for bids and click **Main spec**, **Off spec** or **Pass**
* The loot master sees every bid sorted by the rules and clicks **Award**
* EP for the raid night and the on time bonus go to everyone in the raid and on the bench
* Alts share points with their main
* Weekly decay, undo, price overrides and a standings window
* The windows are built from Blizzard's own frame templates, so they look like the guild and character windows of the game

## Install

1. Download the latest `RedGuildForever.zip` from the releases, or build it with `./build.sh`
2. Extract it so the folder sits at `World of Warcraft\_classic_beta_\Interface\AddOns\RedGuildForever`
3. Enable **Red Guild EPGP** on the character selection screen

If you download the repository as a zip from GitHub, the folder is called `RedGuildForever-main`. Rename it to `RedGuildForever`, otherwise the game does not load it.

## Where the points live

Points are stored in the **officer note** of every guild member, the same way the classic EPGP addons did it.

| Officer note | Meaning |
|---|---|
| `1250,300` | 1250 EP and 300 GP |
| `1250,300 tank` | same, text after the numbers is kept |
| `@Cel Dru` | this character is an alt of Cel Dru and uses his points |

GP always includes the starting 100, so a new player has `0,100`.

This matters on the Forever beta, because the client currently writes addon data on logout but does not read it again on login. Officer notes are saved by Blizzard, so the points can never get lost. Everyone with the addon who can read officer notes sees the same numbers.

Members who cannot read officer notes get the standings from an officer through the addon. Make sure at least one officer with the addon is online.

## The rules in the addon

| Setting | Value |
|---|---|
| Starting GP and lowest possible GP | 100 |
| EP per raid night (raid and bench) | 100 |
| On time bonus (raid and bench) | 25 |
| Weekly decay of EP and GP | 10 percent |
| New members until | 300 EP |
| Bidding time | 30 seconds |
| Officer ranks | rank index 0 and 1 |

Item prices are the base price times the slot.

| Where it drops | Base GP |
|---|---|
| Normal boss | 100 |
| End boss | 150 |
| Very rare | 200 |

| Slot | Multiplier |
|---|---|
| Two handed weapon | 2 |
| One handed weapon, chest, legs, head | 1.5 |
| Shoulders, hands, feet, waist, trinket, ranged | 1 |
| Wrist, neck, ring, cloak, off hand, shield, relic | 0.75 |
| Items without a slot, like tokens | 1 |

Who wins

1. Main spec always goes before off spec
2. In main spec, members with 300 EP or more go before new members
3. Then the highest priority wins, priority is EP divided by GP
4. A tie is decided by `/roll`, the addon reads the rolls and shows the winner
5. Off spec is free, if several people want it they roll

The values live at the top of `Core.lua` and `Pricing.lua`. Every officer must use the same version, so change them in this repository and not locally.

## For raiders

* A popup shows the item, the price and your own priority. Click your choice
* No addon? Whisper the loot master `ms`, `os` or `pass`
* `/rgf` opens the standings and `/rgf me` shows your own points

## For the loot master

1. Type `/rgf bid ` and shift click the item. Add `boss` or `rare` for end boss or very rare items, or switch it in the loot window
2. Wait for the bids. Bidding closes by itself after 30 seconds, or click **Close bids**
3. On a tie the addon asks the tied players to `/roll` and marks the highest roll
4. Click **Award** next to the winner, or **Bank or DE** if nobody wants it

Everything is announced in raid chat, so everyone can follow.

## For officers

| Command | What it does |
|---|---|
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
| `/rgf sync` | send the standings to everyone |
| `/rgf log` | last changes |
| `/rgf help` | all commands |

Names work with first and last name, in any letter case. The first name alone is enough when only one guild member has it, and the start of a name works too, so `/rgf ep Ang 50` finds Anglicus Boniface. If a name fits more than one player, the addon lists them and changes nothing. Between two names a comma is always safe, for example `/rgf alt Cel Rog, Cel Dru`.

The `/rgf` window has three tabs at the bottom, **Standings**, **Bench** and **History**. Officers get buttons for raid EP, on time EP, decay and undo, and the bench tab can add your target or clear the bench. Click a column header to sort.

Two officers should never award or decay at the same time. Pick one loot master per raid.

## Known limits on the Forever beta

* The addon has been tested against a simulated game API, not yet inside the Forever client. Please report Lua errors with the steps that caused them
* Price overrides and the bench list are saved addon data, which the beta may forget after logging out. Points are not affected
* Forever uses the Midnight addon rules, which can block addon messages inside instances during combat. Open bidding after the boss is dead. If the popup does not show up, whispering `ms` or `os` always works
* Officer notes are limited to 31 characters, extra text after the numbers gets cut

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
