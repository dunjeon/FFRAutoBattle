# FFR:AutoBattle

Auto battle for FINAL FANTASY RESONANCE that plays from the gear, skills, and Vision you already equipped. Turn it on and the party picks its own commands: it finds what hits hard, builds the stagger, spends Limit Bursts where they count, and guards against the moves the game warns about. Saves and pak files are not changed.

Version 1.2.4. Lead Programmer: Grok, by xAI. Contributor: Claude, by Anthropic. Released under the MIT license.

- **Works with any party.** No list of enemies, bosses, or favorite skills. Everything comes from the game's own data and from what happens in the fight.
- **Two switches.** F10 turns auto battle on or off. F9 switches between two modes: No Mercy, the full plan, and Echo, which repeats the turns you played yourself. Both work mid-fight, and both are on the gamepad triggers.
- **Optional extras.** Skip Limit Burst and Esper scenes, speed up battles, show the minimap large, and save a report of each fight. The large minimap is on; the rest are off until you turn them on.

## Install

This is a Windows mod for the Steam version of FINAL FANTASY RESONANCE. The game does not include the mod loader. You install that first, then you extract this mod into the game folder. Saves and pak files are not changed.

Close the game before you copy anything. If it is running, the new files are ignored until you quit it all the way, including from the system tray, and start it again from Steam.

### 1. Find the game folder

In Steam, right-click FINAL FANTASY RESONANCE, choose Manage, then Browse local files.

That opens the game folder. Steam's usual place for it is:

`C:\Program Files (x86)\Steam\steamapps\common\FINAL FANTASY RESONANCE`

If Steam is installed on another drive, the path is different. Use the folder Browse local files opened. Do not guess.

You should see `FFRS.exe` and a folder named `FFRS` side by side. `FFRS.exe` is only the launcher. The real game is:

`FFRS\Binaries\Win64\FFRS-Win64-Shipping.exe`

Everything below goes next to that shipping exe, not next to `FFRS.exe`.

### 2. Install UE4SS

UE4SS is a separate program. The game does not install it, and this zip does not contain it.

1. Open https://github.com/UE4SS-RE/RE-UE4SS/releases
2. Download the basic Windows zip. Its name starts with `UE4SS_v3`. This mod was written against UE4SS 3.0.1. Do not download a file whose name starts with `zDEV`. Do not download Source code.
3. Open `FFRS\Binaries\Win64`, the folder that contains `FFRS-Win64-Shipping.exe`.
4. Extract the UE4SS zip into that folder. If Windows asks to replace files, you already had a copy. Replacing it is fine if you are installing fresh.

When this step is done, these two things are in the same folder as `FFRS-Win64-Shipping.exe`:

- `dwmapi.dll`
- a folder named `ue4ss`, and inside it `UE4SS.dll`, `UE4SS-settings.ini`, and a `Mods` folder

`dwmapi.dll` is the loader. Windows runs it when the game starts. It is not a file the game shipped.

### 3. Install FFR:AutoBattle

1. On the release page, download `FFRAutoBattle.zip`. Do not download Source code.
2. Extract that zip into the game folder from step 1, the one that contains `FFRS.exe` and the `FFRS` folder. Choose to merge folders if Windows asks.

The zip already contains the `FFRS\Binaries\Win64\...` folders. You do not make those folders yourself, and you do not extract the zip into `Win64` or into `Mods`. Extracting it one level too deep is the usual mistake.

When this step is done, this file exists:

`FFRS\Binaries\Win64\ue4ss\Mods\FFRAutoBattle\Scripts\main.lua`

The same folder also contains `enabled.txt` and `config.ini`. Next to `main.lua` are `rows.lua`, `measure.lua`, `brace.lua`, `report.lua`, `health.lua`, `debuffs.lua`, `gauges.lua`, `espers.lua`, `reflect.lua`, `limits.lua`, `kits.lua`, `items.lua`, `growth.lua`, `pace.lua`, `minimap.lua`, and `echo.lua`. `enabled.txt` is what turns the mod on. You do not edit `mods.txt` for a normal install.

**Upgrading from an earlier version:** extract over your old copy the same way. The old `known.lua`, `mobs.lua`, and `catalog.lua` are no longer used, and you can delete them, along with any old `battle_log.txt`. Your `config.ini` is replaced, so set any changes again. Take it Easy and its `AttacksOnly` setting are gone: if you used it, you start in No Mercy. To get the same play, switch to Echo and give each character Attack by hand once (see [Echo](#echo)).

### 4. Start the game and check

Start FINAL FANTASY RESONANCE from Steam. Load a save and enter a battle. The party should take its own commands. Press F10. The screen flashes AutoBattle Off. Press F9. The screen flashes AutoBattle: Echo Mode. The full list of keys and triggers is in Controls, below.

To confirm the files loaded, open:

`FFRS\Binaries\Win64\ue4ss\UE4SS.log`

Search for `loaded. planner v1.2.4.` If that line is there, the mod is running. It is written when the game starts, so it is near the top of a fresh log.

### If it does not load

Work down this list.

- The game was still running when you copied the files. Quit it fully and start it from Steam again.
- `dwmapi.dll` is not in the same folder as `FFRS-Win64-Shipping.exe`. The launcher folder is the wrong place.
- You extracted `FFRAutoBattle.zip` into `Win64` or into `Mods`, so `main.lua` is not at the path in step 3. Move the folder, or extract the zip again into the game folder.
- You downloaded a Source code zip. Those do not have the game folders inside them. Use `FFRAutoBattle.zip` and the `UE4SS_v3` zip.
- `UE4SS.log` does not exist. UE4SS never started. Repeat step 2.
- `UE4SS.log` exists and does not contain `loaded. planner.` Open `FFRS\Binaries\Win64\ue4ss\Mods\mods.txt`. Under the line `; Built-in keybinds, do not move up!` and above `Keybinds : 1`, add `FFRAutoBattle : 1`. Save, quit the game fully, and start it again.

## Controls

Each switch press flashes a short notice. The mod remembers both switches after you quit, in `state.txt`.

### Keyboard

F9 and F10 work any time: on the field, in a menu, and in a fight.

| Key | What it does | Notice |
| --- | --- | --- |
| F10 | Turns auto battle off or back on. It starts on. | AutoBattle Off, or AutoBattle On |
| F9 | Switches between No Mercy and Echo. It starts on No Mercy. | AutoBattle: No Mercy!, or AutoBattle: Echo Mode |
| F8 | With `LargeMap` on, moves the field minimap to the middle of the screen and draws it large. Press again to put it back. | None |

**No Mercy** is the full plan. The party uses spells, items, Limit Bursts, and heals when the fight needs them. See [How a fight is played](#how-a-fight-is-played).

**Echo** plays your way. Each character repeats the last turn you gave them by hand. See [Echo](#echo).

In No Mercy, if you turn auto battle off, play some turns yourself, and turn it back on, the party picks up from the fight as it is.

### Gamepad

| Button | What it does | When |
| --- | --- | --- |
| Right trigger | Same as F10. Auto battle on or off. | During a fight |
| Left trigger | Same as F9. No Mercy or Echo. The game still receives the press. | During a fight, while auto battle is on |
| Left trigger | Same as F8. Large map on or off. | On the field, with `LargeMap` on. Not in a menu. |

Everywhere else, both triggers keep the actions the game gives them. With `LargeMap` on, the middle mouse button also works like F8 on the field. In a menu or on the world map it is left to the game.

## Settings

Settings are in `config.ini` in the mod folder. Edit the file, then restart the game. A missing line uses its default.

### Core features

| Setting | Default | What it does |
| --- | --- | --- |
| `Enabled` | `true` | Auto battle starts on. After you press F10, `state.txt` remembers your choice instead. |
| `Echo` | `false` | Starts in Echo. After you press F9, `state.txt` remembers your choice instead. |
| `EchoKeep` | `true` | Saves Echo's record in `echo.txt`, so it lasts from one session to the next. `false` keeps it only until you quit. |
| `Submit` | `true` | `false` makes the mod choose and log a command but leave the menu for you. See [Reporting a problem](#reporting-a-problem). |
| `TakeOverKey` | `F10` | The auto battle key. |
| `MenuKey` | `F9` | The No Mercy / Echo key. |
| `ItemPrice` | `5000` | No Mercy only. An item whose buy price is above this stays in the bag. Raise it to let the party spend more expensive items. |
| `EsperLevelGap` | `3` | No Mercy only. An Esper is not called in a fight that only looks dangerous when every foe is at least this many levels under the character who would call it. A boss, or a hit that would kill an ally, still gets the call. `0` turns this off. `-1` never calls an Esper; you can still call one by hand. |
| `ResonanceLevelGap` | `0` | No Mercy only. The same as `EsperLevelGap`, for the Resonance wheel. The wheel is skipped when every foe is at least this many levels under every standing ally, unless it is a boss or an ally is down or about to die. `0` turns this off. `-1` leaves every wheel to you; the mod never picks or skips. |

### Optional settings

Each of these is off until you turn it on.

| Setting | Default | What it does |
| --- | --- | --- |
| `SkipScenes` | `false` | Skips Limit Burst scenes, Vision finish scenes, an Esper's summon, and that Esper's own attack. The skip waits until the game allows it, so the hit still lands and the battle camera comes back. Other attacks and story scenes play as normal. |
| `Turbo` | `false` | Experimental. Plays a fight's actions at four times the speed of the battle speed button's fastest mark. It starts with the first command, so the opening of a fight plays at normal speed. The command menu, Limit Bursts, Vision finishes, and Esper scenes stay at normal speed. Speed goes back to normal when the battle result begins. Turbo only runs while AutoBattle is On. Turn auto battle off in a fight and the speed goes back to normal until you turn it on again. The game keeps writing its own speed back during a fight, and Turbo sets its rate again each time; `UE4SS.log` says how often after each fight. If anything looks wrong, turn it off. |
| `LargeMap` | `true` | Lets F8, the left trigger, and the middle mouse button show the field minimap large in the middle of the screen. The game draws it at the bigger size, so it stays sharp. It only turns on outside a fight, and it comes back large on its own after a conversation or a new area. |
| `MapKey` | `F8` | The large map key. |
| `MapSize` | `80` | Size of the large map, as a percent of the screen height, from 20 to 100. |
| `Reporting` | `false` | Writes each fight to `battle_report.txt` in the mod folder, keeping the last five. Use it to report a problem. |
| `LevelGate` | `false` | For development only. Leave it off. |

Battle speed otherwise stays the game's own button and marks. Only `Turbo` goes past the last mark.

## How a fight is played

The goal is short fights and big damage from what you set up, in any battle, with any party. The mod reads the game's own data and watches what happens in the fight. The rule every change has to pass is in [MANIFEST.md](MANIFEST.md).

- **Find what hits hard, then use it.** The mod measures the real damage of each skill on each enemy, including how often it misses. Weaknesses, gauges, and dangerous moves come from the game's data. A skill that does nothing to an enemy is set aside against it until that enemy's status changes.
- **Stagger is the main source of damage.** The party builds the gauge, then goes all in while the enemy is staggered, including Limit Bursts. It does not stop to prepare during a stagger.
- **Every Limit Burst has a job.** On a boss or a dangerous fight, each Limit is read from the game's own row and used for what it does: a party raise when two are down, a barrier before a dangerous move, acting twice or a stagger bonus while the enemy is staggered, a gauge mark or a bar fill before the break, a hit that lands the break, and a full bar spent rather than held. A one-gauge Limit waits for a two-gauge Limit on a long boss fight, if that bigger Limit can land. A common fight saves the bar.
- **A foe that can die this turn dies this turn.** A measured killing blow comes before heals and raises. A Limit Burst can be that blow on a boss or a dangerous fight, but another hit that kills goes first, so the Limit is kept.
- **The team prepares for a big hit.** When the game warns of a dangerous move, each character estimates that hit against each ally, then uses whichever guard, Shell, Protect, Cover, heal, item, or Defend saves the most of them. If nothing would save anyone, they keep hitting.
- **Multicast is a normal choice.** An All cast is its own row, with that row's own magnification.
- **The Resonance wheel is picked, or skipped in an easy fight.** When every foe is `ResonanceLevelGap` or more levels under every standing ally, the mod skips the wheel, the same as a hand skip. A boss, or an ally who is down or about to die, still gets a pick. At `-1` every wheel is yours, and the mod never picks or skips. Otherwise, a wheel that opens after every foe is already at 0 HP is skipped, so no finisher goes to an empty field.
- **An Esper on a weakness comes early.** It goes ahead of a heal nobody will die without. Raises and critical heals still come first, unless every ally in danger has another healer who acts before the foe and can pay for the heal. Then the Esper goes now and that healer takes the heal.
- **A healing Esper is a party heal.** When enough of the party is under half that a party heal would be the pick, an Esper whose moves heal the party is called first, on a boss or a dangerous fight. The usual Esper rules still hold: one out at a time, and the caster keeps MP for a heal.
- **Reflect is read on everyone.** A spell is not cast at an ally or a foe under Reflect, whatever put it there. A heal goes to an ability or an item instead. A heal that lands on a foe is flagged in the report.
- **Support earns its turn.** Buffs and debuffs go out when they fit the fight. A debuff follows the damage the party and the foe really deal.
- **Spending goes by need.** Items above `ItemPrice` stay in the bag. A buy price far above every other item is held back, and spent only when no cheaper item covers someone down or about to die. A fight where nothing can hurt the party spends no items.

An ally who is confused, charmed, or berserk is left to the game. If a fight stalls for five rounds with no enemy losing HP, the party escapes when the game allows it.

## Echo

Echo repeats your own play. You play a turn for each character once, by hand. After that, every time that character's turn comes up, Echo sends the same turn again, until you play a new one.

### Using it

1. Press F9 until the screen flashes **AutoBattle: Echo Mode**. Echo only records while it is the mode.
2. Press F10 to turn auto battle off, and play one turn for each character the way you want it repeated. You can also leave auto battle on: a character with nothing on record has their turn handed to you, and the screen flashes **Echo: (name)'s turn is yours**.
3. Press F10 to turn auto battle back on. From the next turn on, each character repeats what you gave them.
4. To change the plan, do it again: turn auto battle off, play the new turns, and turn it back on. Whatever you play by hand replaces that character's turn on record.

A turn is everything that character did when their turn came up. A stagger bonus action right after it is part of the same turn, and is repeated in the same order.

### What is repeated exactly

- The same command, with everything in it. Dualcast, Double Action, and the other commands that hold picks are repeated with the same picks, in the same order.
- The same targets, as long as the game still lets them be targeted. A Cure on someone at full HP, or a buff on someone who already has it, goes out as you sent it. Echo does not judge your choices: it is your turn, repeated.

### What can change

Only a target, and only when the game won't take the one you picked:

- A foe that fell: the foe the party is already hitting, otherwise the game's next pick.
- An ally who is down: the standing ally lowest on HP.
- A skill you aimed at a group, or an All cast: every target that is up now.
- In a later fight the old foes are gone, so a single-target hit goes to the foe the party is already hitting, otherwise the game's first pick.

### Never echoed, by design

Echo leaves these to you on purpose. They are not missing features. Each one is a choice for the moment, not a move to repeat every turn: a raise is for someone who just fell, an item is spent, a Limit Burst waits on its bar, an Esper and the wheel each come once.

| Not echoed | What happens instead |
| --- | --- |
| Items | Not recorded. Use them by hand. |
| Raises, by spell or by item | Not recorded. Raise by hand. |
| Limit Bursts | Not recorded. Turn auto battle off and use one by hand when the bar is full. |
| Esper calls | Not recorded. Call an Esper by hand. |
| A summoned Esper's own turns | Not recorded. It acts on its own, and Echo stays out of it. |
| The Resonance wheel | Never recorded and never picked or skipped by Echo. Every wheel is yours. The screen flashes **Echo: the wheel is yours**. |
| A character who is confused, charmed, or berserk | Left to the game. Nothing they do is recorded. |

A turn that uses any of these, including a Dualcast or Double Action with one among its picks, is left off the record. That character keeps repeating the last turn that was recorded. The log shows `skipped` and the reason.

### When the turn comes back to you

Echo never picks a different skill. If a character's turn on record can't go out, the menu is left open for you, and the screen flashes **Echo: (name)'s turn is yours**. That happens when:

- there is no turn on record for them yet,
- they don't have the MP for it,
- the game won't let them use it now, for example while silenced,
- a skill in it is no longer equipped, after a Vision or ability change. That includes a pick inside a Dualcast or Double Action, and the basic Attack, which changes with the Vision,
- there is nobody it can target.

After a gear change, play the character's new turn by hand once and Echo repeats the new one. The old turn is not deleted until you play a new one, so if you equip the old skills again, it works again.

### The record

- Echo records only while Echo is the mode. Auto battle can be on or off. In No Mercy nothing is recorded, and the record is left as it was.
- Each character's turn is kept by name, so it carries from fight to fight. With `EchoKeep` on (the default), it is saved in `echo.txt` in the mod folder, so it is still there the next time you play.
- After a party change, the record is kept. A new member has nothing on record, so their first turn is handed to you, and is repeated from then on. Everyone who stayed keeps their turn. A heal or buff on record for a member who left goes to the standing ally lowest on HP. A member who left keeps their turn on record for when they come back.
- An ally who joins partway through a fight is recorded like anyone else.
- To clear the record, quit the game and delete `echo.txt`.

### Settings that don't apply in Echo

`ItemPrice`, `EsperLevelGap`, and `ResonanceLevelGap` are for No Mercy's own choices. In Echo, items, Espers, and the wheel are all yours (see [Never echoed, by design](#never-echoed-by-design)), so these settings have nothing to do. `SkipScenes`, `Turbo`, `LargeMap`, `LevelGate`, `Reporting`, and `Submit` work the same in both modes. With `Submit = false`, Echo logs the turn it would send and leaves the menu to you.

### Tracking Echo

Every Echo event is an `echo:` line in `UE4SS.log`, even with `Reporting` off:

| Line | Meaning |
| --- | --- |
| `kept` | A turn you played was recorded. `new turn` starts a character's turn; `same turn` adds a bonus action to it. |
| `skipped` | A turn you played was not recorded, and why: one of the things [never echoed](#never-echoed-by-design), or a command the game made for the character. |
| `sent` | A recorded turn went out, with its targets. |
| `retarget` | A foe or ally fell during this fight, and that action took another target. |
| `new fight target` | The turn was recorded in another fight, so its targets changed. Written once per action, per character, per fight. |
| `handed back` | The turn, or the wheel, was left to you, and why. |
| `dropped` | A turn on record from an older version used something that is never echoed, and was removed. |
| `failed` | The game refused the command. Worth reporting. |

With `Reporting` on, the same events are lines in `battle_report.txt`. Each repeated turn is marked `ECHO`, each fight's header names the mode, and each fight's report ends with an `echo:` count of each kind. A fight the party lost shows `PARTY WIPED`, then `FIGHT RESTARTED` when the game starts it over, and the report's `result:` line counts both.

## Known limits

- In No Mercy, commands that hold other picks are left to you, including Dualcast, Double Action, Arms Akimbo, Magic Barrage, Magic Boost, and Reckless Abandonment. Turn auto battle off for that turn to use one. Echo repeats them as you sent them.
- Echo is new in 1.1. It has been played with Dualcast, Double Action, group skills, a foe that falls, a gear change, and the hand-back cases. If a turn goes wrong, see [Tracking Echo](#tracking-echo). An old `shapes.txt` from a 1.0.1 test build is no longer read and can be deleted.
- If you skip a Resonance wheel by hand while the mod is about to skip it, the mod stops for that wheel and leaves it to you. That case is new and not yet tested in game; `UE4SS.log` shows `wheel skipped by hand` or `wheel skipped` when it happens.
- It wins some hard Expert fights and loses others. A loss is worth reporting. See below.
- FFRS QoL's auto-repeat (its F8) presses commands too. Turn it off while auto battle is on, or both mods press the command.

## Reporting a problem

1. Set `Reporting = true` in `config.ini` and restart the game.
2. Play the fight again.
3. Post `battle_report.txt` from the mod folder, with your party and the enemy's name. It shows what each character did and why.

If a single choice looks wrong, also set `Submit = false`. The mod still chooses and writes the choice to the report and to `UE4SS.log`, but it leaves the menu open for you.

Set both back afterward. You can delete the report files any time.

## Uninstall

Quit the game fully.

To remove only FFR:AutoBattle, delete the folder `FFRS\Binaries\Win64\ue4ss\Mods\FFRAutoBattle`. If you added an `FFRAutoBattle : 1` line to `mods.txt`, delete that line too. Leave `dwmapi.dll` and the rest of `ue4ss` in place if you still want UE4SS.

To remove UE4SS as well, also delete `dwmapi.dll` and the `ue4ss` folder next to `FFRS-Win64-Shipping.exe`.

Saves stay where they are either way.

## License

MIT. See [LICENSE](LICENSE).
