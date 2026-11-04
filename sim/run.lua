-- FFR:AutoBattle sim runner.
--
--   lua5.4 sim/run.lua [sessions] [seed] [--only kind] [--hard 1.0] [--keep loss,timeout] [--easy]
--                      [--scripts DIR] [--echo]
--
-- Loads the real Scripts/*.lua into the sim, plays random parties against
-- random fights, and checks the design doc's rules. A session is one game
-- launch: one load of main.lua and one to three fights in a row, with HP,
-- MP, and falls carried between them. Each session is also played by the
-- doc's baseline, attack with the strongest payable skill, on the same seed.
--
-- Output goes to sim/out: report.txt, and one file per fight that broke a
-- rule, with the sim's events and the planner's own log lines.

local here = (arg and arg[0] or "sim/run.lua"):match("^(.*)/[^/]+$") or "sim"
local root = here .. "/.."
package.path = here .. "/?.lua;" .. package.path
local realPrint = print
local Sim = require("sim")
local ATTR, EFF, TGT, REL, ST = Sim.ATTR, Sim.EFF, Sim.TGT, Sim.REL, Sim.ST

local sessions = tonumber(arg[1]) or 200
local seed0 = tonumber(arg[2]) or 1
local only = nil
-- --hard 1.0 is the default difficulty. Higher hits harder and lasts longer.
HARD = 1.0
HIT = 1.0
KEEP = {}
EASY = false
for i = 1, #arg do
    if arg[i] == "--echo" then Sim.echo = true end
    if arg[i] == "--only" then only = arg[i + 1] end
    if arg[i] == "--hard" then HARD = tonumber(arg[i + 1]) or 1.0 end
    if arg[i] == "--hit" then HIT = tonumber(arg[i + 1]) or 1.0 end
    -- --easy plays Take it Easy: only the free basic Attack may go out.
    if arg[i] == "--easy" then EASY = true end
    -- --keep loss,timeout also writes those fights to sim/out/kept.
    if arg[i] == "--keep" then for w in (arg[i + 1] or ""):gmatch("[^,]+") do KEEP[w] = true end end
end

local OUT = here .. "/out"
local WORK = OUT .. "/work"
os.execute(string.format('mkdir -p "%s/Scripts" "%s/fails" "%s/kept"', WORK, OUT, OUT))
os.execute(string.format('rm -f "%s"/fails/*.txt "%s"/kept/*.txt "%s"/battle_log.txt "%s"/state.txt', OUT, OUT, WORK, WORK))
-- --scripts DIR plays another copy of the scripts, for a test of the sim itself.
local SRC = root .. "/Scripts"
for i = 1, #arg do if arg[i] == "--scripts" then SRC = arg[i + 1] end end
os.execute(string.format('cp "%s"/*.lua "%s/Scripts/"', SRC, WORK))

-- The same books the planner reads.
local Known = dofile(root .. "/Scripts/known.lua")
local Catalog = dofile(root .. "/Scripts/catalog.lua")
local Mobs = dofile(root .. "/Scripts/mobs.lua")
local function fact(name)
    local k = name:lower()
    return (Known.skills and Known.skills[k]) or (Catalog.skills and Catalog.skills[k]) or {}
end

--------------------------------------------------------------------------------
-- Skill rows. Cost, power, and target are invented. Element and stagger come
-- from the books, so the sim and the planner agree on what a weakness is.
--------------------------------------------------------------------------------

local function dmg(name, attr, cost, power, stagger, target, extra)
    local f = fact(name)
    local spec = {
        name = name, attr = attr, effect = EFF.DAMAGE, cost = cost, power = power,
        stagger = f.stagger or stagger, target = target or TGT.SINGLE, rel = REL.ENEMY,
        element = f.element, magic = (attr == ATTR.MAGIC) or f.magic,
    }
    for k, v in pairs(extra or {}) do spec[k] = v end
    return Sim.addSkill(spec)
end
local function support(name, cost, target, status, extra)
    local spec = { name = name, attr = ATTR.MAGIC, effect = EFF.PARAM, cost = cost, target = target,
        rel = REL.FRIEND, status = status }
    for k, v in pairs(extra or {}) do spec[k] = v end
    return Sim.addSkill(spec)
end
local function debuff(name, cost, status, tag)
    return Sim.addSkill({ name = name, attr = ATTR.MAGIC, effect = EFF.PARAM, cost = cost,
        target = TGT.SINGLE, rel = REL.ENEMY, status = status, debuff = tag })
end

dmg("Attack", ATTR.FIGHT, 0, 100, 25)
dmg("Tackle", ATTR.ABILITY, 5, 120, 35)
dmg("Bladeblitz", ATTR.ABILITY, 8, 90, 20, TGT.GROUP)
dmg("Dawn Frost", ATTR.ABILITY, 5, 140, 30)
dmg("Ice Splitter", ATTR.ABILITY, 8, 160, 25)
dmg("Flame Sword", ATTR.ABILITY, 6, 150, 33)
dmg("Tranquility in Tumult", ATTR.ABILITY, 19, 220, 40)
dmg("Soul of Valiance", ATTR.ABILITY, 45, 300, 45)
dmg("Vanguard Glaive", ATTR.ABILITY, 7, 170, 25)
for _, el in ipairs({ { "Fire", "Fira" }, { "Blizzard", "Blizzara" }, { "Thunder", "Thundara" },
    { "Water", "Watera" }, { "Aero", "Aerora" }, { "Stone", "Stonera" } }) do
    dmg(el[1], ATTR.MAGIC, 5, 120, 17)
    dmg(el[2], ATTR.MAGIC, 15, 200, 25)
end
-- From the battle log of 2026-11-02 (the replay fight). Tranquility is a
-- katana hit in the game: physical, whatever the books say.
dmg("Tranquility", ATTR.ABILITY, 13, 200, 40, nil, { magic = false, phys = true })
dmg("Shining Arrow", ATTR.ABILITY, 6, 140, 25)
dmg("Banish", ATTR.MAGIC, 6, 130, 17)
dmg("Banishra", ATTR.MAGIC, 16, 210, 25)

-- Cure, Cura and Curaga cost and power as in the game's rows: one target.
Sim.addSkill({ name = "Cure", attr = ATTR.MAGIC, effect = EFF.DAMAGE, cost = 6, power = 200, rel = REL.FRIEND, heal = true })
Sim.addSkill({ name = "Cura", attr = ATTR.MAGIC, effect = EFF.DAMAGE, cost = 18, power = 500, rel = REL.FRIEND, heal = true })
Sim.addSkill({ name = "Curaga", attr = ATTR.MAGIC, effect = EFF.DAMAGE, cost = 50, power = 1500, rel = REL.FRIEND, heal = true })
-- Invented party heals. The game's party heal rows can show no magnification. The sim heals by healPower.
Sim.addSkill({ name = "Mass Cure", attr = ATTR.MAGIC, effect = EFF.DAMAGE, cost = 14, power = 0, healPower = 240, rel = REL.FRIEND, heal = true, target = TGT.ALL })
Sim.addSkill({ name = "Mass Cura", attr = ATTR.MAGIC, effect = EFF.DAMAGE, cost = 30, power = 0, healPower = 420, rel = REL.FRIEND, heal = true, target = TGT.ALL })
Sim.addSkill({ name = "Esuna", attr = ATTR.MAGIC, effect = EFF.CURE, cost = 8, rel = REL.FRIEND })
Sim.addSkill({ name = "Raise", attr = ATTR.MAGIC, effect = EFF.REVIVE, cost = 20, rel = REL.FRIEND, revive = true })
Sim.addSkill({ name = "Libra", attr = ATTR.MAGIC, effect = EFF.ANALYZE, cost = 2 })
Sim.addSkill({ name = "Defend", attr = ATTR.FIGHT, effect = EFF.DEFEND, cost = 0, target = TGT.SELF, rel = REL.FRIEND })
Sim.addSkill({ name = "Escape", attr = 16, effect = 0, cost = 0, target = TGT.SELF, rel = REL.FRIEND })

support("Protect", 8, TGT.SINGLE, ST.PROTECT)
support("Protectga", 18, TGT.ALL, ST.PROTECT)
support("Shell", 8, TGT.SINGLE, ST.SHELL)
support("Shellga", 18, TGT.ALL, ST.SHELL)
support("Haste", 10, TGT.SINGLE, ST.HASTE, { turns = 5 })
support("Hastega", 26, TGT.ALL, ST.HASTE, { turns = 5 })
support("Bravery", 8, TGT.SINGLE, 31)
support("Faith", 8, TGT.SINGLE, 32)
support("Focus Magic", 6, TGT.SELF, 33)
support("Hone Senses", 5, TGT.SELF, 41)
support("Placidity", 6, TGT.SELF, 76)
support("Formation: Assail", 6, TGT.ALL, 80)
support("Formation: Charge", 6, TGT.ALL, 81)
support("Formation: Bulwark", 8, TGT.ALL, 82)
support("Tactic: Fluid Warfare", 30, TGT.SELF, 84)
-- The game shows no status for Provoke or Cover. The sim does the same.
support("Provoke", 10, TGT.SELF, 0, { provoke = true })
Sim.addSkill({ name = "Cover", attr = ATTR.ABILITY, effect = EFF.COVER, cost = 5, target = TGT.SINGLE, rel = REL.FRIEND })
Sim.addSkill({ name = "Multi-Cover", attr = ATTR.ABILITY, effect = EFF.COVER, cost = 10, target = TGT.ALL, rel = REL.FRIEND })
-- A stance: up until its off skill goes out. It lifts the caster's hits and
-- blocks white-magic heals on the caster. The sim marks it status 97.
support("Witching Hour", 8, TGT.SELF, 97, { attr = ATTR.ABILITY, turns = 999, stance = true })
Sim.addSkill({ name = "End Witching Hour", attr = ATTR.ABILITY, effect = EFF.PARAM, cost = 0,
    target = TGT.SELF, rel = REL.FRIEND, endStance = 97 })
Sim.addSkill({ name = "Stratagem", attr = ATTR.ABILITY, effect = EFF.PARAM, cost = 8, rel = REL.ENEMY, status = 90 })
debuff("Deprotect", 8, 61, "protect")
debuff("Deshell", 8, 62, "shell")
debuff("Debrave", 8, 63, "attack")
debuff("Blind", 6, ST.BLIND)
debuff("Silence", 6, ST.SILENCE)
debuff("Slow", 8, ST.SLOW)

for _, e in ipairs({ { "Siren", "wind" }, { "Ramuh", "thunder" }, { "Shiva", "ice" }, { "Ifrit", "fire" } }) do
    Sim.addSkill({ name = e[1], attr = ATTR.SUMMON, effect = EFF.DAMAGE, cost = 50, power = 160, stagger = 20,
        element = e[2], magic = true, target = TGT.ALL, esper = e[1], summonTurns = 3 })
end

Sim.addSkill({ name = "Null Moon", attr = ATTR.LB, effect = EFF.DAMAGE, power = 180, stagger = 27, lbGauges = 1 })
Sim.addSkill({ name = "Infinity Drive", attr = ATTR.LB, effect = EFF.DAMAGE, power = 450, stagger = 25, element = "fire", lbGauges = 1 })
Sim.addSkill({ name = "Transient Rite", attr = ATTR.LB, effect = EFF.DAMAGE, power = 500, stagger = 35, element = "ice", lbGauges = 2, target = TGT.ALL })
Sim.addSkill({ name = "Radiant Restoration", attr = ATTR.LB, effect = EFF.DAMAGE, power = 300, rel = REL.FRIEND, heal = true,
    target = TGT.ALL, lbGauges = 2, raiseAll = true })
Sim.addSkill({ name = "Crimson Onslaught", attr = ATTR.LB, effect = EFF.DAMAGE, power = 520, stagger = 35, element = "fire", lbGauges = 2, target = TGT.ALL })
Sim.addSkill({ name = "Holy Ray", attr = ATTR.LB, effect = EFF.DAMAGE, power = 300, stagger = 25, element = "light", magic = true, lbGauges = 1, target = TGT.ALL })
-- Support Limits, with invented statuses: 85 fills the gauge as the ally
-- acts, 86 doubles the next hit, 87 nullifies the next hit taken.
Sim.addSkill({ name = "Formation: Steeled Advance", attr = ATTR.LB, effect = EFF.PARAM, rel = REL.FRIEND, target = TGT.ALL, status = 85, turns = 3, lbGauges = 1 })
Sim.addSkill({ name = "Mirroring Prism", attr = ATTR.LB, effect = EFF.PARAM, rel = REL.FRIEND, target = TGT.ALL, status = 86, turns = 3, lbGauges = 2 })
Sim.addSkill({ name = "Eternal Veil", attr = ATTR.LB, effect = EFF.PARAM, rel = REL.FRIEND, target = TGT.ALL, status = 87, turns = 4, lbGauges = 1 })
Sim.addSkill({ name = "Crystal Braver", attr = ATTR.FINISH, effect = EFF.DAMAGE, power = 600, stagger = 0, target = TGT.ALL })
Sim.addSkill({ name = "Healing Wind", attr = ATTR.FINISH, effect = EFF.DAMAGE, power = 100, stagger = 0, rel = REL.FRIEND, heal = true, target = TGT.ALL })

local function item(name, spec, rare) return Sim.addItem(name, spec, rare) end
item("Potion", { effect = EFF.DAMAGE, rel = REL.FRIEND, heal = true, calc = 3, power = 300 })
item("Hi-Potion", { effect = EFF.DAMAGE, rel = REL.FRIEND, heal = true, calc = 3, power = 700 })
item("Mist Potion", { effect = EFF.DAMAGE, rel = REL.FRIEND, heal = true, calc = 3, power = 200, target = TGT.ALL })
item("Mist Hi-Potion", { effect = EFF.DAMAGE, rel = REL.FRIEND, heal = true, calc = 3, power = 500, target = TGT.ALL })
item("Ether", { effect = EFF.DAMAGE, rel = REL.FRIEND, mp = true, calc = 3, power = 60 })
item("Phoenix Down", { effect = EFF.REVIVE, rel = REL.FRIEND, revive = true })
item("Antidote", { effect = EFF.CURE, rel = REL.FRIEND, status = ST.POISON })
item("Eye Drops", { effect = EFF.CURE, rel = REL.FRIEND, status = ST.BLIND })
item("Echo Herb", { effect = EFF.CURE, rel = REL.FRIEND, status = ST.SILENCE })
item("Unicorn Horn", { effect = EFF.CURE, rel = REL.FRIEND, status = ST.PARALYSIS })
item("Gold Needle", { effect = EFF.CURE, rel = REL.FRIEND, status = ST.PETRIFY })
item("Herb of Awakening", { effect = EFF.CURE, rel = REL.FRIEND, status = ST.SLEEP })
item("Smelling Salts", { effect = EFF.CURE, rel = REL.FRIEND, status = ST.CONFUSE })
item("Remedy", { effect = EFF.CURE, rel = REL.FRIEND, remedy = true })
-- Premium rows are not flagged rare. The planner has to know them by name.
item("Elixir", { effect = EFF.DAMAGE, rel = REL.FRIEND, heal = true, mp = true, full = true, calc = 3, power = 9999 })
item("Megalixir", { effect = EFF.DAMAGE, rel = REL.FRIEND, heal = true, mp = true, full = true, calc = 3, power = 9999 })
item("X-Potion", { effect = EFF.DAMAGE, rel = REL.FRIEND, heal = true, full = true, calc = 3, power = 9999 })
item("Turbo Ether", { effect = EFF.DAMAGE, rel = REL.FRIEND, mp = true, full = true, calc = 3, power = 999 })
item("Phoenix Pinion", { effect = EFF.REVIVE, rel = REL.FRIEND, revive = true })
-- Thrown attack items. Not flagged rare, so the planner knows them by name.
for _, e in ipairs({ { "Flame", "fire" }, { "Ice", "ice" }, { "Wind", "wind" }, { "Earth", "earth" }, { "Lightning", "thunder" }, { "Water", "water" } }) do
    item(e[1] .. " Scroll I", { effect = EFF.DAMAGE, rel = REL.ENEMY, element = e[2], magic = true, calc = 3, power = 180, stagger = 12 })
end
item("Knife of Blind", { effect = EFF.DAMAGE, rel = REL.ENEMY, phys = true, calc = 3, power = 120, stagger = 8, status = ST.BLIND })
item("Fuma Shuriken", { effect = EFF.DAMAGE, rel = REL.ENEMY, phys = true, calc = 3, power = 260, stagger = 10 })

--------------------------------------------------------------------------------
-- Visions: a bar of skills. The planner is never told which one it is.
--------------------------------------------------------------------------------

local VISIONS = {
    { key = "white", healer = true, hp = { 600, 760 }, mp = { 220, 290 }, atk = 55, mag = 95,
        skills = { "Attack", "Cure", "Cura", "Curaga", "Mass Cure", "Esuna", "Raise", "Shell", "Libra", "Banish", "Hastega" } },
    { key = "paladin", healer = true, hp = { 820, 960 }, mp = { 150, 200 }, atk = 85, mag = 70,
        skills = { "Attack", "Cure", "Cura", "Mass Cure", "Protect", "Protectga", "Multi-Cover", "Provoke", "Soul of Valiance", "Vanguard Glaive", "Defend" } },
    { key = "knight", hp = { 860, 980 }, mp = { 110, 160 }, atk = 95, mag = 40,
        skills = { "Attack", "Tackle", "Provoke", "Cover", "Protect", "Flame Sword", "Defend" } },
    { key = "black", hp = { 560, 700 }, mp = { 200, 270 }, atk = 50, mag = 110,
        skills = { "Attack", "Fire", "Fira", "Blizzard", "Blizzara", "Thunder", "Thundara", "Aero", "Focus Magic" } },
    { key = "sword", hp = { 760, 900 }, mp = { 180, 230 }, atk = 105, mag = 70,
        skills = { "Attack", "Bladeblitz", "Dawn Frost", "Ice Splitter", "Hone Senses", "Placidity", "Tranquility in Tumult", "Haste" } },
    { key = "tactician", hp = { 640, 780 }, mp = { 170, 210 }, atk = 60, mag = 90,
        skills = { "Attack", "Formation: Assail", "Formation: Charge", "Formation: Bulwark", "Tactic: Fluid Warfare",
            "Stratagem", "Water", "Watera", "Cure", "Libra", "Bravery", "Faith", "Slow" } },
    { key = "red", hp = { 650, 780 }, mp = { 180, 230 }, atk = 75, mag = 85,
        skills = { "Attack", "Cure", "Fire", "Blizzard", "Thunder", "Stone", "Deprotect", "Deshell", "Debrave", "Silence", "Blind", "Esuna", "Haste", "Slow" } },
    { key = "summoner", hp = { 580, 700 }, mp = { 220, 280 }, atk = 50, mag = 100,
        skills = { "Attack", "Siren", "Ramuh", "Shiva", "Cure", "Aero", "Stone", "Stonera" } },
    { key = "witch", hp = { 600, 740 }, mp = { 200, 260 }, atk = 60, mag = 105,
        skills = { "Attack", "Fire", "Fira", "Thunder", "Aero", "Witching Hour", "End Witching Hour", "Cure" } },
    { key = "brawler", hp = { 900, 1000 }, mp = { 30, 50 }, atk = 115, mag = 30,
        skills = { "Attack", "Tackle", "Bladeblitz" } },
}
-- The replay party: the last fight in the battle log of 2026-11-02, a boss
-- Shoggoth that wiped this party. Skills and MP are read from the log; HP,
-- attack, and magic are guesses.
local REPLAY_PARTY = {
    { name = "Nichol", vision = "tactician", maxHp = 700, maxMp = 52, atk = 60, mag = 90, spd = 11,
        skills = { "Escape", "Attack", "Slow", "Watera", "Formation: Assail", "Cure", "Defend" } },
    { name = "Lasswell", vision = "sword", maxHp = 820, maxMp = 52, atk = 105, mag = 70, spd = 13,
        skills = { "Escape", "Attack", "Tranquility", "Placidity", "Blizzard", "Dawn Frost", "Defend" } },
    { name = "Fina", vision = "white", healer = true, maxHp = 680, maxMp = 220, atk = 55, mag = 95, spd = 10,
        skills = { "Escape", "Attack", "Siren", "Esuna", "Shining Arrow", "Cure", "Raise" } },
    { name = "Rain", vision = "red", maxHp = 780, maxMp = 55, atk = 80, mag = 80, spd = 12,
        skills = { "Escape", "Attack", "Fire", "Fira", "Provoke", "Cure", "Defend", "Crystal Braver" } },
}
-- The tide party, from the kit bars and casts in the battle log of
-- 2026-11-03. MP, Limits, and the opening gauges are read from the log; HP,
-- attack, and magic are guesses.
local TIDE_PARTY = {
    { name = "Nichol", vision = "tactician", maxHp = 700, maxMp = 213, mp = 177, atk = 60, mag = 90, spd = 11,
        skills = { "Escape", "Attack", "Formation: Assail", "Formation: Charge", "Formation: Bulwark", "Stratagem",
            "Tactic: Fluid Warfare", "Watera", "Cure", "Defend", "Formation: Steeled Advance" }, lbMax = 100 },
    { name = "Rain", vision = "knight", maxHp = 880, maxMp = 191, mp = 82, atk = 95, mag = 60, spd = 12,
        skills = { "Escape", "Attack", "Provoke", "Flame Sword", "Fire", "Protect", "Debrave", "Soul of Valiance", "Defend",
            "Infinity Drive", "Crimson Onslaught" }, lb = 14 },
    { name = "Lasswell", vision = "sword", maxHp = 760, maxMp = 267, mp = 235, atk = 105, mag = 70, spd = 13,
        skills = { "Escape", "Attack", "Haste", "Hastega", "Hone Senses", "Placidity", "Tranquility in Tumult",
            "Thundara", "Fira", "Fire", "Null Moon", "Transient Rite" }, lb = 24 },
    { name = "Fina", vision = "white", healer = true, maxHp = 680, maxMp = 281, mp = 271, atk = 55, mag = 95, spd = 10,
        skills = { "Escape", "Attack", "Cure", "Raise", "Esuna", "Fire", "Siren", "Ramuh", "Holy Ray", "Radiant Restoration" }, lb = 11 },
}
local function tideBag()
    return {
        ["Potion"] = 9, ["Ether"] = 17, ["Phoenix Down"] = 20, ["Antidote"] = 5, ["Eye Drops"] = 5,
        ["Unicorn Horn"] = 5, ["Gold Needle"] = 5, ["Mist Potion"] = 9, ["Mist Hi-Potion"] = 1,
        ["Flame Scroll I"] = 5, ["Ice Scroll I"] = 2, ["Wind Scroll I"] = 4, ["Earth Scroll I"] = 2,
        ["Lightning Scroll I"] = 3, ["Water Scroll I"] = 5,
    }
end

local function replayBag()
    return {
        ["Potion"] = 10, ["Mist Potion"] = 10, ["Ether"] = 12, ["Phoenix Down"] = 6,
        ["Antidote"] = 2, ["Eye Drops"] = 2, ["Echo Herb"] = 2, ["Remedy"] = 1,
        ["Water Scroll I"] = 4, ["Wind Scroll I"] = 2,
    }
end

-- Each character carries a level 1 Limit and, from level 25, a level 2 one.
local LIMITS = {
    { "Null Moon", "Transient Rite" }, { "Infinity Drive", "Crimson Onslaught" },
    { "Holy Ray", "Radiant Restoration" }, { "Formation: Steeled Advance", "Mirroring Prism" },
    { "Eternal Veil" }, { "Null Moon" }, { "Infinity Drive" },
}
local NAMES = { "Rain", "Fina", "Lasswell", "Nichol", "Aria", "Bram", "Cora", "Dax" }

local function pick(t) return t[math.random(#t)] end
local function between(r) return math.random(r[1], r[2]) end

local function makeParty(size)
    local party, used = {}, {}
    for i = 1, size do
        local v = pick(VISIONS)
        local skills = { "Escape" }
        for _, s in ipairs(v.skills) do skills[#skills + 1] = s end
        if math.random() < 0.5 then
            for _, n in ipairs(pick(LIMITS)) do skills[#skills + 1] = n end
        end
        local finisher = math.random()
        if finisher < 0.3 then skills[#skills + 1] = "Crystal Braver"
        elseif finisher < 0.45 then skills[#skills + 1] = "Healing Wind" end
        local name
        repeat name = pick(NAMES) until not used[name]
        used[name] = true
        party[i] = {
            name = name, vision = v.key, healer = v.healer, maxHp = between(v.hp), maxMp = between(v.mp),
            atk = v.atk + math.random(-8, 8), mag = v.mag + math.random(-8, 8), spd = math.random(8, 16),
            skills = skills,
        }
    end
    return party
end

--------------------------------------------------------------------------------
-- Fights, from the enemy book.
--------------------------------------------------------------------------------

local CARDS = {}
for name, c in pairs(Mobs) do
    if type(c) == "table" and tonumber(c.gauge) then CARDS[#CARDS + 1] = { name = name, card = c } end
end
table.sort(CARDS, function(a, b) return a.name < b.name end)
local function cards(pred)
    local out = {}
    for _, e in ipairs(CARDS) do if pred(e.card, e.name) then out[#out + 1] = e end end
    return out
end
local SOFT = cards(function(c) return c.soft and c.gauge <= 120 end)
local MID = cards(function(c) return c.gauge >= 150 and c.gauge <= 400 and not c.danger end)
local DANGER = cards(function(c) return c.danger and c.gauge >= 150 and c.gauge <= 700 end)
local BOSS = cards(function(c) return c.danger and c.gauge >= 600 and c.gauge <= 1500 end)
local COUNTER = cards(function(c) return c.counter and c.gauge <= 800 end)
local ABSORB = cards(function(c) return (c.absorb or c.no) and c.gauge <= 800 end)

local function foe(e, scale, boss, statusChance, statusList)
    local g = e.card.gauge
    -- The real gauge sits off the book's: Leviathan broke under its book 1000
    -- in one log and held past 1068 in another.
    local real = math.floor(tonumber(g) * (0.9 + math.random() * 0.35) + 0.5)
    local hp = (boss and (1100 + g * 7) or (300 + g * 6)) * scale * HARD
    return {
        name = (e.name:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end)), card = e.card, gauge = real,
        hp = math.floor(hp), atk = math.floor(((boss and 95 or 62) + g * 0.07) * (0.55 + 0.45 * scale) * HARD * HIT),
        spd = math.random(6, 14), statusChance = statusChance or 0, statusList = statusList,
    }
end

local KINDS = { "trash", "mixed", "equal", "danger", "boss", "status", "counter", "absorb", "pot", "entry", "nophys", "hidden", "locked", "adds" }

local function makeFight(kind, size)
    local scale = (size / 4) ^ 0.8
    local f = { kind = kind, foes = {}, boss = false, pot = false, focusHealer = math.random() < 0.3 }
    if kind == "trash" then
        local e = pick(SOFT)
        for _ = 1, math.random(2, 4) do f.foes[#f.foes + 1] = foe(math.random() < 0.6 and e or pick(SOFT), scale) end
    elseif kind == "mixed" then
        local big = pick(MID)
        f.foes[1] = foe(big, scale)
        for _ = 1, math.random(1, 2) do f.foes[#f.foes + 1] = foe(pick(SOFT), scale) end
    elseif kind == "equal" then
        local e = pick(MID)
        for _ = 1, math.random(2, 3) do f.foes[#f.foes + 1] = foe(e, scale) end
    elseif kind == "danger" then
        f.foes[1] = foe(pick(DANGER), scale)
        if math.random() < 0.6 then f.foes[2] = foe(pick(SOFT), scale) end
    elseif kind == "boss" then
        f.boss = true
        f.foes[1] = foe(pick(BOSS), scale, true)
        -- One body winds up, then hits the party on its next slot unless broken.
        f.foes[1].warn = true
        for _ = 1, math.random(0, 2) do f.foes[#f.foes + 1] = foe(pick(SOFT), scale) end
    elseif kind == "status" then
        local list = { ST.POISON, ST.BLIND, ST.SLEEP, ST.SILENCE, ST.PARALYSIS, ST.CONFUSE, ST.SLOW, ST.DOOM, ST.BERSERK }
        f.foes[1] = foe(pick(MID), scale, false, 0.35, list)
        for _ = 1, math.random(1, 2) do f.foes[#f.foes + 1] = foe(pick(SOFT), scale, false, 0.25, list) end
    elseif kind == "counter" then
        f.foes[1] = foe(pick(COUNTER), scale)
    elseif kind == "absorb" then
        f.foes[1] = foe(pick(ABSORB), scale)
        if math.random() < 0.5 then f.foes[2] = foe(pick(SOFT), scale) end
    elseif kind == "pot" then
        f.pot = true
        f.foes[1] = { name = "Pot", hp = math.floor(400 * scale), atk = 20, spd = 5, statusChance = 0 }
    elseif kind == "adds" then
        -- A boss with a dangerous attack that keeps calling one small add.
        -- The add comes back two rounds after it falls.
        f.boss = true
        f.foes[1] = foe(pick(DANGER), scale, true)
        f.foes[2] = foe(pick(SOFT), scale)
        f.foes[2].respawn = 2
    elseif kind == "tide" then
        -- The battle log of 2026-11-03: Leviathan and the Orbs of Light it
        -- keeps on the field, wipes on every try. The Orbs break and recover
        -- in the game log and never fall. A test of the rules, not a script.
        f.boss = true
        f.foes[1] = foe({ name = "leviathan", card = Mobs["leviathan"] }, 1, true)
        f.foes[1].hitKind = "magic"
        f.foes[2] = foe({ name = "orbs of light", card = Mobs["orbs of light"] }, 1)
        f.foes[2].called = true
    elseif kind == "replay" then
        -- The battle log's last fight: Shoggoth as a boss, alone.
        f.boss = true
        f.foes[1] = foe({ name = "shoggoth", card = Mobs["shoggoth"] }, 1, true)
    elseif kind == "nophys" then
        -- A book card that nulls physical hits and deals magic damage.
        local e = { name = "shoggoth", card = Mobs["shoggoth"] }
        f.boss = math.random() < 0.5
        f.foes[1] = foe(e, scale, f.boss)
        if math.random() < 0.5 then f.foes[2] = foe(pick(SOFT), scale) end
    elseif kind == "hidden" then
        -- An enemy that nulls a kind the book does not list. The planner has to learn it.
        local e = pick(math.random() < 0.5 and MID or DANGER)
        local x = foe(e, scale)
        x.hidden = (math.random() < 0.7) and "physical" or "magic"
        x.hitKind = (math.random() < 0.5) and "magic" or "physical"
        f.foes[1] = x
        if math.random() < 0.5 then f.foes[2] = foe(pick(SOFT), scale) end
    elseif kind == "locked" then
        -- A fight the game will not let the party flee, though the bar shows
        -- Escape. An evading enemy, so a party of physical hits stalls.
        f.noFlee = true
        f.foes[1] = foe({ name = "cactuar", card = Mobs["cactuar"] }, scale)
        if math.random() < 0.5 then f.foes[2] = foe(pick(SOFT), scale) end
    elseif kind == "entry" then
        f.foes[1] = foe(pick(MID), scale)
        f.foes[2] = foe(pick(SOFT), scale)
        f.entry = true
    end
    return f
end

local function bag()
    return {
        ["Potion"] = math.random(3, 10), ["Hi-Potion"] = math.random(0, 3), ["Mist Potion"] = math.random(0, 3),
        ["Mist Hi-Potion"] = math.random(0, 1), ["Ether"] = math.random(2, 8),
        ["Phoenix Down"] = math.random(2, 6), ["Antidote"] = 3, ["Eye Drops"] = 3, ["Echo Herb"] = 2,
        ["Unicorn Horn"] = 2, ["Gold Needle"] = 1, ["Herb of Awakening"] = 2, ["Smelling Salts"] = 1,
        ["Remedy"] = math.random(0, 2), ["Elixir"] = 2, ["Megalixir"] = 1, ["X-Potion"] = 1,
        ["Turbo Ether"] = 1, ["Phoenix Pinion"] = 1,
        ["Flame Scroll I"] = math.random(0, 2), ["Ice Scroll I"] = math.random(0, 2), ["Wind Scroll I"] = math.random(0, 2),
        ["Earth Scroll I"] = math.random(0, 2), ["Lightning Scroll I"] = math.random(0, 2), ["Water Scroll I"] = math.random(0, 2),
        ["Knife of Blind"] = math.random(0, 2), ["Fuma Shuriken"] = math.random(0, 1),
    }
end

--------------------------------------------------------------------------------
-- Rules read from the planner's own log lines
--------------------------------------------------------------------------------

local ERRORS = { "choice failed", "plan failed", "timer error", "kit fallback failed", "send failed",
    "could not build", "no command sent", "nothing legal", "player command was not recorded", "hook failed" }

-- The doc: a gauge is an add only when it is at or under 60% of the largest.
local function expectPlan(fight)
    local maxG, small = 0, false
    for _, f in ipairs(fight.foes) do
        local g = f.card and tonumber(f.card.gauge) or 100
        if g > maxG then maxG = g end
    end
    for _, f in ipairs(fight.foes) do
        local g = f.card and tonumber(f.card.gauge) or 100
        if g <= maxG * 0.6 then small = true end
    end
    return small and "adds" or "sync"
end

local function scanModLines(lines, fight, viol)
    local firstPlan, earlyHit = nil, false
    for _, s in ipairs(lines) do
        local body = s:gsub("^%[FFRAutoBattle%] ", "")
        -- A hit the game or the player made before the first plan changes the gauges.
        if (not firstPlan) and body:match("^player ") then earlyHit = true end
        for _, e in ipairs(ERRORS) do
            if body:find(e, 1, true) then viol[#viol + 1] = { kind = "planner error", text = body } end
        end
        if (not firstPlan) and body:match("^plan %a+/") then firstPlan = body:match("^plan (%a+)/") end
    end
    if firstPlan and (#fight.foes > 1) and (not earlyHit) then
        local want = expectPlan(fight)
        if firstPlan ~= want then
            viol[#viol + 1] = { kind = "plan mode", text = "opened with plan " .. firstPlan .. ", the gauges call for " .. want }
        end
    end
end

--------------------------------------------------------------------------------
-- Running
--------------------------------------------------------------------------------

local function copyParty(p)
    local out = {}
    for i, m in ipairs(p) do
        local c = {}
        for k, v in pairs(m) do c[k] = v end
        out[i] = c
    end
    return out
end

local function playSession(sid, withMod)
    math.randomseed(seed0 * 100003 + sid)
    local size = math.random(1, 4)
    local party = makeParty(size)
    local nFights = math.random(1, 3)
    if only == "replay" then
        size, party, nFights = #REPLAY_PARTY, copyParty(REPLAY_PARTY), 1
    end
    if only == "tide" then
        size, party, nFights = #TIDE_PARTY, copyParty(TIDE_PARTY), 1
    end
    local plan = {}
    for i = 1, nFights do
        local kind = only or pick(KINDS)
        plan[i] = makeFight(kind, size)
        plan[i].bag = (kind == "replay") and replayBag() or ((kind == "tide") and tideBag()) or bag()
    end
    Sim.install()
    if withMod then
        local f = io.open(WORK .. "/state.txt", "w")
        f:write("enabled=true\nattacks=" .. (EASY and "true" or "false") .. "\n")
        f:close()
        local ok, err = pcall(dofile, WORK .. "/Scripts/main.lua")
        if not ok then error("main.lua failed to load: " .. tostring(err)) end
    end
    local results = {}
    local members = copyParty(party)
    local sharedBag = plan[1].bag
    for i, fight in ipairs(plan) do
        math.randomseed(seed0 * 7919 + sid * 31 + i)
        if fight.entry then
            local m = members[math.random(#members)]
            if #members > 1 and math.random() < 0.5 then m.hp = 0 else m.statuses = { [pick({ ST.CONFUSE, ST.SLEEP, ST.SILENCE, ST.POISON })] = 3 } end
        end
        local B = Sim.newBattle({ party = members, foes = fight.foes, boss = fight.boss, pot = fight.pot,
            bag = (i == 1) and sharedBag or nil, focusHealer = fight.focusHealer, noFlee = fight.noFlee, easy = EASY and withMod,
            retry = fight.boss })
        if i > 1 then B.bag = results[i - 1].bag end
        local outcome = Sim.play(40, (not withMod) and Sim.baseline or nil)
        local viol = {}
        for _, v in ipairs(B.violations) do viol[#viol + 1] = v end
        if withMod then
            scanModLines(B.modLines, fight, viol)
            -- A retry after a wipe should clear the ledger and the setup.
            -- An enemy's own command recorded as the party's.
            for j = 1, #B.modLines do
                local who = B.modLines[j]:match("%] player (.-) p%d")
                if who then
                    for _, u in pairs(B.units) do
                        if u.side == "enemy" and u.name == who then
                            viol[#viol + 1] = { kind = "enemy recorded", text = B.modLines[j] }
                        end
                    end
                end
            end
            -- "party restored" with no wipe: the planner threw away its ledger,
            -- its buffs, and its setup in the middle of a fight.
            for j = 1, #B.modLines do
                if B.modLines[j]:find("party restored", 1, true) and ((not B.retryAt) or (j <= B.retryAt)) then
                    viol[#viol + 1] = { kind = "false retry", text = "the planner cleared its ledger with no wipe" }
                    break
                end
            end
            -- A wipe before the planner's first command in the fight left no
            -- ledger to clear, so only a fight it had already acted in counts.
            local before = false
            for j = 1, math.min(B.retryAt or 0, #B.modLines) do
                if B.modLines[j]:find(" p0 mp", 1, true) then before = true break end
            end
            if B.retryAt and before then
                local saw, acted = false, false
                for j = B.retryAt + 1, #B.modLines do
                    if B.modLines[j]:find("party restored", 1, true) then saw = true end
                    if B.modLines[j]:find(" p0 mp", 1, true) then acted = true end
                end
                if acted and not saw then viol[#viol + 1] = { kind = "missed retry", text = "the party came back after a wipe and the ledger was kept" } end
            end
            -- The planner's battle summary should not list more falls than happened.
            for _, line in ipairs(B.modLines) do
                local fellPart = line:match("battle %d+ done: .*%.%s([^%.]*)%.$")
                if fellPart and fellPart ~= "no one fell" then
                    local n = 1
                    for _ in fellPart:gmatch(", ") do n = n + 1 end
                    if n > B.stats.falls then
                        viol[#viol + 1] = { kind = "false fall", text = string.format("summary lists %d falls (%s), %d happened", n, fellPart, B.stats.falls) }
                    end
                end
            end
        end
        -- The biggest enemy's HP share left at the end, for fitting the sim
        -- to a real fight (a loss with the boss at 40% reads 0.40).
        local bossLeft = nil
        do
            local big = nil
            for _, u in pairs(B.units) do
                if u.side == "enemy" and (u.maxHp or 0) > 0 and ((not big) or u.maxHp > big.maxHp) then big = u end
            end
            if big then bossLeft = math.max(0, big.hp or 0) / big.maxHp end
        end
        results[i] = {
            kind = fight.kind, size = size, outcome = outcome, rounds = B.round, stats = B.stats, bossLeft = bossLeft,
            violations = viol, events = B.events, modLines = B.modLines, bag = B.bag, party = members,
            foes = fight.foes, boss = fight.boss,
        }
        local after = Sim.partyAfter()
        for j, m in ipairs(members) do
            local a = after[j]
            if a then m.hp, m.mp, m.lb, m.statuses = a.hp, a.mp, a.lb, a.statuses end
        end
        if outcome == "loss" then break end
    end
    return results, party
end

local function describe(party, r)
    local bits = {}
    for _, m in ipairs(party) do bits[#bits + 1] = m.name .. "(" .. m.vision .. ")" end
    local foes = {}
    for _, f in ipairs(r.foes) do foes[#foes + 1] = f.name .. (f.card and (" g" .. f.card.gauge) or "") end
    return table.concat(bits, " "), table.concat(foes, ", ")
end

local tally = { fights = 0, win = 0, loss = 0, timeout = 0, fled = 0, baseWin = 0, baseFights = 0, rounds = 0, baseRounds = 0 }
local byKind, bySize, kinds = {}, {}, {}
local function bump(t, k, field, n)
    t[k] = t[k] or { fights = 0, win = 0, base = 0, baseFights = 0 }
    t[k][field] = t[k][field] + (n or 1)
end
local stats = { lb1 = 0, lb2 = 0, lbHeld = 0, lbSupport = 0, hiddenHits = 0, retries = 0, quickRefall = 0, partyHeals = 0, slowLost = 0, hasteTurns = 0, escapes = 0, fallsLogged = 0, pdWhileRaise = 0, weakChance = 0, weakUsed = 0, stalls = 0, falls = 0, raises = 0, draws = 0, ethers = 0, bonus = 0, sweeps = 0, finishByMod = 0, finish = 0,
    gameCommands = 0, modCommands = 0, cures = 0, warnCancel = 0, warnLand = 0, warnCancelLogged = 0, warnLandLogged = 0 }
local items = {}
local fails = 0
-- How often parts of the planner fire, from its own log lines.
local MARKS = {
    { "gauge released", "gauge estimate released" }, { "gauge restored", "working gauge restored" },
    { "gauge proved", "bonus proved the poured" }, { "break held", "break held. working gauge stays" },
    { "plan adds", "plan adds/" }, { "plan sync", "plan sync/" }, { "scout", "-> scout " },
    { "setup guard", "-> setup guard" }, { "debuff", " debuff " }, { "setup lb", "-> setup lb" },
    { "burst", "-> burst " }, { "esper", "-> setup esper" }, { "esper again", "-> esper" },
    { "draw", "-> draw " }, { "formation", "-> setup formation" }, { "opening heal", "-> opening " },
    { "critical heal", "-> critical " }, { "kill-range heal", "-> kill-range " }, { "recover heal", "-> recover " }, { "raise", "-> raise " },
    { "item raise", "-> item raise" }, { "cure", "-> cure " }, { "rescue", "-> rescue " },
    { "cure does not clear", "does not clear status" }, { "ether heal", "ether so a heal fits" },
    { "ether weak", "ether so the weakness fits" }, { "heal left", "heal left," }, { "heal left skipped", "heal left skipped" }, { "fill", "-> fill " },
    { "resonance sent", "resonance " }, { "wheel heal", "resonance heal " }, { "Cure", ": Cure -> " }, { "Cura", ": Cura -> " }, { "Curaga", ": Curaga -> " }, { "pot fight", "pot fight" }, { "summon acts", "acts on its own" },
    { "raise left", "raise left to" }, { "null learned", "takes no damage from" }, { "refresh guard", "-> refresh guard" }, { "ether hit", "ether so a hit lands" }, { "raise waits", "waits, a living ally" }, { "raise cycle", "fell again after a raise" }, { "stalemate", "stalemate:" }, { "haste", "-> haste " }, { "haste for slow", ", slow" },
    { "slow debuff", "debuff slow" }, { "slow skipped", "slow cure skipped" }, { "cure slow", "-> cure slow" },
    { "break in time", "break in time" }, { "prepare guard", "prepare: guard" },
    { "prepare heal", "prepare: heal-ahead" }, { "prepare defend", "prepare: defend" },
}
local marks = {}
local started = os.clock()

for sid = 1, sessions do
    local okM, mod, party = pcall(playSession, sid, true)
    if not okM then
        io.stderr:write("session ", sid, " crashed: ", tostring(mod), "\n")
        kinds["sim crash"] = (kinds["sim crash"] or 0) + 1
    else
        local okB, base = pcall(playSession, sid, false)
        for i, r in ipairs(mod) do
            tally.fights = tally.fights + 1
            tally[r.outcome] = tally[r.outcome] + 1
            tally.rounds = tally.rounds + r.rounds
            if r.outcome ~= "win" and r.bossLeft then
                tally.lossLeft = (tally.lossLeft or 0) + r.bossLeft
                tally.lossN = (tally.lossN or 0) + 1
            end
            bump(byKind, r.kind, "fights")
            bump(bySize, r.size, "fights")
            if r.outcome == "win" then bump(byKind, r.kind, "win") bump(bySize, r.size, "win") end
            for k in pairs(stats) do stats[k] = stats[k] + (r.stats[k] or 0) end
            for name, n in pairs(r.stats.items) do items[name] = (items[name] or 0) + n end
            if r.size == 2 then for _, line in ipairs(r.modLines) do if line:find(": Mass Cure %-> ") or line:find(": Mass Cura %-> ") then stats.partyHeals = stats.partyHeals + 1 end end end
            for _, line in ipairs(r.modLines) do
                local summary = line:match("battle %d+ done: (.*)$")
                if summary then
                    local fellPart = summary:match("%.%s([^%.]*)%.$")
                    if fellPart and fellPart ~= "no one fell" then
                        local n = 1
                        for _ in fellPart:gmatch(", ") do n = n + 1 end
                        stats.fallsLogged = stats.fallsLogged + n
                    end
                end
                local wc, wl = line:match("warned: (%d+) cancelled by a break, (%d+) landed")
                if wc then
                    stats.warnCancelLogged = stats.warnCancelLogged + tonumber(wc)
                    stats.warnLandLogged = stats.warnLandLogged + tonumber(wl)
                end
                for _, m in ipairs(MARKS) do
                    if line:find(m[2], 1, true) then marks[m[1]] = (marks[m[1]] or 0) + 1 end
                end
            end
            local b = okB and base[i] or nil
            if b and KEEP["baseline"] and b.outcome == "win" and r.outcome ~= "win" then
                local who, foes = describe(party, r)
                local path = string.format("%s/kept/s%04d_f%d_%s_baseline-won.txt", OUT, sid, i, r.kind)
                local f = io.open(path, "w")
                f:write(string.format("session %d fight %d (%s): planner %s in %d rounds, baseline won in %d\nparty: %s\nfoes: %s\n\nPLANNER LOG\n",
                    sid, i, r.kind, r.outcome, r.rounds, b.rounds, who, foes))
                for _, line in ipairs(r.modLines) do f:write("  ", line, "\n") end
                f:close()
            end
            if b then
                tally.baseFights = tally.baseFights + 1
                tally.baseRounds = tally.baseRounds + b.rounds
                bump(byKind, r.kind, "baseFights")
                bump(bySize, r.size, "baseFights")
                if b.outcome == "win" then
                    tally.baseWin = tally.baseWin + 1
                    bump(byKind, r.kind, "base")
                    bump(bySize, r.size, "base")
                end
            end
            if (#r.violations == 0) and KEEP[r.outcome] then
                local who, foes = describe(party, r)
                local path = string.format("%s/kept/s%04d_f%d_%s_%s.txt", OUT, sid, i, r.kind, r.outcome)
                local f = io.open(path, "w")
                f:write(string.format("session %d fight %d (%s%s), %s in %d rounds\nparty: %s\nfoes: %s\n\nSIM EVENTS\n",
                    sid, i, r.kind, r.boss and ", boss" or "", r.outcome, r.rounds, who, foes))
                for _, e in ipairs(r.events) do f:write("  ", e, "\n") end
                f:write("\nPLANNER LOG\n")
                for _, s in ipairs(r.modLines) do f:write("  ", s, "\n") end
                f:close()
            end
            if #r.violations > 0 then
                fails = fails + 1
                local seen = {}
                for _, v in ipairs(r.violations) do
                    if not seen[v.kind] then kinds[v.kind] = (kinds[v.kind] or 0) + 1 seen[v.kind] = true end
                end
                local who, foes = describe(party, r)
                local path = string.format("%s/fails/s%04d_f%d_%s.txt", OUT, sid, i, r.kind)
                local f = io.open(path, "w")
                f:write(string.format("session %d fight %d (%s%s), %s in %d rounds\nparty: %s\nfoes: %s\n\nRULES BROKEN\n",
                    sid, i, r.kind, r.boss and ", boss" or "", r.outcome, r.rounds, who, foes))
                for _, v in ipairs(r.violations) do f:write(string.format("  [%s] %s\n", v.kind, v.text)) end
                f:write("\nSIM EVENTS\n")
                for _, e in ipairs(r.events) do f:write("  ", e, "\n") end
                f:write("\nPLANNER LOG\n")
                for _, s in ipairs(r.modLines) do f:write("  ", s, "\n") end
                f:close()
            end
        end
    end
end

local function pct(a, b) return (b > 0) and string.format("%3d%%", math.floor(a * 100 / b + 0.5)) or "  - " end
local lines = {}
local function out(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end
out("FFR:AutoBattle sim: %d sessions, %d fights, seed %d, %.1fs", sessions, tally.fights, seed0, os.clock() - started)
out("")
out("Planner  win %s  loss %d  timeout %d  fled %d  avg rounds %.1f", pct(tally.win, tally.fights), tally.loss, tally.timeout, tally.fled,
    tally.rounds / math.max(1, tally.fights))
out("Baseline win %s  avg rounds %.1f   (attack with the strongest payable skill)", pct(tally.baseWin, tally.baseFights),
    tally.baseRounds / math.max(1, tally.baseFights))
if (tally.lossN or 0) > 0 then
    out("Planner losses: biggest enemy left at %.0f%% HP on average (%d fights)", 100 * tally.lossLeft / tally.lossN, tally.lossN)
end
out("")
out("%-9s %6s %8s %9s", "fight", "fights", "planner", "baseline")
local ks = {}
for k in pairs(byKind) do ks[#ks + 1] = k end
table.sort(ks)
for _, k in ipairs(ks) do
    local t = byKind[k]
    out("%-9s %6d %8s %9s", k, t.fights, pct(t.win, t.fights), pct(t.base, t.baseFights))
end
out("")
out("%-9s %6s %8s %9s", "party", "fights", "planner", "baseline")
for size = 1, 4 do
    local t = bySize[size]
    if t then out("%-9s %6d %8s %9s", size .. " ally", t.fights, pct(t.win, t.fights), pct(t.base, t.baseFights)) end
end
out("")
out("Planner commands %d, game-made %d, stalls %d, falls %d, raises %d, draws %d, cures %d, Ethers %d",
    stats.modCommands, stats.gameCommands, stats.stalls, stats.falls, stats.raises, stats.draws, stats.cures, stats.ethers)
out("Bonus turns %d, sweeps %d, Resonance wheels %d, finishers sent by the planner %d", stats.bonus, stats.sweeps, stats.finish, stats.finishByMod)
local il = {}
for name, n in pairs(items) do il[#il + 1] = name .. " x" .. n end
table.sort(il)
out("Items: %s", (#il > 0) and table.concat(il, ", ") or "none")
out("Weakness: a payable weakness hit was on the bar %d times, the planner took it %d times (%s)",
    stats.weakChance, stats.weakUsed, pct(stats.weakUsed, stats.weakChance))
out("Phoenix Down while a living ally could pay a raise spell: %d", stats.pdWhileRaise)
out("Falls: %d in the sim, %d in the planner's battle summaries", stats.falls, stats.fallsLogged)
out("Warned attacks: %d cancelled by a break, %d landed (planner log %d / %d)",
    stats.warnCancel, stats.warnLand, stats.warnCancelLogged, stats.warnLandLogged)
out("Haste turns %d, ally turns lost to Slow %d, party heals in 2-ally fights %d", stats.hasteTurns, stats.slowLost, stats.partyHeals)
out("Retries after a wipe %d. Raised allies who fell again within a round %d of %d raises", stats.retries, stats.quickRefall, stats.raises)
out("Hits into a hidden null: %d", stats.hiddenHits)
out("Limit Bursts: %d one-gauge, %d two-gauge, %d of them party support. Boss bonus turns with a full damage Limit that sent none: %d", stats.lb1, stats.lb2, stats.lbSupport, stats.lbHeld)
local ml = {}
for _, m in ipairs(MARKS) do ml[#ml + 1] = string.format("%s %d", m[1], marks[m[1]] or 0) end
out("Planner lines: %s", table.concat(ml, ", "))
out("")
out("Fights that broke a rule: %d of %d", fails, tally.fights)
local vk = {}
for k, n in pairs(kinds) do vk[#vk + 1] = { k, n } end
table.sort(vk, function(a, b) return a[2] > b[2] end)
for _, e in ipairs(vk) do out("  %-16s %d fights", e[1], e[2]) end
if fails > 0 then out("Details: sim/out/fails/") end
local report = table.concat(lines, "\n")
realPrint(report)
local f = io.open(OUT .. "/report.txt", "w")
f:write(report, "\n")
f:close()
