# FFR:AutoBattle

Plays the battle from the gear, skills, and Vision you already equipped. Saves and pak files are not changed.

Version 0.2.24, a work in progress. Lead Programmer: Grok, by xAI. Contributor: Claude, by Anthropic. Released under the MIT license.

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

The same folder also contains `enabled.txt` and `config.ini`. Next to `main.lua` are `rows.lua`, `measure.lua`, `brace.lua`, `report.lua`, `health.lua`, `debuffs.lua`, `gauges.lua`, `espers.lua`, `limits.lua`, `kits.lua`, and `items.lua`. `enabled.txt` is what turns the mod on. You do not edit `mods.txt` for a normal install.

**Coming from 0.1.x:** extract over your old copy the same way. The old `known.lua`, `mobs.lua`, and `catalog.lua` are no longer used, and you can delete them, along with any old `battle_log.txt`. Your `config.ini` is replaced, so set any changes again.

### 4. Start the game and check

Start FINAL FANTASY RESONANCE from Steam. Load a save and enter a battle. The party should take its own commands. Press F10. The screen flashes AutoBattle Off. Press F9. The screen flashes AutoBattle: Take it Easy! The full list of keys and triggers is in Controls, below.

To confirm the files loaded, open:

`FFRS\Binaries\Win64\ue4ss\UE4SS.log`

Search for `loaded. planner v0.2.24.` If that line is there, the mod is running. It is written when the game starts, so it is near the top of a fresh log.

### If it does not load

Work down this list.

- The game was still running when you copied the files. Quit it fully and start it from Steam again.
- `dwmapi.dll` is not in the same folder as `FFRS-Win64-Shipping.exe`. The launcher folder is the wrong place.
- You extracted `FFRAutoBattle.zip` into `Win64` or into `Mods`, so `main.lua` is not at the path in step 3. Move the folder, or extract the zip again into the game folder.
- You downloaded a Source code zip. Those do not have the game folders inside them. Use `FFRAutoBattle.zip` and the `UE4SS_v3` zip.
- `UE4SS.log` does not exist. UE4SS never started. Repeat step 2.
- `UE4SS.log` exists and does not contain `loaded. planner.` Open `FFRS\Binaries\Win64\ue4ss\Mods\mods.txt`. Under the line `; Built-in keybinds, do not move up!` and above `Keybinds : 1`, add `FFRAutoBattle : 1`. Save, quit the game fully, and start it again.

## Controls

Two switches. Each press flashes a short notice. The game remembers both choices after you quit.

### Keyboard

F9 and F10 work any time: on the field, in a menu, and in a fight.

| Key | What it does | Notice |
| --- | --- | --- |
| F10 | Turns auto battle off or back on. It starts on. | AutoBattle Off, or AutoBattle On |
| F9 | Turns basic attacks on or off. It starts off. | AutoBattle: Take it Easy!, or AutoBattle: No Mercy! |

**Take it Easy** means the party uses Attack only. No spells, no items, and no MP.

**No Mercy** means the full plan. The party uses spells, items, and heals when the fight needs them.

If you turn auto battle off, play some turns yourself, and turn it back on, the party continues from the fight as it is.

### Gamepad

The right trigger turns auto battle on or off during a fight. The left trigger switches Take it Easy and No Mercy during a fight while auto battle is on. The game still receives that left-trigger press. While auto battle is off, the left trigger keeps the game's own battle action. On the field, and in menus outside a fight, both triggers keep the actions the game already uses.

| Button | What it does | When |
| --- | --- | --- |
| Right trigger | Same as F10. Auto battle on or off. | During a fight |
| Left trigger | Same as F9. Take it Easy or No Mercy. | During a fight, while auto battle is on |

The other settings are in `config.ini`. A change there needs a restart. The mod remembers the F9 and F10 choices in `state.txt`. It writes no battle logs unless you turn on `Reporting`, below.

Battle speed is the game's own button and marks. Auto battle leaves them alone.

## How a fight is played

The goal is short fights and big damage from what you set up, in any battle, with any party. The mod has no list of enemies or favorite skills. It reads the game's own data and watches what happens in the fight. The rule behind it is in [MANIFEST.md](MANIFEST.md).

- **Find what hits hard, then use it.** The mod measures the real damage of each skill on each enemy, including how often it misses. Weaknesses, gauges, and dangerous moves come from the game's data.
- **Stagger is the main source of damage.** The party builds the gauge, then goes all in while the enemy is staggered, including Limit Bursts. It does not stop to prepare during a stagger.
- **A foe that can die this turn dies this turn.** A measured killing blow comes before heals and raises.
- **The team prepares for a big hit.** When the game warns of a dangerous move, each character estimates that hit against each ally, then uses whichever guard, Shell, Protect, Cover, heal, item, or Defend saves the most of them. If nothing would save anyone, they keep hitting.
- **Multicast is a normal choice.** A spell cast on All costs the same MP and does about 40% to each target, so it is picked when that total is better.
- **An Esper on a weakness comes early.** It goes ahead of a heal nobody will die without. Raises and critical heals still come first.
- **Support earns its turn.** Buffs and debuffs go out when they fit the fight. A debuff follows the damage the party and the foe really deal.
- **Spending goes by need.** Rare items are saved for a boss, a foe with dangerous moves, or a real emergency. A fight where nothing can hurt the party spends no items.

An ally who is confused, charmed, or berserk is left to the game. If a fight stalls for five rounds with no enemy losing HP, the party escapes when the game allows it. Take it Easy never escapes.

**This is a work in progress.** It has been tested on few bosses and one party, and it wins some hard Expert fights and loses others. Some skills are not used yet, including Dualcast, Double Action, Arms Akimbo, and Magic Barrage. The last 0.1.x release stays available if you prefer it.

**If a fight goes badly,** set `Reporting = true` in `config.ini`, restart the game, and play the fight again. Then post `battle_report.txt` from the mod folder, with your party and the enemy's name. It shows what each character did and why. Set `Reporting` back to `false` afterward, and delete the files if you like.

## If a choice goes wrong

Set `Submit = false` and `Reporting = true` in `config.ini` and restart. The mod still chooses and writes the choice to `battle_log.txt` and `UE4SS.log`, and it leaves the menu open.

If FFRS QoL's auto-repeat (F8) is on, turn that off. Both mods would press the command.

## Uninstall

Quit the game fully.

To remove only FFR:AutoBattle, delete the folder `FFRS\Binaries\Win64\ue4ss\Mods\FFRAutoBattle`. If you added an `FFRAutoBattle : 1` line to `mods.txt`, delete that line too. Leave `dwmapi.dll` and the rest of `ue4ss` in place if you still want UE4SS.

To remove UE4SS as well, also delete `dwmapi.dll` and the `ue4ss` folder next to `FFRS-Win64-Shipping.exe`.

Saves stay where they are either way.

The rule every change has to pass is [MANIFEST.md](MANIFEST.md).

## License

MIT. See [LICENSE](LICENSE).
