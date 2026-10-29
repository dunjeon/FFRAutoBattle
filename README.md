# FFR:AutoBattle

Plays the battle from the gear, skills, and Vision you already equipped. Saves and pak files are not changed.

Lead Programmer: Grok, by xAI. Released under the MIT license.

## Install

Download `FFRAutoBattle.zip` from the release. Extract it into the folder where the game is stored, the one that contains `FFRS`. The zip already has the folders, so the mod lands at `FFRS/Binaries/Win64/ue4ss/Mods/FFRAutoBattle`.

UE4SS has to be installed for this game. The copy used here loads through `dwmapi.dll` next to `FFRS-Win64-Shipping.exe`. On Proton, set the `dwmapi` override to native then builtin, or launch with `WINEDLLOVERRIDES="dwmapi=n,b" %command%`.

`enabled.txt` in the mod folder turns it on. You do not have to edit `mods.txt`.

Fully quit and launch the game. The startup line is `loaded. planner.` F10 turns auto battle off or back on. Saves and pak files are not changed.

The party starts each fight on its own, at a faster battle speed. A line at the bottom left shows Auto and the last action. When the fight ends, a short note appears on screen, and the full account is appended to `battle_log.txt` in this folder: each command, which skills each character used, who fell, and who was staggered.

## Keys

- **F10** turns auto battle off, or back on.

That is remembered in `state.txt`. The other settings are read from `config.ini` at startup, so a change there needs a restart.

## How a fight is played

The battle lessons are the policy. There is one of them.

One planner reads the whole field and fills the next slot. The characters do not each pick a favorite enemy.

1. The field is every living enemy and every ally who can act. The log line is `field:` then `plan adds` or `plan sync`.
2. Raise the fallen. Heal under 30% HP. Under 50% only when MP is above half and either several allies are hurt or the bonus window just ended. A claimed heal is not cast again that round. Rare items stay in the bag. A Pot fight spends nothing.
3. Above half MP any fitting spell can be spent. From 20% to half, only a heal, a heavy stagger, or a known weakness. Under 20%, a free attack, or one Ether for the character who still has a weakness they cannot pay. One Ether per round.
4. Scout once when a name is missing from the book, or the card says the weakness shifts.
5. On a hard fight, before the first paid damage spell, and not after someone has fallen or is critical: an opener, one guard buff, one debuff, a setup Limit Burst, and the Esper if the weakness still fits. An Ether or a free Attack does not close that window.
6. Adds with a small gauge are cleared first. A large gauge is held until those are down, unless that enemy is close to a killing blow. When the gauges are in the same size class, every one is chipped and none is finished while another is still high. The finishers go when the set can fall together. An area spell chips. A single-target weakness finishes. A cheaper spell wins when it already empties the gauge.
7. The bonus window is damage on the enemies who just broke. The Resonance phase sends the equipped Vision's Finish Blow when that skill can be found.

The same planner is used for whatever party is equipped. Nothing in it is tied to one character or one fight.

`Scripts/mobs.lua` is the enemy book: 409 enemies, with weakness, resist, immunity, absorb, the Normal stagger gauge, and the move to break before. Libra is spent only when a name is missing from that book, or when the weakness changes mid-fight. If the plan fails, the equipped kit is still swung on its own stagger numbers.

An enemy who is confused, charmed, or berserk is left for you, and so is a second command on the same turn. Throw and the other submenu commands are left alone.

## If a choice goes wrong

Set `Submit = false` in `config.ini` and restart. The mod still chooses and writes the choice to `battle_log.txt` and `UE4SS.log`, and it leaves the menu open.

If another mod also changes battle speed, set `BattleSpeed = 1`. If FFRS QoL's auto-repeat (F8) is on, turn that off. Both mods would press the command.

## Uninstall

Close the game, then delete `dwmapi.dll` and the `ue4ss` folder next to `FFRS-Win64-Shipping.exe`. Saves stay where they are.

If the mod never loads, the Proton override is `dwmapi` = native then builtin. The equivalent launch option is `WINEDLLOVERRIDES="dwmapi=n,b" %command%`.

The play policy for contributors is `Final Fantasy Resonance Auto-Battle Design Doc (Rough Draft).md`. How to change the Lua without breaking that policy is `AGENTS.md`.

## License

MIT. See [LICENSE](LICENSE).
