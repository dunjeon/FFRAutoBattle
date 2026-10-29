# Final Fantasy Resonance: Auto-Battle Design Doc (Rough Draft)

The auto-battle never assumes a build: at battle start it reads each character's actual skills, tags them by function, and then runs one priority ladder each turn that keeps the party alive, keeps MP available, and drives enemies toward stagger.

## Game facts the AI relies on

The AI only uses mechanics that hold in every build; anything Vision-specific is discovered at runtime, never hard-coded.

| System | What the game does | What the AI does with it |
| --- | --- | --- |
| Turn order | Turn-based with a visible Timeline of upcoming ally and enemy actions | Reads who acts before the next enemy to time heals and buffs |
| Stagger gauge | Each enemy has a gauge under its HP; weaknesses drain it faster; at zero the enemy loses its action and takes more damage | Main damage goal: empty gauges, then burst |
| Sweeping Stagger | Staggering all enemies in one turn gives a bonus phase ending in a Resonance attack | Plans turns so the last gauges empty together |
| Visions | One equipped per character; grants that Vision's skills, paid with the character's own MP | Reads the actual skill list, never assumes a Vision |
| Roles | Sentinel, Breaker, Medic, Commando, Saboteur, Synergist | Used as a hint only; skill tags decide behavior |
| MP | Skills cost MP; Ethers, MP-on-stagger, MP-on-kill and end-of-battle restores exist as passives or gear | MP budget drives skill choice |
| Items | Potions, Ethers, Phoenix Down, Remedy and similar are in the starter packs | Auto-use as a team resource, with reserves |
| Libra | Cheap spell revealing an enemy's weakness, drops and traits | Used when available and weakness is unknown |

Skill lists, costs and stagger values vary per Vision and character, so the doc treats them as data read from the party, not constants.

## Build-agnostic skill tagging

At battle start, and again whenever a Vision, gear or status changes, the AI scans every usable skill and item and gives each one tags. Decision rules then ask for tags ("a heal that hits one ally"), never names ("Cure"). A build with no healer simply has no heal tags, and the rules fall through to items.

| Tag | How it is detected | Used for |
| --- | --- | --- |
| HEAL\_SINGLE / HEAL\_ALL | Skill description restores HP to one or all allies | Healing before items |
| REVIVE | Skill or item removes KO | Revive rule |
| CURE\_STATUS | Removes poison, blind, silence and similar | Status rule |
| BUFF / DEBUFF | Raises ally or lowers enemy stats, Shell, Haste, Regen | Setup turns |
| DAMAGE\_ELEM(x) | Deals element x damage, single or all targets | Weakness targeting |
| DAMAGE\_PHYS | Physical damage skill, often 0 MP | Free fallback damage |
| STAGGER\_HEAVY | High stagger value relative to damage; the game shows the estimate before attacking | Gauge breaking |
| MP\_RESTORE\_SELF | Skill that drains or restores own MP, or MP-on-stagger effects | MP economy |
| ANALYZE | Libra-type skill | Weakness discovery |
| SUMMON | Esper with MP cost and a turn duration | Burst windows |
| FREE\_ATTACK | Basic Attack, 0 MP | Last-resort action |

If the game's data does not expose a tag directly, the AI falls back to the skill description text and, failing that, the previewed damage and stagger numbers. Every character always has at least FREE\_ATTACK, so the AI can always act.

## Party brain: one planner, not four soloists

Yes, the characters must know each other's moves. The design uses one shared planner that plans the whole round across the Timeline, and the four characters are only executors of its plan. Four independent AIs would double-heal, stack the same buff twice, waste a stagger one turn early, and revive the same ally twice.

**Shared state the planner keeps**

- Every enemy: HP, stagger gauge remaining, known weaknesses and immunities, and what it did last turn.
- The Timeline: who acts before whom this round, and which enemy acts next.
- Every ally: HP, MP, statuses, and the tags of every skill and item they can use.
- **Claims:** when the planner assigns an action it reserves its effect (this heal covers Ally B, this debuff is on Enemy 2, this Ether goes to Ally C). Later actions see the claim and pick something else.
- **Projected gauges:** each queued attack's stagger preview is subtracted from the target's gauge in the plan, so the planner knows whether the gauge will be empty before an enemy's turn.

**How a round is planned**

1. Read the Timeline and list the party's actions in order, with the enemy actions between them.
2. Fill the slots front to back with the ladder from the turn loop, but score each option against the projected state left by earlier slots, not the real state.
3. Order matters: buffs and debuffs go early, heals go before the enemy action that threatens, and gauge finishers go last so the whole party's chip damage is counted first.
4. After every real action, compare what happened with the projection (crit, miss, resist) and re-plan the rest of the round.

The previewed stagger and damage numbers are the planner's ground truth, so it never needs to know a skill's name, only what the game says it will do.

## Multi-enemy targeting

The party neither all hits one target nor splits evenly, and it does not wing it. It scores every enemy each round, and the score decides where damage and stagger go.

| Factor | What raises the enemy's priority |
| --- | --- |
| Threat | It acts before the next ally turn, or its attack is AoE, lethal, or applies a bad status |
| Support role | It heals, buffs or shields other enemies, or summons more |
| Stagger proximity | Its gauge is close to empty given what the party can deal this round |
| Weakness fit | A party skill hits its weakness, so stagger per MP is high |
| Kill value | Low HP: one more hit removes an action from the Timeline for good |
| Immunity or absorb | Lowers priority for that element only, never for the whole enemy |

**Adds versus boss.** The planner compares two plans and takes the one that needs fewer rounds.

- **Plan A, clear the adds.** Kill or stagger-and-kill adds first, then the boss is the only enemy left, so staggering it alone is a sweeping stagger. Best when adds are fragile, support the boss, or act often.
- **Plan B, sync everything.** Keep every enemy alive and bring all gauges to near zero together. Best when adds have large HP or the boss is the main threat.
- The boss is never ignored while the adds are cleared if its next action on the Timeline is lethal; the planner then heals or buffs against it instead.

**Sweeping stagger timing.** The game staggers enemies for one turn and they recover at the start of the next, so emptying one gauge early wastes most of it. The planner therefore chips every gauge down to a small remainder, then finishes all of them in the same round, ordered by the Timeline. It uses AoE skills for the chip and single-target stagger skills for the finish.

**Focus versus split.** Focus on one enemy for HP damage when the sweep is not reachable (for example an immune boss), and split chip damage across gauges when it is. Overkill is avoided: the planner never puts a big-MP skill on a target that a cheaper one already finishes.

## Fight phases and strategy style

At battle start the planner scores the party against the enemies and picks a style. It then moves through phases and may jump back when things change.

| Phase | Goal | Typical actions |
| --- | --- | --- |
| 1. Scout | Learn weaknesses and threats | Libra-type skill if any, otherwise a cheap varied first hit; log what the previews and results show |
| 2. Setup | Make the party safe and the enemy weaker | Shell and Haste-type buffs, Blind and defense-down debuffs, summon if the fight will last |
| 3. Chip | Bring all gauges near zero without wasting a stagger | AoE or weakness hits, kill fragile support adds |
| 4. Break and burst | Empty every gauge in one round, then spend the bonus phase | Highest-damage skills on staggered enemies, Resonance |
| 5. Recover | Reset after the enemies recover | Heals, cures, MP restores, then back to phase 3 |

**Style, chosen from the party profile.** The planner sums the party's healing per round, damage per round, stagger per round and MP pool, and compares them with the enemies' estimated damage per round.

- **Aggressive:** healing is strong or enemies are weak. Shorter setup, break as soon as possible.
- **Balanced:** the default.
- **Defensive:** healing is thin or enemies hit hard. Buff and debuff first, keep a full MP and item reserve, break only when a stagger can be completed safely.

The style is re-evaluated every round, so a party that starts well and then loses its healer shifts to defensive on its own.

**Proving it works for every build.** Before release, run the planner in a simulator against many random parties (every character crossed with every Vision, with and without healers, AoE, weakness coverage and items) and fight types (single enemy, groups, boss with adds). The pass conditions: never stall, never waste a revive, never spend premium items on trivial fights, and win more often than a plain "attack with the strongest skill" baseline.

## Turn decision loop

&#91;embedded content: turn priority ladder, 8 rules\]

Every character on their turn walks this ladder and takes the first rule that fires. Rules 2 to 5 are the care layer (revive, heal, cure, MP); rules 6 and 7 are the offense layer. Thresholds are starting values to tune.

## Healing and item rules

The party's HP is one shared pool of risk: the AI picks the cheapest tool that fixes the problem, in this order: free effect, MP skill, item. Items are spent freely in danger and saved when the fight is safe.

| Situation | Trigger | Action, first available |
| --- | --- | --- |
| Ally KO'd | Any ally at 0 HP | 1. REVIVE skill from a healthy ally. 2. Phoenix Down-type item. Do not revive if the fight is about to end (one weak enemy left, no threat). |
| Critical HP | Ally under 30% HP, or enemy's next action on the Timeline can kill them | 1. HEAL\_SINGLE. 2. Strongest-fit potion (smallest item that restores the missing HP, so Elixir-class items are saved). |
| Low HP | Ally under 50% and no one is critical | HEAL\_SINGLE if MP is healthy; otherwise a potion. |
| Party-wide damage | 3 or more allies under 60%, or a known AoE enemy | HEAL\_ALL; otherwise Regen-type buff; otherwise two potions over two turns. |
| Harmful status | Poison, blind, silence, sleep or similar on an ally | CURE\_STATUS skill, then matching cure item (Remedy). Silence on a caster is treated as high priority because it locks their MP skills. |
| Healer is down or silenced | No HEAL tag usable | Any other ally uses items; the AI never waits for a healer. |

**Item budget.** The AI keeps a reserve of one revive item for the party, unless the battle is flagged as a boss fight, where reserves can be spent. On normal encounters it prefers to end the fight quickly and rely on end-of-battle MP restores rather than spend premium items.

**Timeline use.** If a heal is needed and a stagger is about to land on the threatening enemy, the AI may skip the heal because a staggered enemy loses its action. It only does this when the stagger is guaranteed by the previewed gauge estimate.

## MP economy

Because every Vision skill is paid from the character's own MP, a build with a big skill set can run dry in a long fight. The AI treats MP as a budget per character and spends it in proportion to how much fight is left.

- **Budget bands.** Above 50% MP: any skill. 20 to 50%: only skills that tag as HEAL, STAGGER\_HEAVY or a known weakness hit. Under 20%: free attacks and MP recovery only.
- **Recover in this order.** (1) Free MP effects already in the build: MP-restore on stagger, on kill, on critical hit, Syphon-type drain skills. The AI prefers actions that trigger these, for example choosing the stagger-finishing hit when the passive is equipped. (2) MP\_RESTORE\_SELF skills. (3) An Ether-type item on that character, only when they hold a role-critical skill (heal, revive, key weakness) that they can no longer afford.
- **Cheap-first damage.** Among skills that hit a known weakness, pick the lowest MP cost whose stagger is enough to finish the gauge this turn. The AI never uses a 40+ MP skill on a gauge that a 5 MP skill empties.
- **Item routing.** Ethers go to whoever is out of MP and still has a high-value skill, not to whoever has the lowest percentage.
- **Summons.** An Esper costs MP and stays a fixed number of turns (the game shows Bahamut at 50 MP for 3 turns). The AI summons only when the fight is projected to last longer than the summon's duration and a stagger or boss window is coming.
- **Between fights.** The AI does not spend items to refill MP between encounters when the game offers end-of-battle recovery or resting options.

## Stagger and Resonance planning

Damage is not the goal until enemies are staggered; the gauge is. The AI picks targets and skills to empty gauges, then bursts.

1. **Find weaknesses.** Use ANALYZE (Libra-type) once per new enemy type if any character has it and spare MP; otherwise read the weakness from attack previews, and remember what each enemy took extra damage from.
2. **Pick the attack by preview.** Each attack shows its stagger estimate before use. The AI chooses the skill with the best stagger per MP against that enemy's known weakness, and prefers all-target skills when two or more enemies are close to staggering.
3. **Aim for a sweeping stagger.** With several enemies, the AI avoids staggering one early if it can set up all of them in the same turn. It chips the others first, then finishes the gauges together, because a sweeping stagger grants the bonus phase and a Resonance attack.
4. **Spend the stagger window.** While an enemy is staggered it loses its action and takes extra damage, so the AI uses its strongest damage skills and any buffs it has queued, not heals, unless an ally is critical.
5. **Resonance.** When offered, the AI always fires it. Preview builds could fire it even if enemies died mid bonus phase, which also tops off HP, so killing during the window is not wasted.
6. **No usable weakness.** If the build has no skill matching any weakness, the AI uses the highest-stagger skills it has, then plain attacks, and accepts a longer fight with more defensive play.
7. **Boss behavior.** Use debuffs and buffs on turn one (Shell, Haste, Blind, defense down), then cycle: break the gauge, burst in the window, recover during the recovery turn.

## Edge cases, fallbacks and open questions

| Case | Behavior |
| --- | --- |
| No healer, no items | Defensive skills (Shell, Protect-type buffs, Sentinel enmity), then kill fast; flee option if the game allows and the party is losing |
| No weakness hit available | Highest stagger per MP, then free attacks (see stagger section) |
| All MP-skilled, all out of MP | Free attacks; Ether to the character with the most valuable skill; Syphon-type skills if present |
| Enemy immune or absorbs an element | Tag the skill as bad for that enemy and never use it again this battle |
| Enemy counters or has a charge-up | If the Timeline shows a heavy move next, prefer a heal or stagger before it lands |
| Healer is KO'd | Revive the healer first if it costs one action; otherwise items |
| Player changes gear or Vision mid-run | Re-scan tags before the next turn |
| Unknown skill the tagger cannot classify | Treat as a normal damage skill only if the preview shows damage; otherwise skip it |

**Open questions for the real game**

- Can the auto-battle read skill descriptions and stagger previews through an API, or only the menu? The design assumes it can read both.
- Do items have shared stacks across the party, and is there a per-battle item limit?
- Does the player want a manual override per character (for example never use premium items)? A toggle for item aggressiveness (Conservative, Normal, Free) is recommended.
- Exact numbers (30%, 50%, MP bands) are starting values to tune in playtests.

## Sources

Mechanics come from search results read on 2026-10-28; item names are from the Digital Deluxe contents, and specific item numbers are not confirmed.

- [Final Fantasy Resonance (wiki)](https://finalfantasy.fandom.com/wiki/Final_Fantasy_Resonance): turn-based, four-character party, roles, sweeping stagger
- [Combat mechanics](https://meowdb.com/db/final-fantasy-resonance/mechanics/combat): Timeline, stagger gauge, Espers
- [Staggering tutorial](https://meowdb.com/db/final-fantasy-resonance/tutorials/staggering-break): stagger preview, weakness
- [Starting Visions guide](https://meowdb.com/db/final-fantasy-resonance/guides/starting-visions): Vision spells and MP costs
- [What is Combat Like?](https://gmtreks.com/final-fantasy-resonance/page/01M4CZTC6T1NXYA757VKMNKKAR): Vision MP, Esper cost and duration
- [Resonance Attacks](https://thegameswiki.com/final-fantasy-resonance/wiki/resonance-attacks): bonus phase behavior
- [Nintendo store page](https://www.nintendo.com/au/games/nintendo-switch/final-fantasy-resonance/): Mist Potion, Mist Ether, Phoenix Down, Remedy items
- [Game Informer review](https://gameinformer.com/review/final-fantasy-resonance/on-its-own-wavelength): no auto-battle option in the base game
