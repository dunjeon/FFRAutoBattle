# FFR:AutoBattle

Plays the battle from the gear, skills, and Vision you already equipped. Saves and pak files are not changed.

Version 0.1.12. Lead Programmer: Grok, by xAI. Released under the MIT license.

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

The same folder also contains `enabled.txt`, `config.ini`, `known.lua` is next to `main.lua`, and so is `mobs.lua`. `enabled.txt` is what turns the mod on. You do not edit `mods.txt` for a normal install.

### 4. Start the game and check

Start FINAL FANTASY RESONANCE from Steam. Load a save and enter a battle. The party should take its own commands. Press F10. The screen flashes AutoBattle Off. Press F9. The screen flashes AutoBattle: Take it Easy! The full list of keys and triggers is in Controls, below.

To confirm the files loaded, open:

`FFRS\Binaries\Win64\ue4ss\UE4SS.log`

Search for `loaded. planner.` If that line is there, the mod is running. The line is written when the game starts, so it is near the top of a fresh log.

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

The triggers do those same two things, and only during a fight. On the field, and in menus outside a fight, they keep doing what the game already uses them for.

| Button | What it does | When |
| --- | --- | --- |
| Right trigger | Same as F10. Auto battle on or off. | During a fight |
| Left trigger | Same as F9. Take it Easy or No Mercy. | During a fight |

The other settings are in `config.ini`. A change there needs a restart. A written account of each fight is added to `battle_log.txt` in this folder.

## How a fight is played

The battle lessons are the policy. There is one of them.

One planner reads the whole field and fills the next slot. The characters do not each pick a favorite enemy.

1. The field is every living enemy and every ally who can act. The log line is `field:` then `plan adds` or `plan sync`.
2. Raise the fallen. The same ally is not raised again until they are standing, and a retry waits until the party has acted. Heal under 30% HP. Under 50% only when MP is above half and either several allies are hurt or the bonus window just ended. While a danger move is still up, that recover line is 65% for the lowest ally, and it does not wait for the bonus. A heal spell is cast when its cost still fits. A potion is the spend when it does not. When three or more allies are under half, a party heal is chosen over a single cure. One or two hurt allies keep the single cure. The ally who is the only one able to pay a weakness on the current pool keeps chipping while the hurt ally is at or above 15% and someone else can still heal. A claimed heal is not cast again that round. Rare items stay in the bag. A Pot fight spends nothing.
3. Above half MP any fitting spell can be spent. From 20% to half, only a heal, a heavy stagger, or a known weakness. Under 20%, a known weakness whose cost still fits, or a free attack. One Ether when that weakness does not fit. One Ether per round.
4. Scout once when a name is missing from the book, or the card says the weakness shifts. A status cure is never aimed at an enemy.
5. When a living enemy has a danger move, or the battle is a boss, and the style is not aggressive: before the first paid chip, and not after someone has fallen or is critical, one opener, one guard, one debuff, a setup Limit Burst, and the Esper if the weakness still fits. A paid chip waits while an ally can still cast that guard, that debuff, or that setup Limit Burst. The wait ends after a fall or while someone is critical. An Ether or a free Attack does not close that window. A cash Limit Burst is spent on the break of a hard fight. A soft pack does not take it, so the gauge is still full when the field gets hard. An empty limit gauge is left to fill. The row is taken on the turn that gauge can pay it. The published stagger on a Limit row is not the cash score. A Limit row with no power still wins that break when the element is not absorbed.
6. A gauge is an add only when it is at or under 60% of the largest gauge still up. Those are cleared first. Equal gauges stay on one shared plan, and none of them is finished while another in that plan is still above 40% of its gauge, unless the hit is a weakness and nothing cheaper in that element can chip. The book's Normal gauge is the count. When the poured stagger reaches it, that enemy is treated as broken. If the bonus phase does not arrive within about one round, and a bonus has not confirmed that gauge yet, the count is kept and the working gauge rises. The log says `working gauge`. If that bonus then arrives before the new gauge is filled, or the gauge refills during that same short wait, the size goes back. The log says `working gauge restored`. While that wait is open the enemy is cashed with the broken bodies and is not built. A bonus confirms a gauge the fight has filled. A risen gauge that is still unfilled becomes the stagger that had been poured, and the log says `poured stagger`. Once a bonus phase has confirmed it, a later miss clears the count and the size stays. The log says `working gauge stays`.
7. The bonus window is damage on the enemies who just broke, including when a new body walks in during that window. A normal spell is not sent as a Finish Blow. The Resonance wheel is left for you when the equipped Finish Blow cannot be found.

The same planner is used for whatever party is equipped. Nothing in it is tied to one character or one fight.

`Scripts/mobs.lua` is the enemy book: 409 enemies, with weakness, resist, immunity, absorb, the Normal stagger gauge, and the move to break before. Libra is spent only when a name is missing from that book, or when the weakness changes mid-fight. If the plan fails, the equipped kit is still swung on its own stagger numbers.

An enemy who is confused, charmed, or berserk is left for you, and so is a second command on the same turn. Throw and the other submenu commands are left alone.

## If a choice goes wrong

Set `Submit = false` in `config.ini` and restart. The mod still chooses and writes the choice to `battle_log.txt` and `UE4SS.log`, and it leaves the menu open.

If another mod also changes battle speed, set `BattleSpeed = 1`. If FFRS QoL's auto-repeat (F8) is on, turn that off. Both mods would press the command.

## Uninstall

Quit the game fully.

To remove only FFR:AutoBattle, delete the folder `FFRS\Binaries\Win64\ue4ss\Mods\FFRAutoBattle`. If you added an `FFRAutoBattle : 1` line to `mods.txt`, delete that line too. Leave `dwmapi.dll` and the rest of `ue4ss` in place if you still want UE4SS.

To remove UE4SS as well, also delete `dwmapi.dll` and the `ue4ss` folder next to `FFRS-Win64-Shipping.exe`.

Saves stay where they are either way.

The play policy for contributors is `Final Fantasy Resonance Auto-Battle Design Doc (Rough Draft).md`. How to change the Lua without breaking that policy is `AGENTS.md`.

## License

MIT. See [LICENSE](LICENSE).
