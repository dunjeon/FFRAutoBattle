# What the game tells us

Phase 0 output. One row per read or fact. **Status:** `used` (v0.1.x already
calls it and it works), `lead` (strong evidence, not yet confirmed in our own
log), `confirm` (needs a probe run), `failed` (tried, does not work: do not
try again).

Sources: the v0.1.36 code, the FFR-Vision-Studio and ffr-bestiary projects
(both MIT, in `research/tools/`), and public guides. Third-party facts are
marked with their source.

## The big finds

1. **The live stagger gauge is probably `GetParameterByType(3)`.** The game's
   `eUnitParameterType` enum is `1 HitPoint, 2 MagicPoint, 3 BreakPoint,
   4 LimitBurstPoint, 5 Attack, 6 Defence, 7 Intelligence, 8 Mind,
   9 Agility, 10 Level, ...` (FFR-Vision-Studio `docs/build16/ffr-effects.json`).
   v0.1.x already reads 1, 2, and 4 through `GetParameterByType` /
   `GetMaxParameterByType`, but never 3. If it holds, the stagger ledger and
   its recovery rules become a fallback. The probe logs `bp cur/max` at every
   decide.
2. **The whole game is data tables, and they can be read.** Skills, skill
   effects, statuses, units (with element and status resistances), items, and
   damage formulas are DataTables under `/Game/Datatable/`. They can be read
   offline from the player's own paks (the game is not encrypted) with a
   `Mappings.usmap` dumped by UE4SS. That gives every skill's real element,
   power, stagger, target, and effect rows, and every enemy's real
   weaknesses, from the game, with no wiki needed.
3. **Status ids are known.** The full `eUnitStatusCondition` enum is below.
   v0.1.x's hard-coded ids agree with it (Break 89; Cover 34, CoverAll 35,
   Defend 36), which is how we know the source is right. **Reflect is 32.**
4. **There is a turn hook.** `CPP_UI_BattleSubsystem:HandleBeginTurn` fires
   at each shared turn (used by FFR-Vision-Studio). `CPP_BtlUnitAI:GetTurnNum`
   reads the shared turn counter (`CPP_BtlManager` field at +0x200).


## Found in the C++ header dump (2026-11-03)

- **Per-hit record.** `FindFirstOf("CPP_BtlVoiceManager").m_pSkillObj`
  (`UCPP_BtlSkill`) `.m_DamageVariationDataList`, each an
  `FBTL_EFFECT_UNIT_PARAMETER_VARIATION_DATA`: `pActionUnit`, `pTargetUnit`,
  `LimitBurstPoint`, and `unitParameterVariationData` with
  `beforeVariationValue`/`afterVariationValue` (HP), `breakDamageValue`,
  `beforeBreakPoint`/`afterBreakPoint`, `resistance`, `elementList`,
  `DamageType`, `damageMultiplier`, `isCritical`, `isMiss`, `isDefence`,
  `isTriggeredBreak`, `isOnBreak`, `SkillId`, `addEffectId`. Seen live in the
  v0.1 probe log: `beforeBreakPoint 100 -> afterBreakPoint 0` on a break.
  This answers R1, R3, R9 (element per hit), and R10 (resistance per hit).
- **Timeline.** `CPP_VM_BtlTimeLine:HandleUpdateTimeline(delval)` receives a
  `CPP_BtlTimelineUpdateDelVal` with `currentTimelines`, `nextTimelines`,
  `additionalTurnTimelines` (unit unique ids). `EUIBtlTurnTimeLine`:
  0 Current, 1 Next, 2 Additional. R2.
- **Danger warning (likely).** `CPP_VM_BtlTimeLine.RiskUnitUniqueIdList`,
  updated through `HandleUpdateRisk`, with `ActionSkillId`.
- **Prediction.** `CPP_BFL_Battle:GetPredictionTimeline(out ids, actor,
  targets, skillId)`: the order if that skill is used. Not called yet.
- **Unit list.** `GetBattleUnitListByRelation(out units, relation,
  isAliveOnly, bIncludeUnselectable)` returns `ACPP_BtlUnit` objects; the id
  is `m_UniqueId`. `UCPP_BtlUnitParameter` has `GetBreakPoint()`;
  `GetParameterByType(type, bUseMax)`.
- **Also there:** `CPP_BFL_Battle:IsAutoBattle()`, `UCPP_BtlAutoCmdManager`.

- **Confirmed live (v0.3):** the Timeline hook works in game: `timeline current
  [3,1,9,2,0,8] next [3,1,2,8,9,0]`. `FSKILL_DATA` (header dump) has
  `element`, `isReflectPenetration`, `hitCount`, `magnification`,
  `breakDamageValue`, `accuracy`, `criticalHitRate`, `statusCondition`,
  `effectBundleList`: R9 is answered, the skill row carries its element.

## Confirmed in game (probe v0.5, 2026-11-03, one trash fight)

- **R1 answered.** `GetParameterByType(3, false)` is the live stagger gauge:
  an enemy read `bp 120/120`, then `12/120` after two hits of 54. Max is
  `GetMaxParameterByType(3)`. Allies read 100/100.
- **Per-hit record works** (`m_DamageVariationDataList`, read at the next
  decide; each row names its actor). A two-hit Thunder spell (skill 220100,
  `elements=[5]`) on a Thunder-weak enemy: `resistance=1`, damage x1.5, 54
  stagger a hit. A Dark hit (`elements=[8]`) showed x1.3 neutral and x1.95
  on a weak enemy (1.5 x 1.3). A Cure-type heal (210010): `VariationType=0`,
  HP 395 to 821. Physical hits (`DamageType=1`) on a body already at 0 HP
  still poured stagger. `isTriggeredBreak` is set on the hit that empties
  the gauge.
- **R2 answered.** `HandleUpdateTimeline` gives the round order and the next
  round's; after unit 3 broke an enemy, `extra [3]` held its bonus turn.
- **Enums** (`mucha_enums.hpp`): `eElement` 0 None, 1 Fire, 2 Ice, 3 Wind,
  4 Earth, 5 Thunder, 6 Water, 7 Light, 8 Dark. `eResistance` 0 None,
  1 Weakness, 2 Halved, 3 Invalid, 4 Absorb, **5 Reflect**: a reflected hit
  should show in the record (R5). `eSkillDamageType` 1 Physic, 2 Magic.
  `eUnitParameterVariationType` 0 Increase, 1 Decrease.
- `GetBreakPointRatio()` read 0.1 at 12/120, so it does work here. v0.1.x
  notes say it reads full; worth a second look at when v0.1.x read it.
- **Gap in v0.5:** enemy actions' hits were not read (hits only at party
  decides). v0.6 also reads them at each turn start.

## Confirmed in game (probe v0.6, 2026-11-03, three trash fights)

- **R3 answered.** Enemy hits are read at turn start: 40 enemy hits from 9
  enemy skills, each with target, damage, and Limit points gained (1 to 2 per
  hit taken). Damage per enemy skill varies within a range (one party-wide
  spell 42-89 per hit; single hits up to 214). Some enemy skills dealt 0
  (status or buff moves).
- **Damage multipliers multiply.** Weakness x1.5 (`resistance=1`), staggered
  target x1.5 (`isOnBreak`), both x2.25, with a critical x3.375. Halved
  (`resistance=2`) halves the multiplier (0.75 on a staggered target). Buffs
  showed as x1.2 and x1.3.
- **Sweeping stagger** shows in the Timeline: `extra [1,3,0,2]` gave every
  party member a bonus turn; a single break gave only the breaker one.
- 11 breaks (`isTriggeredBreak`, gauge to 0), 21 hits on a staggered body,
  15 criticals, 3 misses, 1 Defend.
- The risk list stayed empty in the trash fights. **In a boss fight (fight 4:
  40,000 HP, gauge 1000) it read `risk [9]`, the boss,** twice. The probe
  logs the list only when it changes, on the walk 50 ms after a turn start
  or a decide. Both times the boss's own turn already showed a zero hit
  (skill 500590, no HP change, no element) while the list was still empty.
  The next turn's walk is the one that reads `risk [9]`. `ActionSkillId` on
  that read was -1 both times, so the wind-up's skill id is on the hit
  record, not on the risk read.
- The first warning stayed up through the boss's next action, a 20-hit
  party attack (skill 505830). That turn's walk already had the damage and
  the list was still `[9]`. The following turn's walk read `risk []`, in
  the same snapshot as a zero self-hit (skill 501380) and a new enemy
  entering. Gauge at the set was 439/1000 and at the clear 207/1000. Chips
  between those reads did not clear it. Fight 4 has no `isTriggeredBreak`.
  A break did not clear this warning, because it cleared with no break.
- The second warning was set the same way (500590, then `risk [9]` on the
  next turn, gauge 239/1000). The boss died on the next round, on a hit
  that left the gauge at 142/1000, and that decide's walk did not log a
  clear. One fight. The warning outlived the wind-up and was still set
  when the body died.
- **A break cancels the warned action (probe v0.8, boss fight, 2026-11-03).**
  With `risk [9]` up, the summon's weakness hit took the boss's gauge 12 to 0
  (`isTriggeredBreak`). In that same update the boss left the round's
  Timeline (`current [10,2,0,9]` became `[2,0]`), the sweep gave every
  party member a bonus turn (`extra [0,1,2,3]`), and the next turn start read
  `risk []`, before the boss's slot. So: a break before the warned body's
  Timeline slot removes its turn and clears the warning. Chip damage and
  death do not clear it (fight 4 of the v0.6 log).
- **v0.1.40 in game (2026-11-03, three fights):** the five-argument
  `CanUnitActivateSkill` answered sanely (false = MP short, or Escape in a
  boss fight). The Finish Blow was found and sent on a sweep ("resonance
  Colossal Shantotto II by Rain"), where earlier logs said "no finisher
  equipped". The warning rule cancelled 2 of 2 warned actions by a break in
  time (Basilisks). Expert Leviathan: 89 commands and 7 falls (previous
  session on v0.1.39: 128 commands, 11 falls; one fight each, not a trend);
  3 warnings landed with the gauge too high to break (917 and 1567 of 1600).
- **v0.1.37 in game (2026-11-03, three fights with probe v0.9): every break
  logged right.** Expert Leviathan: the Orb by Rain (Flame Sword) and
  Leviathan by Lasswell (Thundara), as the game gave them. Diresaur: one, by
  Nichol. Shoggoth: two, Nichol's Watera, and after the gauge refilled
  (0 to 756/800), Rain's Earth Scroll I (85 to 0). v0.1.36 had logged
  "nobody broken" for the same Leviathan fight.
- **Thrown items are not in the hit records.** The Earth Scroll break (item
  212) showed only in the live gauge; `m_DamageVariationDataList` had no
  `isTriggeredBreak` for it. Item throws (214, 212) moved the gauge with no
  hit lines. Planner 2 must take breaks from the live gauge, and treat hit
  records as the per-hit detail for skills only.
- **The bag reads** (probe v0.9: 20 to 23 consumables per snapshot) by
  asking each of the 51 consumable ids for its count.
- **The live max gauge includes the difficulty.** The same boss fight on
  Normal read 40,000 HP and gauge 1,000 (Orb 2,400 and 180); on Expert it
  read 64,000 and 1,600 (Orb 3,840 and 288), exactly x1.6. Reading
  `GetMaxParameterByType(3)` needs no separate difficulty scaling.
- **v0.1.36 missed that break.** Its battle log said "nobody broken" for this
  fight, while the live gauge read 0/1000 and the Timeline gave a sweep.
  Job 5 (live gauge) fixes this.
- **A summon is in the party unit list** (fight 4: `ally10`, with HP, MP,
  and Agility, and its own Timeline slot). The planner must keep treating it
  as a summon (AGENTS.md), not a party member.

## The game's tables, dumped offline (2026-11-03)

R8 is answered. UE4SS's Ctrl+Numpad 6 wrote
`ue4ss/FFRS-5.6.1-0+UE5-cdbc0b66.usmap`; with it, ffr-dump read every table
from the player's paks on Linux (Oodle works). The extracts are in
`research/extracted/` and are git-ignored. Dumped: `DT_SkillData` (1,167
skills, every one with `element`: 409 elemental, 758 none),
`DT_SkillEffectData`, `DT_PassiveSkillData`, `DT_CommandSkillData`,
`DT_ConsumablesItemData`, `DT_UnitParameter`, `DT_StatusConditionDetailData`
(84 statuses), `DT_SkillGeneralData`, `DT_SkillDamageCalcData`,
`DT_SkillRecoveryCalcData`, `DT_SkillTargetData`,
`DT_SkillAttributeDetailData`, `DT_GameDifficultyParam`, `DT_BattleGroup`,
`DT_UnitBattleCmd`, and the English text (`locres_en.json`).

**Monsters.** `DT_UnitParameter` holds all 643 units: 367 enemies, 229
bosses, 26 Visions, 11 playable, 10 beasts (summons); 564 have an English
name (`ST_UnitName`). Checked against `Scripts/mobs.lua` (2026-11-03): 401 of
its 409 names are found; the stagger gauge (`MaxBreakPoint`) matches on 401
of 401 and the element resistances on 400 of 401. The one difference is
Shoggoth's physical null, a damage-type immunity that is not in the element
list. The 8 not found are naming (apostrophes, alternate forms). Danger
moves, counters, and ailment immunities in the book are from enemy behavior
and are not in these tables. `DT_BattleGroup` lists every encounter.

Facts from them so far:

- **Difficulty** (`DT_GameDifficultyParam`): Expert enemy HP x1.6, **stagger
  gauge x1.6** (`EnemyBreakRate`), speed x1.4, damage taken x1.4, damage dealt
  x0.8. Easy: HP x0.6, gauge x0.4. `mobs.lua` keeps the Normal gauge, so on
  Expert v0.1.x under-counts every gauge.
- **Reflect status row:** not cleared by Esuna, cleared by Dispel, does not
  stack, can be extended.
- `DT_SkillGeneralData`: `normalAttackSkills` (the basic attacks), cost
  overrides (one skill costs 5% HP), extra costs (Good Luck points).
- `DT_SkillDamageCalcData`: which steps each calc type runs (element, hit
  count, critical, break, random, defence); Fixed damage skips element and
  break.

**Probe safety.**

- Walking the DataTables while a save is loading crashed the game (probe
  v1.2, its 20 s timer). Build the books in a fight (v1.3: first party
  menu), never on a timer at startup. v0.1.x's own skill-index walk runs
  early too; it has never crashed, but it reads fewer tables.
 v0.1 followed every object link four levels deep and the
game crashed in its first fight. v0.3 follows no links and reads the per-hit
record by field name. F7 crashed the game in v0.3 (after writing the
schema; the row walk on data-table structs found no fields). v0.4 turns F7
and the generic walk off, and logs a breadcrumb before each step.

## Reads

| Read | Returns | Status | Note |
| --- | --- | --- | --- |
| `Default__CPP_BFL_Battle:GetBattleUnitParameter(uid, true)` | `CPP_BtlUnitParameter` | used | |
| `param:GetParameterByType(1/2/4, false)`, `GetMaxParameterByType` | HP, MP, LB | used | |
| `param:GetParameterByType(3, false)` and max | stagger gauge now / max | **lead** | Probe logs it. R1 |
| `param:GetParameterByType(9, false)` | Agility | lead | Turn order input. R2 |
| `param:GetBreakPointRatio()` | reads full | failed | Leave it |
| `bfl:GetStatusConditionList(t, uid)` | status ids | used | Ids below |
| `bfl:GetBattleUnitListByRelation(t, rel, flag)` | unit ids; 1 party, 2 enemy | used | |
| `FindFirstOf("CPP_UI_BattleSubsystem").CurrentActionUnitUniqueId` | actor id | used | |
| `...BtlPhaseType`, `IsFinishPhase` | phase | used | R7 |
| `CPP_UI_BattleSubsystem:HandleBeginTurn` (hook) | each shared turn | lead | Probe hooks it |
| `CPP_BtlUnitAI:GetTurnNum()` | shared turn count | lead | |
| `FindAllOf("CPP_BtlManager")` | one per battle; `m_UnitList`, job lists with `m_ActionUnitList`, `m_TargetUnitList` | lead | The probe walks it. The action queue may be here (R2) |
| `CPP_BtlUnit:GetUnitParameter()`, `p:GetRelation()`, `p:GetUnitId()` | unit param, side, unit id | lead | Used by ffr-bestiary |
| `CPP_BtlUnitParameter.m_pOwnerBtlUnit`, `m_pVisionOwner` | owner | lead | FFR-Vision-Studio |
| `CPP_BFL_Battle:CanUnitActivateSkill`, `IsEnableCommand` | can act | used / lead | |
| `GetTurnVM` | throws | failed | Never call |
| `GetUnitParameterById` with out-params | crashed ffr-bestiary (freed memory) | failed | Do not call from Lua |
| `GetLimitBurstPointOneGauge`, `GetLimitBurstPointMaxGaugeNum` | nothing | failed | v0.1.34 |

## Data tables (from FFR-Vision-Studio `docs/01-game-anatomy.md`)

| Table | Row struct | What we need from it |
| --- | --- | --- |
| `Skill/DT_SkillData` | `SKILL_DATA` (~1,000 skills) | element, damage type, calc type, power, stagger, target, cost, effect ids |
| `Skill/DT_SkillEffectData` | `SKILL_EFFECT_DATA` (~1,000 rows) | each effect: type, status, timing, turns, chance, params |
| `Skill/DT_PassiveSkillData` | passives (378) | what gear and Visions change |
| `Skill/DT_CommandSkillData` | command entries | the bar |
| `Skill/Other/DT_SkillDamageCalcData`, `DT_SkillRecoveryCalcData`, `DT_SkillTargetData`, `DT_SkillAttributeDetailData` | formulas, targets | damage and heal model |
| `Unit/DT_UnitParameter` | every unit and monster | element resistances (weak / resist / immune / absorb), status resistances, stats, max break point |
| `Difficulty/DT_GameDifficultyParam` | HP rate per difficulty | Expert is HP x1.6 (ffr-bestiary) |
| `Item/...` | items | heal amounts, targets, cures |
| `Unit/DT_UnitBattleCmd` | battle commands | |

Row keys are Japanese names; display names come from string tables
(`ST_SkillName`, `ST_UnitName`) and `Game.locres`.

## Effect types the party can use

Counted from the offline dump on 2026-11-03. A skill is in the party set
when its command list is 1, 6, 7, or 10 (the skill, summon, item, and
limit commands), or its owner is one playable unit, or its kind is
FinishBlow. That is 531 skills. Command 912 is 535 skills and is not in
the set: the boss wind-up and the 20-hit attack from the probe log sit
there. Another 101 skills have no command and owner All. The level tables
and the vision item table are not in this dump, so a skill granted only
there would be in that 101 and is not counted. Two effect types show up
only in that 101: `StealStatus` (4 skills) and `BackSummonUnit` (2).

Every skill row has eight effect slots. A slot of -1 is empty. The counts
below are distinct skills with at least one real slot of that type. The
skill row's own `skillEffectType` is separate: 396 of the 531 are
`DamageAndRecovery` and 135 are `None`. That is the direct hit or heal.
The bundle is the rider.

Names are the table's, including `Deffence` and `Regene`.

| Effect type | Party skills | Of which, item skills |
| --- | --- | --- |
| `MulBaseSkillByLevel` | 44 | 0 |
| `ParameterVariation` | 28 | 5 |
| `AutomaticSkill` | 24 | 6 |
| `CureStatusCondition` | 20 | 8 |
| `DamageMultiplier` | 16 | 0 |
| `Deffence` | 15 | 0 |
| `ParameterContinuousVariation` | 14 | 0 |
| `Revival` | 14 | 2 |
| `RemoveEffect` | 10 | 0 |
| `InstantDeath` | 10 | 0 |
| `SummonUnit` | 10 | 0 |
| `AccuracyVariation` | 8 | 2 |
| `DamageLimitBreak` | 8 | 0 |
| `AddSideJob` | 8 | 0 |
| `BreakDamageVariation` | 7 | 0 |
| `DamageAbsorb` | 6 | 0 |
| `Steal` | 4 | 0 |
| `SkillUnavailable` | 4 | 2 |

Fifty-two more types appear on three party skills or fewer. The ones on
two or three are `CostVariation` (3), `ImpossibleSelect`, `Cover`,
`CritOrMiss`, `BreakDefence`, `Escape`, `OverClock`,
`CriticalRateVariation`, `AddGoodLuck`, and `Berserk` (2 each). `Reflect`
is on one party skill. `RepeatAction` and `AddActionNum` are not in this
set (`AddActionNum` is on the enemy command, 4 skills).

The 51 items: 7 have no skill id. The other 44, plus 21 throw skills, are
already inside the 531. Their riders are the item column above, and
`Escape` on one more. Statuses on those item skills, two skills each:
Poison, Blind, Silence, Confusion, Paralyzation, Sleep. Regen is on one.

Statuses on the 531, from the effect row, three or more skills: Poison 9,
Paralyzation 6, MindUp 6, Sleep 6, Blind 6, DeffenceUp 5, Confusion 5,
Regene 4, Silence 4, Haste 3, Slow 3, MindDown 3, IntelligenceDown 3,
AttackDown 3. The skill row's own status is Gravide on 3 skills and empty
on the rest. Forty-one other statuses appear on one or two party skills.

**Addition (Claude, after review).** The 101 no-command skills are not all
out of reach. `DT_VisionAwakeningMasteryData` and
`DT_VisionSynchroMasteryData` (now dumped) grant actives by id
(`eVisionMasteryParameterType::ActiveSkill`, 259 ids) and passives
(`PassiveSkill`, 218 ids). 52 of the 101 are Vision-granted actives, so the
party set is **583**. With them: `DamageMultiplier` 26 (from 16),
`AutomaticSkill` 27, `ParameterVariation` 30, `CureStatusCondition` 21,
`BreakDamageVariation` 10, `DmgMulConsecutiveUse` 5, `StealStatus` 4,
`BreakDefence` 4, `AddExPhase` 3, `HateTarget` 3, `Cover` 3,
`AddRandExPhase` 2, `AddEffect` 2, `WaitTimeOffset` 2.

**Multi-action is passive.** `RepeatAction` (2), `AddActionNum` (4), and
`AddActOnSkill` (1) sit on `DT_PassiveSkillData` effect bundles, not on
active skills. Dualcast-type abilities change how a turn runs while
equipped; they are not commands the planner chooses. R4 is about reading
the second decide, not about choosing a skill. The most common passive
effects: `ParameterVariation` 41, `DamageMultiplier` 34,
`BreakDamageVariation` 30, `AddElementResistance` 24, `Counter` 23.

## Status ids (`eUnitStatusCondition`)

```
 1 Poison        2 Blind          3 Sleep          4 Silence        5 Paralysis
 6 Confusion     7 Stone          8 Charm          9 Stop          10 Berserk
11 Doom         12 Slow          13 InstantDeath  14 Gravity       15 AttackDown
16 DefenceDown  17 MagicDown     18 MindDown      19 BreakDmgDown  20 BreakDmgTakenUp
21 OverHeat     22 MoonSlayer    23 CrashBlade    24 AttackUp      25 DefenceUp
26 MagicUp      27 MindUp        28 BreakDmgUp    29 BreakDmgTakenDown
30 Regen        31 Reraise       32 Reflect       33 Haste         34 Cover
35 CoverAll     36 Defend        37 Boost         38 GoodLuck      39 VeilDefenceUp
40 DivineRadiance 41 HoningSense 42 LightVeil     43 SuperiorGuard 44 Decoy
45 BadstatusGuard 46 OverClock   47 OverClockZero 48 Camouflage    49 Taunt
50 DemonForm    51 AwakeningPower 52 GrandMagic   53 MindFocus     54 ParadiseLost
55 DualityNight 56 VitalPointAtk 57 RoyalGuard    58 GreatWall     59 MagicBarrier
60 HateTarget   61-68 Invalid<Element> (Fire Ice Wind Earth Thunder Water Light Dark)
69 Heat         70 Meteor(doom)  71-74 Enhance<Element> (Fire Ice Wind Thunder)
75 Masamune     76 Swift         77 SageEye       78 Fury          79-86 Formations/Tactics
88 Jump         89 Break
```

Each status row also says: bad status, debuff, its opposite
(`negateStatusCondition`: Slow/Haste, AttackDown/AttackUp, and so on), whether
Esuna, Dispel, or items clear it, whether it stacks, whether it overwrites,
whether it takes control (`isControlDisabled`) or the action
(`isActionDisabled`). Those flags are the cause-and-effect rules for statuses;
they come from the table, not from a wiki.

## Effect types (`eSkillEffectType`, 194)

The ones the planner must understand. The rest are logged as unknown and the
skill is scored by its damage and heal rows only.

| Code | Type | Why it matters |
| --- | --- | --- |
| 1 | DamageAndRecovery | damage or heal |
| 2, 3, 4 | ParameterVariation (and continuous, increase) | MP restore, poison, regen |
| 11 | TimelineChange | moves a unit on the Timeline (Haste-like, delay) |
| 12, 13 | RepeatAction, MimicRepeatAction | Dualcast, Double Action, mimic |
| 17, 18, 66 | AddElement, AddElementResistance, AddElementWhenNoneElement | imbues and barriers change what a weakness is |
| 19, 20 | CureStatusCondition, Revival | cures and raises |
| 26, 27 | Deffence, BreakDefence | Defend, stagger defense |
| 29 | Analyze | Libra |
| 34, 51, 62 | Reflect, ReflectDoublePayback, ReflectPenetration | Reflect and the skills that pass it |
| 36, 152 | DamageAbsorb, AbsorbsMagic | absorbs |
| 41, 99, 137 | Cover, HateTarget, Decoy | draws |
| 45 | ImpossibleLimitBurst | |
| 89 | ForcedWeakness | makes a weakness |
| 91, 92, 123, 159 | Break, BreakDamageVariation, AddBaseBreakDmg, MulBaseBreakBySkill | stagger math |
| 103, 104, 153 | AddExPhase, AddRandExPhase, ImpossibleAddExPhase | bonus phase |
| 108, 129 | AddActionNum, AddActOnSkill | extra actions (Arms Akimbo) |
| 116 | WaitTimeOffset | turn order |
| 132 | RemoveEffect | Dispel |

## Turn timing (`eSkillTiming`)

Effects run at fixed points: `BeginTurn 7`, `EndTurn 8`, `ActionBegin 2`,
`ActionEnd 4`, `Break 29`, `AllBreak 30`, `AddExPhase 12`, `Revival 51`,
`Dead 52`, `DamageCalculationOnBreak 48`, and more. A status's turns count
down on these (FFR-Vision-Studio measured a five-turn effect leaving at
shared turn 6).

## Mechanics from public guides (use only until the tables confirm them)

- A weakness hit deals 1.5x damage and 3x stagger (vorxu, ffresonance.wiki).
  Resisted elements deal half (Fextralife).
- Staggering an enemy before its turn cancels its devastating attack.
- Whoever staggers an enemy gets a bonus action at the end of the round. A
  sweeping stagger gives the whole party one.
- Reflect: "Enable an ally to reflect back black or white magic cast at them.
  Certain magic spells cannot be reflected back." Carbuncle's Ruby Light puts
  Reflect on all allies. Not stated: whether heals bounce. The effect rows
  answer it (`ReflectPenetration`).
- Dualcast: two black or white magic spells in a turn. Double Action: two
  attack skills, no magic. Arms Akimbo: two actions, 40 MP.
- Buffs: different ones stack, the same one does not; a buff and its opposite
  cancel.
- Sleep and Confusion end when the unit takes a physical hit.
- Bosses are immune to Charm, Confuse, Gravity, Instant Death, Petrify, Poison
  (by Fextralife's counts; the unit table is the real answer).

**Licensing.** ffresonance.wiki's footer forbids reproduction and AI training
use without permission; vorxu.com is all rights reserved. Facts may be
checked against them, but their text and compiled tables must not be copied
into this repo. v0.1.x's books should be checked against this too. The game's
own tables, read from the player's install, are the clean source.
