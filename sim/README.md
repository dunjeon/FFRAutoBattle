# FFR:AutoBattle battle sim

The sim loads the real `Scripts/*.lua` under Lua 5.4, unchanged, against a stand-in for the game and UE4SS. It plays random parties against random fights and checks the design doc's rules.

```
lua5.4 sim/run.lua [sessions] [seed] [--only kind] [--hard 1.0] [--keep loss,timeout,fled] [--easy] [--scripts DIR] [--echo]
```

- `sessions` is how many game launches to play. Each one loads `main.lua` once and plays one to three fights in a row, with HP, MP, and falls carried between them. The default is 200. 1000 takes about 45 seconds.
- `seed` makes a run repeatable. The same seed plays the same fights.
- `--only kind` plays one kind of fight: `trash`, `mixed`, `equal`, `danger`, `boss`, `status`, `counter`, `absorb`, `pot`, `entry`.
- `--hard` scales enemy HP and attack. 1.0 is the default.
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
- **premium item**: Elixir, Megalixir, X-Potion, Turbo Ether, Phoenix Pinion, a tent, or a scroll. These rows are not flagged rare, so the planner has to know them by name.
- **pot item**: any item spent in a Pot fight.
- **second ether**: two Ethers in one round, as the planner counts a round.
- **overheal**: a second single heal in the round on an ally already above 65%.
- **summon target**: a single heal, cure, or raise on a summon.
- **healer draws**, **calm draw**: Provoke or Cover from the party's best healer, or on a field with no threat and no hurt healer.
- **wheel**: a normal spell sent on the Resonance wheel.
- **early escape**: an escape while enemies were still losing HP. The planner escapes only on a stalemate.
- **false fall**: the planner's battle summary lists more falls than happened.
- **easy mode**: with `--easy`, anything but the free basic Attack at an enemy.
- **plan mode**: the first plan is `adds` when the gauges are equal, or `sync` when one is at or under 60% of the largest.

The report also gives the win rate against the doc's baseline (attack with the strongest payable skill, on the same seed), by fight kind and by party size, how often each planner rule fired, how often a payable weakness was taken, and how often a Phoenix Down went out while a living ally could pay a raise spell.

## What it does not know

The battle model is invented. Damage, HP, enemy attacks, status chances, and how long Cover and Provoke last are rough numbers chosen to make fights last about nine rounds. Win rates compare the planner with the baseline on the same fights. They are not a prediction of the game. Do not tune the planner's lines from them.

Game facts it copies from the design doc and the battle logs:

- The live break ratio stays full. A break shows as status 89.
- A weakness is x3 stagger. Half is x0.5. Null and absorb are a miss.
- A break gives the next ally turn the bonus phase (`p1`). Every living enemy broken at once gives every ally a bonus turn, then the Resonance wheel (`p2`). The player picks on the wheel when the planner sends nothing.
- Sleep, paralysis, petrify, and stop take the turn with no menu. The game decides for a confused, charmed, or berserk ally.
- A summon is a friend unit in slot 7 with no skill list. It acts on its own.
- Every bar has Escape. The game refuses it in a boss fight.
- A hasted ally acts twice every other round. A slowed ally or enemy loses every other turn. Haste and Slow cancel each other, as in the classic games. FFR is not confirmed.
- The units stay on screen a moment after the last blow.
- Provoke and Cover show no status.

Open questions the sim cannot settle:

- How an `evade` card breaks. The sim makes physical hits miss it until it breaks. The planner does not read `evade`. A party with only physical hits counts stagger that never lands, swings `fill`, and escapes on the stalemate. In a boss fight the game refuses Escape, so it plays until the fight times out.
- How a dead ally's skill list reads in the game. The sim returns it from the slot, as the planner now asks for it.
