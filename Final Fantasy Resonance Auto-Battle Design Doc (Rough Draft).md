# Final Fantasy Resonance: Auto-Battle Design Doc (Rough Draft)

The auto-battle never assumes a build: at battle start it reads each character's actual skills, tags them by function, and then runs one priority ladder each turn that keeps the party alive, keeps MP available, and drives enemies toward stagger.

This is v0.1.33. Two switches sit on top of that ladder. They do not open a menu, and both choices are remembered.

- F10, and the right trigger during a fight, turns auto battle on or off. The screen flashes AutoBattle On or AutoBattle Off. It starts on. While it is off, the planner still records the commands the player chooses and the state of the fight. Turning it back on in the middle of a fight plans from that fight.
- F9 chooses the plan. On flashes AutoBattle: Take it Easy! and sends the Attack command only. No MP and no items. Off flashes AutoBattle: No Mercy! and runs the ladder below. Off is the default. During a fight, while auto battle is on, the left trigger does the same. The game still receives that press.
- While auto battle is off, or outside a fight, the left trigger stays with the game. F9 and F10 work any time.
- Battle speed is the game's own button and marks. Auto battle leaves them alone.
- Take it Easy is outside everything below: the free Attack only, no MP, no items, no Esper, and it never escapes.

## Game facts the AI relies on

The AI only uses mechanics that hold in every build; anything Vision-specific is discovered at runtime, never hard-coded.

| System | What the game does | What the AI does with it |
| --- | --- | --- |
| Turn order | Turn-based with a visible Timeline of upcoming ally and enemy actions | The Timeline is not readable. Party order and the stagger ledger stand in for it |
| Stagger gauge | Each enemy has a gauge under its HP; weaknesses drain it faster; at zero the enemy loses its action and takes more damage | Main damage goal: empty gauges, then burst. The book's Normal gauge is the count. Reaching it marks the enemy broken. If the bonus does not arrive within about one round, and no bonus has confirmed that gauge yet, the poured count is kept and the working gauge rises, by at most a quarter over the book. If that bonus then arrives before the new gauge is filled, or the gauge refills during that same short wait, the size goes back. While that wait is open the enemy is cashed with the broken bodies and is not built. A bonus confirms a gauge the fight has filled. A risen gauge that is still unfilled becomes the stagger that had been poured. After a bonus has confirmed it, a later miss clears the count and the size stays. The live break ratio stays full, so the ledger is the count |
| Sweeping Stagger | Staggering all enemies in one turn gives a bonus phase ending in a Resonance attack | Plans turns so the last gauges empty together. A normal spell is not sent as the Resonance move. The wheel is left for the player when the equipped Finish Blow is not found |
| Visions | One equipped per character; grants that Vision's skills, paid with the character's own MP | Reads the actual skill list, never assumes a Vision |
| Roles | Sentinel, Breaker, Medic, Commando, Saboteur, Synergist | Not read. Skill tags decide behavior. Role skills (formations, marks, Provoke, Cover, Haste) are spent from the kit book by name, never by the role |
| MP | Skills cost MP; Ethers, MP-on-stagger, MP-on-kill and end-of-battle restores exist as passives or gear | MP budget drives skill choice |
| Items | Potions, Ethers, Phoenix Down, Remedy and similar are in the starter packs | Auto-use as a team resource, with reserves |
| Libra | Cheap spell revealing an enemy's weakness, drops and traits | Spent once when the name is missing from the book, or the card says the weakness shifts. A hit that already landed does not skip that Libra. The result is not read back |

Skill lists, costs and stagger values vary per Vision and character, so the doc treats them as data read from the party, not constants.

## Build-agnostic skill tagging

At battle start, and again whenever a Vision, gear or status changes, the AI scans every usable skill and item and gives each one tags. Decision rules then ask for tags ("a heal that hits one ally"), never names ("Cure"). The live row supplies cost, power, stagger, target, and effect. The catalog supplies the element, the use, whether the hit is physical or magic, and whether a published heal hits the whole party. A name known.lua lists keeps its values; a field it leaves out comes from the catalog, and its kind of hit is one fact. Description text is not read. A build with no healer simply has no heal tags, and the rules fall through to items.

| Tag | How it is detected | Used for |
| --- | --- | --- |
| HEAL\_SINGLE / HEAL\_ALL | The live target is one ally or the party, or the catalog marks the heal as hitting all allies. The row restores HP | Healing before items |
| REVIVE | Skill or item removes KO | Revive rule |
| CURE\_STATUS | A cure effect on the live row | Sleep, silence, paralysis, confuse, petrify, charm, stop, berserk, or doom on a living ally. Poison, blind, and slow are cleared only when they are bad enough. A broken stat is not this row |
| BUFF / DEBUFF | Raises ally or lowers enemy stats, Shell, Haste, Regen | Setup turns |
| DAMAGE\_ELEM(x) | Deals element x damage, single or all targets | Weakness targeting |
| DAMAGE\_PHYS | Physical damage skill, often 0 MP | Free fallback damage |
| STAGGER\_HEAVY | High stagger value relative to damage; the game shows the estimate before attacking | Gauge breaking |
| MP\_RESTORE\_SELF | Skill that drains or restores own MP, or MP-on-stagger effects | MP economy |
| ANALYZE | Libra-type skill | Weakness discovery |
| SUMMON | Esper with MP cost and a turn duration | Burst windows |
| FREE\_ATTACK | Basic Attack, 0 MP | Last-resort action |

An unnamed spell is still cast, on its own stagger, with no weakness multiplier until the catalog names the element. Every character always has at least FREE\_ATTACK, so the AI can always act.

## Party brain: one planner, not four soloists

Yes, the characters must know each other's moves. One shared planner fills the slot that is open. The characters carry that slot out. Four independent pickers would double-heal, stack the same buff twice, waste a stagger one turn early, and revive the same ally twice.

**Shared state the planner keeps**

- Every enemy: HP, the forecast still to pour, known weaknesses and immunities, and whether the card has a danger move.
- Party order: the ally whose menu is open. The Timeline is not readable, so it is not who acts next.
- Every ally: HP, MP, statuses, and the tags of every skill and item they can use.
- **Claims:** when the planner assigns an action it reserves its effect (this heal covers Ally B, this debuff is on Enemy 2, this Ether goes to Ally C). Later actions see the claim and pick something else.
- **The round:** one turn for each party member who can take one. A fallen ally, a summon, and an ally whose status takes the turn are not waited on, and a round never runs past two passes of the party. Claims last one round. Party size sets only how long a round is. It never switches a rule; "most of the party" is a share of the living party, the same at any size.
- **The party:** whoever is on the field when the fight begins. A friend that arrives later with no skill list, or one the Esper book names, is a summon. It is not healed, raised, counted, or waited on.
- **The ledger:** each connecting hit adds its stagger, times the weakness factor, to that enemy. The book's Normal gauge is the forecast. The bonus phase confirms the break.

**How a turn is planned**

1. Read the ally whose menu is open, and the living field.
2. Walk the ladder for that one slot. Score damage against the ledger, not against a queued round.
3. Setup, when it runs, comes before the first chip. Heals come before offense on the lines in the healing section. A finish waits until the gauges in the pool can fall together.
4. After the action, the ledger takes the hit. The next open menu is planned from that state.

The live row's stagger is the count for an unnamed spell. Element comes from the catalog when the spell is named there. An unnamed Vision spell is still cast.

## Multi-enemy targeting

The party neither all hits one target nor splits evenly, and it does not wing it. It scores every enemy each round, and the score decides where damage and stagger go.

| Factor | What raises the enemy's priority |
| --- | --- |
| Threat | Its card has a danger move. Among hits with similar stagger, that body scores higher. A `call` mark scores a little higher. There is no separate support mark |
| Support role | A card marked `call` replaces its escorts. That is the large body to hold, not an add to clear |
| Stagger proximity | Its gauge is close to empty given what the party can deal this round |
| Weakness fit | A party skill hits its weakness, so stagger per MP is high |
| Kill value | Low HP: one more hit removes an action from the Timeline for good |
| Immunity or absorb | Lowers priority for that element only, never for the whole enemy |

**Adds versus one plan.** Size class decides the pool. A gauge is an add only when it is at or under 60% of the largest gauge still up. Those are cleared first, and the larger gauges are held. Equal gauges, including a tie for the largest, stay on one shared plan. A `soft` or `call` mark does not pull a near-equal gauge into the adds. A danger move on the large body does not pull the smaller gauges off the adds plan. When the style is defensive, someone is critical, and the danger body's forecast is under 40%, the pool narrows to that body.

**Sweeping stagger timing.** Emptying one gauge while its partners are still high spends the bonus on one body. Inside one plan, a hit that would finish one enemy while another is still above 40% of its forecast is held, unless the hit is a weakness and nothing cheaper in that element can chip. An area spell chips the pool. A single-target weakness finishes when the set can fall together.

**Focus versus split.** Focus on one enemy for HP damage when the sweep is not reachable (for example an immune boss), and split chip damage across gauges when it is. Overkill is avoided: the planner never puts a big-MP skill on a target that a cheaper one already finishes.

## Fight phases and strategy style

At battle start the planner scores the party against the enemies and picks a style. It then moves through phases and may jump back when things change.

| Phase | Goal | Typical actions |
| --- | --- | --- |
| 1. Scout | Learn weaknesses and threats | Libra once when the name is missing from the book, or the card says the weakness shifts. A hit that already landed does not skip that Libra. Otherwise the fight goes on to setup and the chip |
| 2. Setup | Make the party safe and the enemy weaker | Shell and Haste-type buffs, Blind and defense-down debuffs, summon if the fight will last |
| 3. Chip | Bring all gauges near zero without wasting a stagger | AoE or weakness hits, kill fragile support adds |
| 4. Break and burst | Empty every gauge in one round, then spend the bonus phase | Highest-damage skills on the enemies who just broke, not on a body that walked in during the window. The Resonance wheel is the player's when the Finish Blow is not found |
| 5. Recover | Reset after the enemies recover | Heals, cures, MP restores, then back to phase 3 |

**Style, chosen from the field and who can still heal.** A living enemy whose card has a danger move, or a boss flag, is a hard field. A healer counts only when they can pay their heal cost.

- **Aggressive:** the field is not hard and a healer can pay. The opener can run. Guard, debuff, Limit Burst setup, and Esper wait.
- **Balanced:** the field is hard and a healer can pay, or the field is not hard and nobody can pay a heal. On a hard field, one guard and one debuff go out before the first chip.
- **Defensive:** the field is hard and nobody can pay a heal. The same one guard and one debuff, and the pool can narrow to the danger body when someone is critical and that forecast is under 40%.

The style is re-evaluated every turn, so a party that spends the last of a heal's MP shifts on its own. Setup does not start after someone has fallen or while someone is under 30%. A paid chip waits while an ally can still cast the one guard, the one debuff, or the one setup Limit Burst, except after a fall or while someone is under 30%. The weakness that must survive that spend can be on another ally. An Ether or a free Attack does not close the window. The setup Limit is cast once, on the turn its gauge can pay it. If that gauge fills after a chip, it still goes out once, until someone has fallen or is under 30%. An empty gauge is left to fill. One full gauge pays a 100% row. Two pay a 200% row. A cash Limit Burst is the spend on a hard fight's bonus phase, including when the skill row has no magnification. It is not spent while the ledger has marked a break and the bonus has not arrived. A soft pack does not take it.

**Proving it works for every build.** Before release, run the planner in a simulator against many random parties (every character crossed with every Vision, with and without healers, AoE, weakness coverage and items) and fight types (single enemy, groups, boss with adds). The pass conditions: never stall, never waste a revive, never spend premium items on trivial fights, and win more often than a plain "attack with the strongest skill" baseline.

## Turn decision loop

&#91;embedded content: turn priority ladder, 8 rules\]

Every character on their turn walks this ladder and takes the first rule that fires. Rules 2 to 5 are the care layer (revive, heal, cure, MP); rules 6 and 7 are the offense layer. Thresholds are starting values to tune.

## Healing and item rules

The party's HP is one shared pool of risk: the AI picks the cheapest tool that fixes the problem, in this order: free effect, MP skill, item. A heal spell whose cost still fits is spent before a potion, including when MP is under 20%. That care line is outside the offense band. Under 30% is healed first. An ally who enters the fight down is raised before that, including on the first round when one weak enemy is all that is up. Doom, a lock, and silence already on a living ally are cleared before the opening heal. Poison, blind, and slow stay on their own lines. At the start of the fight, before the party has each acted once, an ally under the recover line is healed without waiting for the bonus or for MP to be above half. After that round, under 50% is healed when MP is above half and either several allies are hurt or the bonus window just ended. While a danger move is up and that gauge is still open, the recover line for the lowest ally is 65%, and it does not wait for the bonus. When most of the living party is under 50% (three of four, three of three, two of two), the heal is the party heal if this character has one, and it beats every single heal, including when that row has no magnification. Fewer hurt allies keep the single heal. The party heal has to be on the character who is acting. Rare items stay in the bag outside a boss fight (see Boss fights). A Pot fight spends nothing. One Ether per round, unless a boss fight is in dire need.

| Situation | Trigger | Action, first available |
| --- | --- | --- |
| Ally KO'd | Any ally at 0 HP | 1. REVIVE skill from a healthy ally, including a revive Limit Burst when its gauge can pay it. 2. Phoenix Down. An ally who can pay a raise spell does it better than an item, so the others leave it to them while they still have a turn this round; a raiser out of MP, held by a status, or already gone this round is not waited on. The living come first: a raise waits while a living ally is under 30% and not yet healed this round, unless the fallen ally is the party's best healer (heal score, then a raise spell, then the number of heals). An ally who fell again within two rounds of a raise is not raised again for three rounds, or sooner once no living ally is under half, for the best healer too: the Timeline is not readable, and that is the sign the next hit would drop them again. The same ally is not raised again until they are standing, and a retry waits until the party has acted. Do not revive if the fight is about to end (one weak enemy left, no threat). |
| Critical HP | Ally under 30% HP | 1. A payable heal. A party heal when three or more allies are under 50%. 2. Smallest potion that restores the missing HP. Elixir-class items stay in the bag, except in a boss fight under dire need. The ally who is the only one able to pay a weakness on the current pool keeps chipping while the hurt ally is at or above 15% and someone else can still heal. Under 15%, that chipper heals too. The healer is the living ally who can act and whose kit has the highest heal score. A tied score goes to the kit with more real heals. Anyone else leaves the heal while that healer can act and pay and still has a turn this round, unless the hurt ally is under 15%, or under 20% while a danger gauge is open. A slowed healer raises those lines to 25% and 30%. Able to act and pay means alive, not stopped by sleep, paralysis, petrify, confuse, charm, stop, or berserk, not silenced on a spell heal, and the heal cost fits. A healer who is out of MP, or silenced, still uses a potion on their own turn. |
| Low HP | Ally under 50%, no one is critical, MP is above half, and either several allies are hurt or the bonus window just ended. Before the party has each acted once, an ally under the recover line is healed without that wait. While a danger gauge is open, the lowest ally under 65% | A heal spell whose cost fits. A party heal when three or more allies are under 50%. Otherwise a potion. The danger line does not wait for the bonus. A non-healer does not spend a heal or a potion on this line while a healer can still act and pay. Once two others have acted and a slowed healer has not, that wait ends. With no healer who can act and pay, this row stays as written. |
| Party-wide damage | Most of the living party under 50% | A group heal beats every single heal. A row with no magnification still takes the group heal on that spread. A patch stays a last resort. |
| Harmful status | Doom on anyone is first. Then a status that takes the main healer's turn. Then sleep, paralysis, stop, petrify, confuse, charm, or berserk on anyone, before the recover line. Silence on someone whose spells matter, when nobody is critical. Poison on that ally, under about 60% HP. Blind on a physical attacker. Slow on the healer, on the only ally who can pay the current weakness, or on the ally a stagger window needs, once it has lasted two rounds. Other slows are last, and only the healer clears them. Poison, blind, and slow wait while anyone is dead, critical, or under the recover line, and they wait through the setup window and the bonus | Doom, the healer's lost turn, and the other turn-taking locks are cleared before the recover line. The healer's lost turn spends the matching item before a cure spell. The other locks spend the cure spell first. Silence on the healer spends Echo Herb or Remedy only. Poison and blind are that ally's own item on their own turn. Nobody spends a turn on someone else's poison or blind. The healer clears Slow with a cure spell whose row lists Slow, when the MP left is still above half and a heal is kept back. A non-healer casts that cure only when no healer can act, and only for the healer, the weakness payer, or the stagger finisher. Nothing is spent until Slow has lasted two rounds. A slowed healer raises the dire line, and the others stop waiting on the recover line after two of them have acted. A cast counts only after it goes out. Two misses mark that cure as not working for the launch. A Slow that ends after the cast is not counted as that cure working. If no cure spell lists Slow, that cure is skipped and the battle log says so once. Haste is the other answer: an ally who carries Haste casts it on a slowed ally, on any field. A cure spell is aimed at a status its row lists; a cure that went out and left the same status is a miss, and two misses retire it for that status this fight. Remedy is not spent on poison, blind, or slow, and the last one is kept for the healer or for doom. Antidote and Antidote Herb match poison. Eye Drops match blind. Echo Herb, Smelling Salts, Unicorn Horn, Gold Needle, and Herb of Awakening match silence, confuse, paralysis, petrify, and sleep. A cure name the book does not list is still spent on a lock. When nothing matches, the turn is a swing. An unknown status id is written once. A broken stat is not this row. |
| Healer is down, silenced, or locked | No HEAL tag usable, or the healer cannot act | Any other ally uses a heal or the item that clears the healer's status. The AI does not wait for that healer. One ally claims the cure so a second ally does not spend the same round on it. |

**Item budget.** Phoenix Down is spent when no ally who still has a turn this round can pay a raise spell. There is no saved reserve. A status item is spent only when it clears a status this row is curing. Remedy is not spent on poison, blind, or slow, and the last one is kept for the healer or for doom. Outside a boss fight, Elixir, megalixir, X-tier items, turbo ether, a phoenix pinion, a tent, and scrolls stay in the bag. On a Pot fight nothing is spent. The planner does not refill the party between fights.

**Boss fights.** A boss fight, the one the game flags as a boss, is burn-if-you-have-them. A rare item (Mist Hi-Potion, X-Potion, Turbo Ether, X-Ether and their Mist forms, Phoenix Pinion, Elixir, Megalixir) is spent when no common item does the job, the cheapest rank first. A Phoenix Pinion goes out at once when no Phoenix Down is left. A rare heal or MP item waits for dire need: an ally down, an ally under 30%, or most of the living party under half. Dire need also lifts the one-Ether-per-round limit. Thrown items are the boss fight's too. A scroll goes on a weakness in the pool when the actor's bar cannot pay a hit in a weakness. When nothing payable on the bar lands, any scroll, knife, or shuriken that lands is thrown instead of a Defend. Tents and Healing Spring stay in the bag. A Pot fight spends nothing.

**Who keeps chipping.** The ally who is the only one able to pay a weakness on the current pool skips a heal while the hurt ally is at or above 15% and someone else can still heal. Under 15%, during the bonus, and when no one else can heal, that ally heals too. Able to pay means the spell's cost fits that ally's current MP.

**The only payer of the large gauge.** In an adds plan, the ally who is the only one able to pay a weakness on the held large gauge keeps chipping it while another ally can pay a weakness on the adds. The adds are left to the others.

## Role skills, draws, and Haste

These are spent from the kit book (`kits.lua`) by name. A name the book does not list is left on the bar. Each waits while someone is critical or a fallen ally is still down, a paid one goes while MP is above the low band, and a carried heal is kept back.

- **Formations and their setup.** A formation, the skill that sets one up, a stagger mark, one weakness on an enemy the book leaves bare, and a luck toss. The setup skill goes only when the formation it sets up still fits after it.
- **Draws: Provoke, Cover, Multi-Cover.** They answer a danger move still open on the field, or a healer under the recover line. A calm field spends none. The party's best healer does not pull attacks (equal heal kits cover each other), nor does an ally under the recover line, and there has to be someone else to protect. A hurt healer gets Cover first, then Multi-Cover, then Provoke; otherwise Provoke first. One draw at a time: a second waits while another is up. A cast is held while its status shows; with no status, Provoke for its three rounds and a Cover once a fight. Timing counts rounds, so Haste does not shorten it.
- **Haste.** A slowed ally first, on any field. On a hard field while MP is above half, the healer and then the strongest damage dealer. Held while its status shows, or once per ally a fight. One per round. Hastega when two or more want it. Enemy Slow stays the fallback debuff.
- **Generic buffs.** Faith, Bravery, Focus Magic, and the rest stay on the bar.
- **Support, then a hit.** Once the fight is underway, a role skill or a debuff refresh is followed by a hit, when the ally has a hit that lands. Support does not crowd out the damage.
- **The guard.** One per kind a fight, before the first paid chip on a hard field. It matches the danger's kind of damage when the card gives it (`hits`): Shell for magic, Protect for physical. With no kind on the card, one guard of any kind. In the sim, casting it again as it wore off cost more turns than it saved.

## MP economy

Because every Vision skill is paid from the character's own MP, a build with a big skill set can run dry in a long fight. The AI treats MP as a budget per character and spends it in proportion to how much fight is left.

- **Budget bands.** Above 50% MP: any fitting spell. From 20% to 50%: a heal, a heavy stagger, or a known weakness. Under 20% the offense spend is a known weakness whose cost still fits, or a free attack. When no free hit can land on a body, a paid hit that lands is allowed in any band, and it is not held for the setup. A heavy hit that is not the weakness waits. A care-line heal whose cost still fits is still cast.
- **One Ether.** It is spent on the character whose turn it is, when a heal they are holding no longer fits, when nothing payable lands and a hit on the bar would, or when MP is under 20% and a known weakness no longer fits. One Ether per round, unless a boss fight is in dire need. It is not handed to a different character.
- **Cheap-first damage.** Among skills that hit a known weakness, a hit that would finish a gauge while a partner in the same plan is still above 40% is held, unless nothing cheaper in that element can chip. An absorbed element is left alone.
- **Summons.** One Esper before the first paid chip, on a hard field, when the style is not aggressive, and not after a fall or while someone is under 30%. Its cost has to leave a weakness payable, or three or more enemies have to be up.
- **Between fights.** The AI does not spend items to refill MP between encounters.

## Stagger and Resonance planning

Damage is not the goal until enemies are staggered; the gauge is. The AI picks targets and skills to empty gauges, then bursts.

1. **Find weaknesses.** Libra once when the name is missing from the book, or the card says the weakness shifts. A hit that already landed does not skip that Libra. The break ratio stays full, so a weakness is not learned by watching the gauge move. The book is the weakness list.
2. **Pick the attack from the row.** The catalog stagger, or the live row when the spell is unnamed, is the count. The skill with the best stagger against that enemy's known weakness is chosen. An area spell chips the pool when more than one gauge is still up and the element is not absorbed.
3. **Aim for a sweeping stagger.** With several enemies, the AI avoids staggering one early if it can set up all of them in the same turn. It chips the others first, then finishes the gauges together, because a sweeping stagger grants the bonus phase and a Resonance attack.
4. **Spend the stagger window.** While an enemy is staggered it loses its action and takes extra damage, so the AI uses its strongest damage skills on the bodies that just broke. A body that walks in during the window does not take that bonus. Heals wait unless an ally is critical. When an add broke and the large gauge is still open, a bonus turn that can pay the large gauge's weakness goes there instead: the broken add has already lost its turn.
5. **Resonance.** The planner looks for the equipped Finish Blow and sends it when that skill is found. It does not put a normal spell on the wheel, and it does not guess a command-bar id as a Vision id. When the lowest ally is under 40%, or two allies are under 40%, a heal on that wheel is sent instead, and a party heal hits the whole party. When the Finish Blow is not found, the wheel is left for the player.
6. **No usable weakness.** If the build has no skill matching any weakness, the AI uses the highest-stagger skills it has, then plain attacks, and accepts a longer fight with more defensive play.
7. **Danger and bosses.** One guard, one debuff, and one setup Limit Burst before the first paid chip, on any card with a danger move and on a boss, when the style is not aggressive. Not after a fall, and not while someone is under 30%. A paid chip waits while an ally can still cast that guard, that debuff, or that setup Limit Burst. The weakness can belong to another ally. The setup Limit is cast once, on the turn its gauge can pay it, including when that gauge fills after a chip, until someone has fallen or is under 30%. That stagger is counted. A second setup Limit stays in the gauge. An empty gauge is left to fill. One full gauge pays a 100% row. Two pay a 200% row. A revive Limit is a raise when someone is down and the gauge can pay it, on any fight. A cash Limit Burst is the spend on a hard fight's bonus phase, ahead of a normal spell, including when the row has no magnification. Its published stagger is not the cash score. It is not spent while the ledger has marked a break and the bonus has not arrived. A soft pack does not spend it. An absorbed element is left alone. While that danger gauge is open, the lowest ally is recovered up to 65%. A status cure is never aimed at an enemy.
8. **The book gauge.** When the poured stagger reaches the working gauge, the enemy is marked broken and the burst can start. Hits while it is marked are not added. If the bonus phase does not arrive within about one round of ally actions, the mark is cleared. Until a bonus phase has confirmed that enemy, the poured count is kept and the working gauge rises to about the poured amount divided by 0.72, capped at a quarter over the book, and at least the poured stagger plus one. The log says `working gauge`. If that bonus arrives before the new gauge is filled, or the gauge refills during that same short wait, the size goes back to the one from before the rise. The log says `working gauge restored`. While that wait is open the enemy is cashed with the broken bodies and is not built. A bonus confirms a gauge the fight has filled. A risen gauge that is still unfilled becomes the stagger that had been poured. The log says `poured stagger`. Once a bonus phase has confirmed the size, a later miss clears the poured count and the size stays. The log says `working gauge stays`. A bonus that returns to the command phase resets the poured count for the enemies that were marked and keeps the learned size. A new battle clears it.

## Edge cases, fallbacks and open questions

| Case | Behavior |
| --- | --- |
| No healer, no items | The one guard and the one debuff on a hard field, then the chip and free attacks. The planner does not flee |
| No weakness hit available | Highest stagger per MP, then free attacks (see stagger section) |
| All MP-skilled, all out of MP | A free attack. One Ether on the character whose turn it is, when a known weakness no longer fits. It is not handed to someone else |
| Enemy immune or absorbs an element | That element is not spent on that enemy. The book supplies the absorb and the immunity. It is not learned from the gauge |
| Enemy nulls a kind of hit | Physical or magic. The book marks it, and a fight learns it: two hits of one kind in a row that leave the enemy's HP where it was mark that kind as nulled on that enemy. A kind that already took HP off that enemy in this fight, with no summon out, is not learned as nulled. It is a miss like a nulled element. The fallback swing lands or the ally Defends, and the wheel is left for the player when no finisher lands |
| Enemy counters or has a charge-up | A danger move on the card is the signal. One guard and one debuff before the first paid chip, and the recover line for the lowest ally is 65% while that gauge is open |
| Healer is KO'd | The party's best healer is raised at once, ahead of the wait on a critical ally, unless they just fell again after a raise |
| A summon is out | It is not a party member: not healed, raised, counted, or waited on. Its leaving is not a fall |
| Stalemate | Five rounds of the party's hits on enemies with no enemy losing HP and no bonus phase. Setup, heals, items, and a confused ally's swings do not count. The party escapes when the game allows it. Not in a Pot fight, and never in Take it Easy |
| The party wipes and the game retries | Every party member down marks a wipe. A party member standing again after it is a retry, at any HP or MP: the stagger ledger and the one-time setup start over. The log says `party restored` |
| An `evade` card | Not read. A physical hit that takes no HP twice marks physical as nulled for that fight, so the party turns to magic. How the game breaks these enemies is not known yet |
| Player changes gear or Vision mid-run | Re-scan tags before the next turn |
| Unknown skill the tagger cannot classify | Treat as a normal damage skill only if the preview shows damage; otherwise skip it |

**Open questions for the real game**

- The Timeline is not readable. `GetTurnVM` throws. Party order and the stagger ledger stand in for it.
- The live skill row has cost, power, stagger, target, and effect. It does not have an element. Element stays in the catalog until a spell is named there. An unnamed Vision spell is still cast, on its own stagger, with no weakness multiplier.
- The break ratio stays full after a hit, so a weakness cannot be learned by watching the gauge move.
- Do items have shared stacks across the party, and is there a per-battle item limit?
- A toggle for item aggressiveness is not in v0.1.12. Take it Easy is the basic-attack switch, and it does not change which items are allowed when No Mercy is on. Rare items stay in the bag outside a boss fight. Common shop items are spent on the heal and Ether lines above. A Pot fight spends nothing.
- The 30% heal, the 50% recover, the 65% line while a danger gauge is open, the 15% chipper exception, the 60% adds line, and the MP bands are what the earlier playtests ran. v0.1.12 spends a heal spell before a potion whenever the cost fits, and a party heal when three or more allies are under half. That party-heal line has not had its own playtest yet. v0.1.13 leaves the recover line to the healer. v0.1.14 keeps a non-healer off that heal for the whole round while a payable healer can pay, except under 15%, or under 20% while a danger gauge is open. A healer who is asleep, paralyzed, stopped, petrified, confused, charmed, berserk, or silenced on a spell does not count as able to pay. Doom, and a status that takes the healer's turn, are cleared before the recover line. Poison and blind are that ally's own item when nothing more urgent is waiting. Slow is a spare cure from the healer after it lasts two rounds. The spell's row lists Slow. A cast counts only after it goes out, and two misses mark that cure as not working for the launch. A slowed healer is treated as late. A setup Limit that fills in after the first chip still goes out once, and it stops after a fall or while someone is under 30%. The battle log keeps the last five fights. A bonus spends on the break the ledger just marked. A body still flagged from an older wave does not take that hit. When the party comes back at its opening MP, the stagger ledger and the one-time setup are cleared. v0.1.20 still spends Libra once after a hit has already landed, when a name is missing from the book or the card says the weakness shifts. v0.1.21 spends that Libra on Sadalsuud, because its weakness changes. Iron Giant counters a physical hit. Beast of Ruin, Shinryu, and Tegmine counter any hit. Magic against Odin's Shadow or Necromonarch is no longer treated as a counter. Cactuar is marked as evading until it breaks. v0.1.22 spends Raise and Arise on a fallen ally. A living ally is left standing. A Slow that ends after the cast is not counted as that cure working. A cast that was only queued is tried again when that ally acts and the cost has not been paid. v0.1.23 heals an ally under the recover line at the start of the fight, before the party has each acted once. It does not wait for the bonus or for MP to be above half. After that first round the 50% line waits as before. v0.1.24 raises an ally who entered the fight down, and it clears doom, a lock, or silence that came in with them before the opening heal. A living ally is still left standing. Poison, blind, and slow stay on their own lines. v0.1.25 spends Provoke, Cover, and Multi-Cover on a danger move or a hurt healer. v0.1.26 reads a fallen ally's bar from its slot, keeps summons out of the party, counts a round only on the party members who can act, drinks an Ether when a held heal no longer fits, leaves a raise to the ally who can pay one, holds a raise while the living are critical and after a raise that fell straight back, raises the best healer first, lets a party heal win on most of the party at any size, keeps one draw up at a time, spends Haste on a slowed ally, escapes a stalemate, and catches a retry after a wipe. A battle sim (`sim/`) plays the scripts against these rules. On the Water Dragon, expert lost twice after a long fight and normal won in 14 commands with no falls. v0.1.27 reads a kind of hit the enemy nulls from the book and learns it in the fight, matches the guard to the danger's kind of damage, lets a paid hit go when no free hit lands, swings only a hit that lands or Defends, follows a support turn with a hit, leaves the wheel when no finisher lands, ends the raise cycle guard after three rounds, and fills a skill's missing book fields from the catalog. From Shoggoth, which nulls physical hits: the party had spent about fourteen of eighty-two commands on swings that did nothing.

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
