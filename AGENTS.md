# FFR:AutoBattle contributor guide

This file is for people and agents changing the mod. The player instructions are in `README.md`. The battle policy is `Final Fantasy Resonance Auto-Battle Design Doc (Rough Draft).md`.

Grok, by xAI, is the Lead Programmer. Claude, by Anthropic, is a contributor. Implement the policy in Lua. Do not invent a second battle plan.

Do not rewrite the design doc unless asked. What a good fight looks like is in that doc.

The license is MIT.

## What this mod is

One UE4SS Lua mod. F10 turns auto battle on or off. F9 turns basic attacks on or off. In a fight the right trigger does what F10 does. In a fight, while auto battle is on, the left trigger does what F9 does. While auto battle is off, or outside a fight, the left trigger stays with the game. Do not rewrite the game's input mappings from the trigger poll. One shared planner for the round. The characters carry out the next slot from the gear, skills, items, and Vision the player equipped.

It has to work for any party size, any character, and any Vision. A change that names a fight, a character, or a Vision is the wrong change.

## Where the files are

The game loads `Scripts/main.lua`, `Scripts/known.lua`, and `Scripts/mobs.lua`. UE4SS reads them at startup. After a Lua change the player must fully quit and launch again. The startup line is `loaded. planner v0.1.48.`

`known.lua` is published skill facts: element, stagger, and use. `items.lua` is the item book and the rules for which item to spend; `main.lua` only reads the bag and sends the item. `mobs.lua` is the enemy book. `main.lua` is the planner and the game socket. `config.ini` is the player settings. `battle_log.txt` and `state.txt` are runtime files. Do not commit them.

This repo is the only copy under git. The installed mod folder, `FFRS/Binaries/Win64/ue4ss/Mods/FFRAutoBattle/` in the game, holds only `Scripts/`, `config.ini`, `enabled.txt`, and the runtime files. Do not put a git repo or the docs there. After a change, parse, then copy `Scripts/*.lua` into the installed `Scripts/`. Read `battle_log.txt` from the installed folder.

FFRProbe and the other research tools stay off in testing builds. Only FFRAutoBattle and UE4SS's own default mods load. A probe mod runs only when the player asks for it.

## Rules that keep the planner general

- Party size sets how long a round is: one turn for each party member who can take one. It never switches a rule. Where a rule needs "most of the party", it is a share of the living party, the same at any size.
- A summon is not a party member. It is not healed, raised, counted, or waited on.
- Score the field that is actually alive. A friend, a matching ally name, a nameless slot, or a body with no HP is not a foe.
- Plan adds only when the largest open gauge is actually larger than the others. Equal gauges stay on one shared plan.
- Spend the element on the card. No card means stagger factor 1 and the live stagger number. Libra only when the name is missing or the card says the weakness shifts. A paid chip does not close that scout.
- A weakness may finish a gauge when nothing in that element can chip it without finishing. When a weakness can still chip another enemy in the pool, the hit moves there.
- One debuff goes on the enemy with a dangerous attack, or on the largest gauge.
- Claims stop a second heal, a second revive, or a second Ether in the same round. A party item's heal claim does not cover an ally still under 30% at the next turn.
- Common shop items only, outside a boss fight. In a boss fight a rare item is spent when no common item does the job: a raise at once, a heal or MP item only under dire need (an ally down, an ally under 30%, or most of the living party under half). Dire need lifts the one-Ether-per-round limit. Scrolls and knives are thrown in a boss fight on a weakness the bar cannot pay, or when nothing payable lands. Tents and Healing Spring stay put. A Pot fight spends nothing.
- The Resonance wheel is the player's. Detect the phase. Do not send a normal spell as a Finish Blow. Do not guess command-bar ids as Vision ids.
- Battle speed stays with the game. Do not read it, write it, multiply it, clamp it, or move its marks. Do not bind the speed key.
- In a fight, while auto battle is on, the left trigger toggles basic attacks. While auto battle is off, or outside a fight, the left trigger stays with the game. F9 still toggles basic attacks. Do not rewrite the game's input mappings from the trigger poll. That walk threw and stopped both triggers.
- If the planner throws or returns nothing, swing a payable damage skill that can land, on a body it lands on. When nothing on the bar can land on anyone, Defend. With no Defend, swing anyway, so the menu is never left open.
- A kind of hit (physical or magic) the card nulls, or one the fight has seen do no damage twice, is a miss, the same as a nulled element. A kind that already took HP off that enemy in the fight, with no summon out, is not learned as nulled.

## Lua

The script is Lua 5.4. There is no `continue` and no `goto`. `and` and `or` share precedence and bind tighter than comparison. A chunk is capped at 200 locals. Do not add a pile of new chunk-level functions.

A function defined before `local Fight` or `local unitKit` binds the global, which is nil. Declare those names first. Parse with `luac5.4 -p Scripts/main.lua` before you call the change done.

Do not call `GetTurnVM`. It throws. The Timeline is `CPP_VM_BtlTimeLine:HandleUpdateTimeline`. Copy the unit ids inside the hook. The warning list is `RiskUnitUniqueIdList`, read when a party menu opens. Do not hook `HandleUpdateRisk`.

The enemy stagger gauge is the live BreakPoint, parameter 3, current and max. That read already includes the difficulty rate. A current of 0, or status 89, is broken. The ledger and the book gauge are the fallback when the read is missing. The break ratio is not the count.

The `SKILL_DATA` row has cost, power, stagger, target, effect, and element. The command bar does not carry the element. The planner reads the row first, then `known.lua`. An unnamed Vision spell is still cast. It does not get the weakness multiplier until one of those names the element.

## How to check a change

Run the battle sim before a change goes to the game: `lua5.4 sim/run.lua 1000 1`. It loads the real scripts against a stand-in for the game and lists any fight that broke a rule in `sim/out/fails`. Its numbers are invented, so it checks rules, not balance. See `sim/README.md`.

Read `UE4SS.log` for `[FFRAutoBattle]` and `battle_log.txt`. A fight is going right when the log shows `field:` and then `plan adds` or `plan sync`, and the spells follow the weakness on those cards. One fight's enemies are evidence for the rules. They are not a script to add.
