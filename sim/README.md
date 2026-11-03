# FFR:AutoBattle battle sim

The sim loads the real `Scripts/*.lua` under Lua 5.4, unchanged, against a stand-in for the game and UE4SS. It plays random parties against random fights and checks the design doc's rules.

```
lua5.4 sim/run.lua [sessions] [seed] [--only kind] [--hard 1.0] [--hit 1.0] [--keep loss,timeout,fled] [--easy] [--scripts DIR] [--echo]
```

- `sessions` is how many game launches to play. Each one loads `main.lua` once and plays one to three fights in a row, with HP, MP, and falls carried between them. The default is 200. 1000 takes about 45 seconds.
- `seed` makes a run repeatable. The same seed plays the same fights.
- `--only kind` plays one kind of fight: `trash`, `mixed`, `equal`, `danger`, `boss`, `status`, `counter`, `absorb`, `pot`, `entry`, `nophys`, `hidden`, `locked`, `adds`. `adds` is a boss with a danger card that calls one small add, which comes back two rounds after it falls. `tide` plays the battle log's Leviathan and the Orbs of Light it keeps on the field, of 2026-11-03 (the Orbs break and recover but never fall, as in the game log), with that fight's party and bag. It is only played when asked for; the game wiped there twice, so play it with `--hit 2.0`. `replay` plays the battle log's boss Shoggoth of 2026-11-02 with that fight's party and bag. It is only played when asked for.
- `--hard` scales enemy HP and attack. 1.0 is the default.
- `--hit` scales enemy attack alone, to make a fight as deadly as the game's without making it longer.
- `--keep loss,timeout,fled` also writes those fights to `sim/out/kept`.
- `--easy` plays Take it Easy instead of No Mercy, and flags anything but the free basic Attack. Every other run, and every test, is No Mercy.
- `--scripts DIR` plays another copy of the scripts. Use it to check that the sim catches a rule you broke on purpose.
- `--echo` prints the planner's own log as it plays.

Output goes to `sim/out` (not committed): `report.txt`, and one file per fight that broke a rule in `sim/out/fails`, with the sim's events and the planner's log lines.

## What it checks

A broken rule is any of these, in any fight:

- **stall**: a menu got no command.
- **planner error**: the planner logged a failure (`choice failed`, `plan failed`, `no command sent`, and the like).
- **illegal**: a skill not on the bar, not paid, or sealed, an item not in the bag, or a missing target.
- **wrong actor**, **wrong side**, **dead target**, **empty cure**: a command aimed at the wrong unit.
- **wasted revive**: a raise on a living ally.
- **premium item**: Elixir, Megalixir, X-Potion, Turbo Ether, Phoenix Pinion, a tent, a scroll, a knife, or a shuriken outside a boss fight. In a boss fight: a tent at all, a rare heal or MP item with no dire need, or a rare item while a common one of the same use is in the bag. These rows are not flagged rare, so the planner has to know them by name.
- **pot item**: any item spent in a Pot fight.
- **second ether**: two Ethers in one round, as the planner counts a round, unless a boss fight is in dire need. An Elixir spent on a heal is not an Ether.
- **missed group heal**: a single heal (an item that also restores MP is not counted, since it may be spent as an Ether) while most of the living party is under half and a common party heal item (one whose row targets every ally, like the sim's Mist Potion) is in the bag.
- **buff still up**, **debuff still up**: a buff or debuff cast again while its status still shows on every body it would land on.
- **enemy recorded**: an enemy's own command, which the game's decide hook also reports, logged by the planner as a party command. The sim fires that hook on every enemy turn.
- **false retry**: the planner logged `party restored` with no wipe, and threw away its ledger, buffs, and setup mid-fight.
- **overheal**: a second single heal in the round on an ally already above 65%.
- **summon target**: a single heal, cure, or raise on a summon.
- **blocked heal**: a single white-magic heal on an ally whose stance (Witching Hour) blocks it. The sim marks the stance status 97, lifts that ally's hits by half, and lets items through.
- **healer draws**, **calm draw**: Provoke or Cover from the party's best healer, or on a field with no threat and no hurt healer.
- **wheel**: a normal spell sent on the Resonance wheel.
- **early escape**: an escape while enemies were still losing HP. The planner escapes only on a stalemate.
- **boss escape**, **escape again**: an escape from a boss fight, or a third escape after the game refused two. The `locked` fight is a Cactuar the game will not let the party flee, though the bar still shows Escape.
- **false fall**: the planner's battle summary lists more falls than happened.
- **raise before the living**: a raise while a living ally was under 30% and not healed in the last pass of the party, unless the fallen ally was the party's best healer.
- **missed retry**: a boss fight was retried after a wipe and the planner kept the old ledger and setup. A wipe before the planner's first command in that fight is not counted.
- **stacked draw**: a second Provoke, Cover, or Multi-Cover while another was still up.
- **easy mode**: with `--easy`, anything but the free basic Attack at an enemy.
- **plan mode**: the first plan is `adds` when the gauges are equal, or `sync` when one is at or under 60% of the largest.

The report also gives the win rate against the doc's baseline (attack with the strongest payable skill, on the same seed), by fight kind and by party size, how often each planner rule fired, how often a payable weakness was taken, and how often a Phoenix Down went out while a living ally could pay a raise spell. It counts one- and two-gauge Limit Bursts, the party support ones among them, and boss bonus turns where an ally with a full damage Limit sent something else. That last count includes a level 1 Limit saved on purpose for a level 2 one. The game answers neither Limit gauge-size call, so the sim does not either, and the planner has to count gauges from the bar.

## What it does not know

Each enemy's real gauge is its book gauge times 0.9 to 1.25, since the game logs show Leviathan breaking under its book 1000 in one fight and holding past 1068 in another. The planner's stagger book has to find the real size.

Kit buffs have invented effects so a setup turn is not counted as pure loss: Formation: Charge +20% damage, Formation: Assail +30% stagger, Hone Senses and Placidity +20% stagger on the caster, Formation: Bulwark a quarter less damage taken, and Stratagem's mark 30% more stagger on the marked enemy. The game's numbers are not known. Limit Bursts come in each character's level 1 and level 2 pair. Formation: Steeled Advance adds 20 points to an ally's gauge on each of their actions for three turns, Mirroring Prism doubles each ally's next hit, and Eternal Veil cancels each ally's next hit taken. A break adds 25 points to every living ally's gauge, as the public guides say.


The battle model is invented. Damage, HP, enemy attacks, status chances, and how long Cover and Provoke last are rough numbers chosen to make fights last about nine rounds. Win rates compare the planner with the baseline on the same fights. They are not a prediction of the game. Do not tune the planner's lines from them.

Game facts it copies from the design doc and the battle logs:

- The stagger gauge is BreakPoint, parameter 3, current and max. A current of 0, or status 89, is a break. The ratio call is not used.
- A weakness is x3 stagger. Half is x0.5. Null and absorb are a miss.
- A break gives the next ally turn the bonus phase (`p1`). Every living enemy broken at once gives every ally a bonus turn, then the Resonance wheel (`p2`). The player picks on the wheel when the planner sends nothing.
- Sleep, paralysis, petrify, and stop take the turn with no menu. The game decides for a confused, charmed, or berserk ally.
- A summon is a friend unit in slot 7 with no skill list. It acts on its own.
- Every bar has Escape. The game refuses it in a boss fight.
- A boss fight offers one retry after a wipe. The defeat screen holds a moment first.
- Party heal rows (Cura, Curaga) show no magnification, as the game's rows can.
- A hasted ally acts twice every other round. A slowed ally or enemy loses every other turn. Haste and Slow cancel each other, as in the classic games. FFR is not confirmed.
- The units stay on screen a moment after the last blow. Each command and each enemy action takes screen time, so the planner's 0.7 s field check sees a raise land before the next hit.
- Enemies deal physical or magic damage. Protect softens physical, Shell softens magic. A card's `no.physical` or `no.magic` makes that kind do nothing. The `nophys` fight is Shoggoth from the book. The `hidden` fight gives an enemy a null the book does not list, so the planner has to learn it.
- **null hit**, **kept hitting a null**, **wrong guard** are checked: a hit into a book null while another kind would land, more than three hits into a hidden null (hits while a summon is out are not counted, since the planner cannot tell whose hit took HP), and a guard of the wrong kind when the card names the damage. A hit that lands before the planner has seen two misses (a confused swing, a blind miss) can push a fight past three; about one fight in four hundred.
- **raise cycle** is checked too: a raise into the same hits right after that ally fell straight back.
- Provoke and Cover show no status.

Open questions the sim cannot settle:

- How an `evade` card breaks. The sim makes physical hits miss it until it breaks. The planner does not read `evade`. A party with only physical hits counts stagger that never lands, swings `fill`, and escapes on the stalemate. In a boss fight the game refuses Escape, so it plays until the fight times out.
- How a dead ally's skill list reads in the game. The sim returns it from the slot, as the planner now asks for it.
