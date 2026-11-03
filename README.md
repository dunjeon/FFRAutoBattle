# FFR:AutoBattle

Plays the battle from the gear, skills, and Vision you already equipped. Saves and pak files are not changed.

Version 0.1.32. Lead Programmer: Grok, by xAI. Contributor: Claude, by Anthropic. Released under the MIT license.

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

The same folder also contains `enabled.txt` and `config.ini`. Next to `main.lua` are `known.lua`, `mobs.lua`, `catalog.lua`, `health.lua`, `debuffs.lua`, `gauges.lua`, `espers.lua`, `limits.lua`, `kits.lua`, and `items.lua`. `enabled.txt` is what turns the mod on. You do not edit `mods.txt` for a normal install.

### 4. Start the game and check

Start FINAL FANTASY RESONANCE from Steam. Load a save and enter a battle. The party should take its own commands. Press F10. The screen flashes AutoBattle Off. Press F9. The screen flashes AutoBattle: Take it Easy! The full list of keys and triggers is in Controls, below.

To confirm the files loaded, open:

`FFRS\Binaries\Win64\ue4ss\UE4SS.log`

Search for `loaded. planner v0.1.32.` The same startup also writes `catalog 154 added`. If those lines are there, the mod is running. They are written when the game starts, so they are near the top of a fresh log. `battle_log.txt` in the mod folder keeps the last five fights.

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

The other settings are in `config.ini`. A change there needs a restart. A written account of each fight is added to `battle_log.txt` in this folder.

Battle speed is the game's own button and marks. Auto battle leaves them alone.

## How a fight is played

The battle lessons are the policy. There is one of them.

One planner reads the whole field and fills the next slot. The characters do not each pick a favorite enemy.

1. The field is every living enemy and every ally who can act. The log line is `field:` then `plan adds` or `plan sync`.
2. Raise the fallen. Raise and Arise are spent on that ally, and a living ally is left standing. A healer is raised before the highest damage dealer. An ally who can pay a raise spell does the raise better than an item, so the others leave it to them while they still have a turn this round. A raiser who is out of MP, held by a status, or already gone this round is not waited on, and anyone spends a Phoenix Down. The living come first: a raise waits while a living ally is under 30% HP and not yet healed this round, unless the fallen ally is the party's best healer. An ally who fell again within two rounds of a raise is not raised again for three rounds, or sooner once no living ally is under half, so the party is not raising someone into the same hits. The log says `raise X waits`. The same ally is not raised again until they are standing, and a retry waits until the party has acted. Heal under 30% HP. An ally who enters the fight down is raised on that first round. Doom, a lock, and silence already on the party are cleared before the opening heal. Poison, blind, and slow stay on their own lines. At the start of the fight, before the party has each acted once, an ally under the recover line is healed without waiting for the bonus or for MP to be above half. After that round, under 50% only when MP is above half and either several allies are hurt or the bonus window just ended. While a boss is up, or a danger move on a gauge of 500 or more is still open, that recover line is 65% for the lowest ally, and it does not wait for the bonus. A smaller danger move stays at 50%. The ally with the stronger payable heal kit takes that heal. Someone with a weaker heal, or no heal, leaves it while that healer can still act and pay. A healer who is asleep, paralyzed, stopped, petrified, confused, charmed, berserk, or silenced does not count, and the others heal on their own. Under 15% they heal at once, and under 20% while a danger gauge is open. A slowed healer raises those to 25% and 30%. On the 50% and 65% lines they leave the heal for the whole round, unless that healer is slowed and two others have already acted. With no healer who can act and pay, they heal as before. A heal spell is cast when its cost still fits. The smallest potion that covers the missing HP is the spend when it does not. Doom is cleared first. The main healer is cleared next when a status takes their turn, and the matching item is spent before a cure spell. Sleep, paralysis, stop, petrify, confuse, charm, and berserk are cleared before the recover line, spell first. Silence on someone whose spells matter is cleared when nobody is critical, and on the healer only when Echo Herb or Remedy is in the bag. Poison is that ally's own antidote when their HP is under about 60% and nothing more urgent is waiting. Blind is that ally's own eye drops when their attacks are physical, on that same line. Nobody spends a turn on someone else's poison or blind. Slow is a cure spell from the healer, one whose row lists Slow, once it has lasted two rounds, and only when the MP left is still above half after a heal is kept back. The healer clears themself first, then the ally who alone pays the weakness or the stagger finisher, then anyone else. A non-healer casts it only when no healer can act. A cast counts only after it goes out. Two misses mark that cure as not working for the launch. A Slow that ends after the cast is not counted as that cure working. If no cure spell lists Slow, that cure is skipped and the battle log says so once. Haste is the other answer to Slow: an ally who carries Haste casts it on a slowed ally, on any field. Remedy is not spent on those three, and the last Remedy is kept for the healer or for doom. Antidote and Eye Drops are spent only on that line. Echo Herb, Smelling Salts, Unicorn Horn, Gold Needle, and Herb of Awakening match their locks. A cure name the book does not list is still spent on a lock. A cure spell is aimed at a status its row lists. A cure that went out and left the same status is a miss, and after two misses that cure is not spent on that status for the fight. An unknown status id is written once to the battle log. When most of the living party is under half, a party heal is chosen over every single heal, including a party row with no power number. That is three of four, three of three, or two of two. Fewer hurt allies keep the single cure. The ally who is the only one able to pay a weakness on the current pool keeps chipping while the hurt ally is at or above 15% and someone else can still heal. A claimed heal is not cast again that round. Rare items stay in the bag outside a boss fight. In a boss fight they are spent when no common item does the job: a Phoenix Pinion when no Phoenix Down is left, and a rare heal or MP item under dire need (an ally down, an ally under 30%, or most of the party under half). Dire need also lifts the one-Ether-per-round limit. In a boss fight a scroll is thrown on a weakness the bar cannot pay, and a scroll, knife, or shuriken that lands is thrown when nothing payable does. Tents and Healing Spring stay put. A Pot fight spends nothing.
3. Above half MP any fitting spell can be spent. From 20% to half, only a heal, a heavy stagger, or a known weakness. Under 20%, a known weakness whose cost still fits, or a free attack. When no free hit can land on a body, a paid hit that lands is allowed at any MP. One Ether on the ally's own turn when a heal they carry no longer fits, when nothing payable lands and a hit on the bar would, or when the bar is low and that weakness does not fit. One Ether per round.
4. Scout once when a name is missing from the book, or the card says the weakness shifts. A hit that already landed does not skip that Libra. A status cure is never aimed at an enemy.
5. When a living enemy has a danger move, or the battle is a boss, and the style is not aggressive: before the first paid chip, and not after someone has fallen or is critical, one opener, one guard, the debuffs that matter, a setup Limit Burst, and the Esper whose element matches a weakness, when that cost leaves a heal. An element any living enemy nulls or absorbs is not called. A support Esper is used when no element matches. It can be called again after its turns when the fight is still long, and before a gauge is about to break. Its own turn is left alone. Defense down and attack down go on the enemy with the danger move, or the largest gauge. Blind and silence go on a caster. A charm, confuse, poison, or slow is spent only when none of those is equipped, and only when the book does not list that ailment as an immunity. A debuff still showing on the body is not cast again. When that status has been seen and then drops, it is refreshed, unless someone is critical or a payable hit would finish the gauge. A paid chip waits while an ally can still cast that guard, one of those opening debuffs, or that setup Limit Burst. The wait ends after a fall or while someone is critical. An Ether or a free Attack does not close that window. A setup Limit Burst goes on the enemy with the danger move, or the largest open gauge. A barrier or a party row goes on the allies. One of those is spent per fight, before the break, on the turn its gauge can pay. A one-gauge row is spent when that gauge is full. A two-gauge row waits until both are full. A damage Limit Burst is spent on the break of a hard fight, and when more than one is ready the row whose element matches that break is the one taken. A row with no element is still spent. An element any living enemy nulls or absorbs is not used as an area hit. A soft pack does not take a damage burst, so the gauge is still full when the field gets hard. An empty limit gauge is left to fill. The published stagger on a Limit row is not the cash score. A Limit row with no power still wins that break when the element is not absorbed. When two or more allies are down and the raise spends two gauges, it raises the party. One fallen ally still takes a single raise.
6. A gauge is an add only when it is at or under 60% of the largest gauge still up. Those are cleared first. Equal gauges stay on one shared plan, and none of them is finished while another in that plan is still above 40% of its gauge, unless the hit is a weakness and nothing cheaper in that element can chip. The book's Normal gauge is the count. When the poured stagger reaches it, that enemy is treated as broken. If the bonus phase does not arrive within about one round, and a bonus has not confirmed that gauge yet, the count is kept and the working gauge rises. That rise stops at a quarter over the book, unless the stagger already poured is higher, in which case the gauge is that stagger plus one. The log says `working gauge`. If that bonus then arrives before the new gauge is filled, or the gauge refills during that same short wait, the size goes back. The log says `working gauge restored`. While that wait is open the enemy is cashed with the broken bodies and is not built. A bonus confirms a gauge the fight has filled. A risen gauge that is still unfilled becomes the stagger that had been poured, and the log says `poured stagger`. Once a bonus phase has confirmed it, a later miss clears the count and the size stays. The log says `working gauge stays`.
7. The bonus window is damage on the enemies who just broke, including when a new body walks in during that window. A normal spell is not sent as a Finish Blow. The Resonance wheel is left for you when the equipped Finish Blow cannot be found.
8. Role skills. A formation, the skill that sets one up, a stagger mark, one weakness on an enemy the book leaves bare, and a luck toss are spent from the kit book when they are equipped and the cost fits. A paid one goes while MP is above the low band. The skill that sets up a formation is spent only when that formation still fits after it.
9. Provoke, Cover, and Multi-Cover pull the hits onto the caster. They answer a danger move still open on the field, or a healer under the recover line. A calm field spends none. The healer does not pull attacks, and neither does an ally under the recover line, and there has to be someone else to protect. A hurt healer gets Cover first. One draw at a time: a second one waits while another is up. The log says `draw`.
10. Haste goes on a slowed ally first. On a hard field while MP is above half, the healer and then the strongest damage dealer get it. One per round. Hastega goes when two or more want it. The log says `haste`. The other generic buffs stay on the bar.
11. A stalemate is five rounds of the party's hits on enemies in which no enemy loses HP and no bonus phase comes. Then the party escapes, when the game allows it. A Pot fight is yours. Take it Easy never escapes.
12. When the whole party falls and the game retries the fight, the stagger count and the one-time setup start over. The log says `party restored`.
13. A kind of hit the enemy nulls is a miss. The book marks it (`no = { physical = true }`), and a fight learns it too: two hits of one kind in a row that take no HP mark that kind as nulled on that enemy. A kind that already took HP off that enemy in this fight, with no summon out, is not learned as nulled. The log says `takes no damage from physical hits`. The guard matches the danger's kind of damage when the book gives it (`hits = "magic"` calls for Shell, `physical` for Protect), and goes out once.
14. Once the fight is underway, a support turn (a role skill or a debuff refresh) is followed by a hit, when the ally has a hit that lands.

The same planner is used for whatever party is equipped, at any party size. Nothing in it is tied to one character or one fight. A summoned Esper is not a party member: it is not healed, raised, or waited on.

`Scripts/mobs.lua` is the enemy book: 409 enemies, with weakness, resist, immunity, absorb, the Normal stagger gauge, and the move to break before. Libra is spent only when a name is missing from that book, or when the weakness changes mid-fight. A hit that already landed does not skip that Libra. If the plan fails, the equipped kit is still swung on its own stagger numbers, on a body the hit lands on. When nothing lands, the ally Defends. The Resonance wheel is left for you when no equipped finisher lands.

An ally who is confused, charmed, or berserk is left to the game, and a second command on the same turn is left for you. Throw and the other submenu commands are left alone.

## If a choice goes wrong

Set `Submit = false` in `config.ini` and restart. The mod still chooses and writes the choice to `battle_log.txt` and `UE4SS.log`, and it leaves the menu open.

If FFRS QoL's auto-repeat (F8) is on, turn that off. Both mods would press the command.

## Uninstall

Quit the game fully.

To remove only FFR:AutoBattle, delete the folder `FFRS\Binaries\Win64\ue4ss\Mods\FFRAutoBattle`. If you added an `FFRAutoBattle : 1` line to `mods.txt`, delete that line too. Leave `dwmapi.dll` and the rest of `ue4ss` in place if you still want UE4SS.

To remove UE4SS as well, also delete `dwmapi.dll` and the `ue4ss` folder next to `FFRS-Win64-Shipping.exe`.

Saves stay where they are either way.

The play policy for contributors is `Final Fantasy Resonance Auto-Battle Design Doc (Rough Draft).md`. How to change the Lua without breaking that policy is `AGENTS.md`.

## License

MIT. See [LICENSE](LICENSE).
