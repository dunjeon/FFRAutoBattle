# FFR AutoBattle contributor guide

This file is for people and agents changing the mod. The player instructions are in `README.md`. The battle policy is `Final Fantasy Resonance Auto-Battle Design Doc (Rough Draft).md`.

Dunjeon is the Project Manager. Play policy, what a good fight looks like, and what ships are Dunjeon's call. Do not rewrite the design doc unless Dunjeon asks.

Grok, by xAI, is the Lead Programmer. Implement the policy in Lua. Do not invent a second battle plan.

The license is MIT.

## What this mod is

One UE4SS Lua mod. One F10 switch. One shared planner for the round. The characters carry out the next slot from the gear, skills, items, and Vision the player equipped.

It has to work for any party size, any character, and any Vision. A change that names a fight, a character, or a Vision is the wrong change.

## Where the files are

The game loads `Scripts/main.lua`, `Scripts/known.lua`, and `Scripts/mobs.lua`. UE4SS reads them at startup. After a Lua change the player must fully quit and launch again. The startup line is `loaded. planner.`

`known.lua` is published skill and item facts: element, stagger, and use. `mobs.lua` is the enemy book. `main.lua` is the planner and the game socket. `config.ini` is the player settings. `battle_log.txt` and `state.txt` are runtime files. Do not commit them.

If a `wip/` folder exists beside the game, copy the three scripts there after a change so the readable copies match.

## Rules that keep the planner general

- Score the field that is actually alive. A friend, a matching ally name, a nameless slot, or a body with no HP is not a foe.
- Plan adds only when the largest open gauge is actually larger than the others. Equal gauges stay on one shared plan.
- Spend the element on the card. No card means stagger factor 1 and the live stagger number. Libra only when the name is missing or the card says the weakness shifts.
- A weakness may finish a gauge when nothing in that element can chip it without finishing. When a weakness can still chip another enemy in the pool, the hit moves there.
- One debuff goes on the enemy with a dangerous attack, or on the largest gauge.
- Claims stop a second heal, a second revive, or a second Ether in the same round.
- Common shop items only. Elixir, megalixir, X-tier, turbo ether, phoenix pinion, tent, and scrolls stay put. A Pot fight spends nothing.
- The Resonance wheel is the player's. Detect the phase. Do not send a normal spell as a Finish Blow. Do not guess command-bar ids as Vision ids.
- If the planner throws or returns nothing, swing a payable damage skill. Defend only when there is no enemy and an ally is under 30% HP.

## Lua

The script is Lua 5.4. There is no `continue` and no `goto`. `and` and `or` share precedence and bind tighter than comparison. A chunk is capped at 200 locals. Do not add a pile of new chunk-level functions.

A function defined before `local Fight` or `local unitKit` binds the global, which is nil. Declare those names first. Parse with `luac5.4 -p Scripts/main.lua` before you call the change done.

Do not call `GetTurnVM`. It throws. The stagger count the mod keeps, and the party order it can see, stand in for the Timeline the design doc describes.

The live skill row has cost, power, stagger, target, and effect. It does not have an element. An unnamed Vision spell is still cast. It does not get the weakness multiplier until `known.lua` names the element.

## How to check a change

Read `UE4SS.log` for `[FFRAutoBattle]` and `battle_log.txt`. A fight is going right when the log shows `field:` and then `plan adds` or `plan sync`, and the spells follow the weakness on those cards. One fight's enemies are evidence for the rules. They are not a script to add.
