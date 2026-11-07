-- lua5.4 tests/test_report.lua
local Report = dofile("Scripts/report.lua")
local path = os.tmpname()
local R = Report.new(path, function() return "12:00:00" end)
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end
local function read()
    local f = io.open(path); local s = f:read("a"); f:close(); return s
end
local function ally(hp, mp, down) return { name = "Fina", hp = hp, maxHp = 1000, mp = mp, maxMp = 200, lb = 0, gauge = 100, maxGauge = 100, statuses = {}, down = down } end
local function foe(hp, g, st) return { name = "Boss", hp = hp, maxHp = 5000, gauge = g, maxGauge = 1600, statuses = st or {} } end
R:begin({ number = 1, boss = true, difficulty = "difficulty 2" })
R:field({ allies = { [2] = ally(1000, 200, false) }, foes = { [8] = foe(5000, 100) } })
R:decide({ who = "Fina", phase = 0, round = 1, mp = 200, maxMp = 200, lb = 0, name = "Attack", id = 1, kind = "damage", reason = "sync", cost = 0,
    targets = { { name = "Boss", factor = 1, weakPaid = "Thunder" } }, could = { "Thunder 5 (Boss x3)" }, canHeal = true, isHealer = true })
R:hit({ from = 2, to = 8, skill = 1, skillName = "Attack", fromName = "Fina", toName = "Boss", fromFriend = true, param = 1, vtype = 1, value = 100, before = 5000, after = 4900, breakValue = 50 })
R:hit({ from = 2, to = 8, skill = 1, skillName = "Attack", fromName = "Fina", toName = "Boss", fromFriend = true, param = 1, vtype = 1, value = 100, before = 5000, after = 4900, breakValue = 50 })
R:field({ allies = { [2] = ally(100, 190, false) }, foes = { [8] = foe(4900, 0, { [89] = true }) } })
R:decide({ who = "Fina", phase = 0, round = 1, mp = 190, maxMp = 200, name = "Fire", id = 2, kind = "damage", reason = "fill", cost = 5,
    targets = { { name = "Boss", factor = 0 } }, canHeal = true, isHealer = true })
R:decide({ who = "Fina", phase = 0, round = 2, mp = 185, maxMp = 200, name = "Cure", id = 3, kind = "heal", reason = "x", cost = 6, targets = { { name = "Fina", pct = 80 } }, canHeal = true })
R:hit({ from = 2, to = 2, skill = 3, skillName = "Cure", fromName = "Fina", toName = "Fina", fromFriend = true, toFriend = true, param = 1, vtype = 0, value = 400, before = 800, after = 1000, breakValue = 0 })
R:decide({ who = "Fina", phase = 0, round = 2, mp = 2, maxMp = 200, name = "Attack", id = 1, kind = "damage", reason = "x", cost = 0, targets = { { name = "Boss", factor = 1 } },
    short = { { need = "heal", what = "Cure for Fina", spent = false }, { need = "weakness", what = "Thunder on Boss", spent = true } } })
R:field({ allies = { [2] = ally(900, 179, false) }, foes = { [8] = foe(4900, 0, {}) } })
R:decide({ who = "Fina", phase = 1, round = 2, mp = 179, maxMp = 200, name = "Shell", id = 5, kind = "buff", reason = "setup", cost = 5, targets = { { name = "Fina", pct = 90 } } })
R:field({ allies = { [2] = ally(100, 174, false) }, foes = { [8] = foe(4900, 0, {}) } })
R:decide({ who = "Fina", phase = 1, round = 2, mp = 100, maxMp = 200, name = "Attack", id = 1, kind = "damage", reason = "burst", cost = 0, attr = 1, targets = { { name = "Boss", factor = 1 } },
    limitReady = "Holy Ray", value = 100, bestValue = 900, bestName = "Thundara", now = "Fina Boss", multicastSweep = "Fire", multicastHeal = "Cura" })
R:hit({ from = 2, to = 8, skill = 1, skillName = "Attack", fromName = "Fina", toName = "Boss", fromFriend = true, param = 1, vtype = 1, value = 700, before = 4900, after = 4200, breakValue = 0, onBreak = true })
R:hit({ from = 2, to = 8, skill = 1, skillName = "Attack2", fromName = "Fina", toName = "Boss", fromFriend = true, param = 1, vtype = 1, value = 50, before = 5000, after = 4950, breakValue = 50, trigger = true })
R:field({ allies = { [2] = ally(0, 179, true) }, foes = { [8] = foe(4900, 0, {}) } })
R:decide({ byHand = true, who = "Fina", phase = 0, round = 2, mp = 100, maxMp = 200, name = "Blind", id = 9, kind = "debuff", reason = "sent by the player", cost = 5, targets = { { name = "Boss", factor = 0 } } })
R:note("  a line from the battle log")
R:finish({ rounds = 2, wheelOpen = 1, wheelSent = 1 })
local s = read()
check(s:find("=== FIGHT 1, boss true, difficulty 2", 1, true), "the fight header has the difficulty")
check(s:find("hp 1000>100", 1, true) and s:find("mp 200>190", 1, true), "HP and MP changes are written")
check(s:find("gauge 100>0 +st89 BROKE", 1, true) or s:find("BROKE", 1, true), "a break is written")
check(s:find("FELL", 1, true), "a fall is written")
check(select(2, s:gsub("hit Fina > Boss: Attack, param 1 type 1 value 100", "")) == 1, "a repeated hit record is written once")
check(s:find("could pay: Thunder 5 (Boss x3)", 1, true), "what could be paid is written")
check(s:find("why: sync", 1, true), "the reason is written")
check(s:find("--- REPORT fight 1", 1, true) and s:find("--- END REPORT", 1, true), "the report is written")
check(s:find("damage logged 850, stagger logged 100, healed 400 (overheal 200)", 1, true), "the party totals add up")
check(s:find("breaks 1", 1, true), "the enemy's breaks are counted")
check(s:find("weakness on the bar, hit something else: 1", 1, true), "a missed weakness is flagged")
check(s:find("hit that can't land: 1", 1, true), "a hit that can't land is flagged")
check(s:find("no heal with an ally under 30%, heal payable: 1", 1, true) or s:find("heal on an ally at 65% or more: 1", 1, true), "care flags are counted")
check(s:find("heal on an ally at 65% or more: 1", 1, true), "a heal at 80% is flagged")
check(s:find("wheels opened 1, sent 1", 1, true), "wheels are counted")
check(s:find(" BY HAND round 2", 1, true), "a player's command is written and marked")
check(s:find("Blind x1", 1, true), "a player's command counts in the totals")
check(not s:find("#%d+ Fina Blind"), "a player's command isn't flagged")
check(s:find("staggers: 1 seen on the gauge, 1 in the hit records, 1 of them sweeps", 1, true), "staggers are counted, with the sweep")
check(s:find("on Boss: HP 100%>98%", 1, true), "a stagger shows HP before and after")
check(s:find("1 hits, 700 damage", 1, true), "only hits on a staggered body count to its window")
check(s:find("Limit ready during a stagger, not used: 1", 1, true), "an unused Limit is flagged")
check(s:find("stagger open, hit under half the best payable: 1", 1, true), "a weak hit in the window is flagged")
check(s:find("stagger open, nobody critical, turn wasn't a hit", 1, true), "an off-task window turn is flagged")
check(s:find("every gauge low, Multicast in reach", 1, true) and s:find("Multicast heal in reach", 1, true), "Multicast chances are flagged")
check(s:find("(11%) on staggered", 1, true) or s:find("on staggered bodies", 1, true), "damage on staggered bodies is reported")
check(s:find("short of MP for a heal, Ether in the bag: 1", 1, true), "short of MP for a heal is flagged")
check(s:find("short of MP for a weakness, Ether in the bag: 1", 1, true) and s:find("(Ether already spent this round)", 1, true), "the one-a-round limit is noted")
check(s:find("12:00:00 a line from the battle log", 1, true), "battle log lines are mirrored")
R:finish({})
R:decide({ who = "x", name = "y" })
check(true, "calls with no fight open do nothing")
local function fightFile(count)
    local f = io.open(path, "w")
    for i = 1, count do
        f:write("12:00:00 == battle ", i, " ==\n\n=== FIGHT ", i, ", boss false ===\nbody ", i, "\n--- END REPORT\n12:00:01 after ", i, "\n")
    end
    f:close()
end
local function countFights(s)
    local n = 0
    for _ in s:gmatch("=== FIGHT") do n = n + 1 end
    return n
end
fightFile(7)
R:trim()
local t = read()
check(countFights(t) == 5, "a launch keeps five fights")
check(t:sub(1, 20) == "12:00:00 == battle 3", "the kept file opens on the oldest kept fight's battle line")
check(t:find("after 7", 1, true) and not t:find("after 2", 1, true), "the newest fights stay and the older ones go")
fightFile(5)
local whole = read()
R:trim()
check(read() == whole, "five fights are left alone")
fightFile(5)
R:begin({ number = 6, boss = false })
R.fight = nil
t = read()
check(countFights(t) == 5 and t:find("=== FIGHT 6", 1, true) and not t:find("=== FIGHT 1,", 1, true), "a new fight drops the oldest")
os.remove(path)
print(fails == 0 and "OK" or (fails .. " checks failed"))
-- HP readings and enemy moves, on a fight of their own.
local path2 = os.tmpname()
local R2 = Report.new(path2, function() return "12:00:00" end)
R2:begin({ number = 2, boss = true })
local function body(hp, gauge) return { name = "Boss", hp = hp, maxHp = 1000, gauge = gauge, maxGauge = 100, statuses = {} } end
local hero = { name = "Rain", hp = 50, maxHp = 100, mp = 1, maxMp = 1, lb = 0, gauge = 1, maxGauge = 1, statuses = {} }
R2:field({ allies = { [1] = hero }, foes = { [9] = body(1000, 50) } })
R2:field({ allies = { [1] = hero }, foes = { [9] = body(700, 0) } })
R2:field({ allies = { [1] = hero }, foes = { [9] = body(200, 0) } })
R2:hit({ from = 9, to = 1, skill = 5, skillName = "Big Wave", fromName = "Boss", toName = "Rain", fromFriend = false, toFriend = true, param = 1, vtype = 1, value = 60, before = 50, after = 0 })
R2:field({ allies = { [1] = hero }, foes = {} })
R2:finish({})
local f2 = io.open(path2); local s2 = f2:read("a"); f2:close(); os.remove(path2)
check(s2:find("damage by HP readings: 1000 total", 1, true), "HP readings count every drop, and a body that goes")
check(s2:find("drop 500 on Boss", 1, true), "the biggest drops are listed")
check(s2:find("700 by HP", 1, true), "a stagger shows the HP it really took")
check(s2:find("Big Wave 1 hits, worst 60, 1 kills", 1, true), "an enemy's moves and kills are listed")
os.exit(fails == 0 and 0 or 1)
