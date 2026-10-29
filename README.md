# FFR:AutoBattle

Plays the battle from the gear, skills, and Vision you already equipped. Saves and pak files are not changed.

Version 0.1.2. Lead Programmer: Grok, by xAI. Released under the MIT license.

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

Start FINAL FANTASY RESONANCE from Steam. Load a save and enter a battle. The party should take its own commands. A line at the bottom left says Auto and the last action. F10 turns auto battle off. F10 again turns it back on.

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

The party starts each fight on its own, at a faster battle speed. The screen stays clear during the fight. F10 flashes AutoBattle On or AutoBattle Off, and that is the only text the mod draws. The full account is still appended to `battle_log.txt` in this folder: each command, which skills each character used, who fell, and who was staggered.

## Keys

- **F10** turns auto battle off, or back on.

That is remembered in `state.txt`. The other settings are read from `config.ini` at startup, so a change there needs a restart.

## How a fight is played

The battle lessons are the policy. There is one of them.

One planner reads the whole field and fills the next slot. The characters do not each pick a favorite enemy.

1. The field is every living enemy and every ally who can act. The log line is `field:` then `plan adds` or `plan sync`.
2. Raise the fallen. Heal under 30% HP. Under 50% only when MP is above half and either several allies are hurt or the bonus window just ended. While a danger move is still up, that recover line is 65% for the lowest ally, and it does not wait for the bonus. The ally who is the only one able to pay a weakness on the current pool keeps chipping while the hurt ally is at or above 15% and someone else can still heal. A claimed heal is not cast again that round. Rare items stay in the bag. A Pot fight spends nothing.
3. Above half MP any fitting spell can be spent. From 20% to half, only a heal, a heavy stagger, or a known weakness. Under 20%, a free attack, or one Ether for the character who still has a weakness they cannot pay. One Ether per round.
4. Scout once when a name is missing from the book, or the card says the weakness shifts.
5. When a living enemy has a danger move, or the battle is a boss, and the style is not aggressive: before the first paid chip, and not after someone has fallen or is critical, one opener, one guard, one debuff, a setup Limit Burst, and the Esper if the weakness still fits. An Ether or a free Attack does not close that window.
6. A gauge is an add only when it is at or under 60% of the largest gauge still up. Those are cleared first. Equal gauges stay on one shared plan, and none of them is finished while another in that plan is still above 40% of its gauge, unless the hit is a weakness and nothing cheaper in that element can chip. The book's Normal gauge is the count. When the poured stagger reaches it, that enemy is treated as broken. If the bonus phase does not arrive within about one round, the count is kept and the working gauge rises, and the log says `working gauge`.
7. The bonus window is damage on the enemies who just broke. A normal spell is not sent as a Finish Blow. The Resonance wheel is left for you when the equipped Finish Blow cannot be found.

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
