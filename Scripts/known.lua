-- Published skill and item facts for FFR:AutoBattle.
-- Stagger numbers are the ones printed on the Resonance wiki ability pages and
-- the boss guides (a plain Attack is 25, Tackle 35, Dawn Frost 30, Fire 17).
-- A weakness hit is three times that stagger. This list does not know the enemy,
-- so it only ranks the skill's own number. The live table is the fallback.
--
-- use:
--   break     fill the gauge
--   cash      save for the bonus phase and the Resonance
--   opener    cast once before the first swing (Hone Senses)
--   guardbuff Shell or Protect, once, and only in a boss fight
--   guard     Defend. Last resort, never an opener
--   heal      restore HP
--   patch     a heal too small to spend the turn on. A potion is preferred.
--   debuff    a real debuff, once
--   lb-setup  Limit Burst whose payoff is before the break (Null Moon)
--   lb-cash   Limit Burst whose payoff is after the break
--   scan      Libra. Left alone; the result is not readable yet

return {
    skills = {
        ["attack"] = { stagger = 25, use = "break", phys = true },
        ["tackle"] = { stagger = 35, use = "break", phys = true },
        ["dawn frost"] = { stagger = 30, element = "ice", use = "break", magic = true },
        ["fire"] = { stagger = 17, element = "fire", use = "break", magic = true },
        ["fira"] = { stagger = 19, element = "fire", use = "break", magic = true },
        ["blizzard"] = { stagger = 17, element = "ice", use = "break", magic = true },
        ["thunder"] = { stagger = 17, element = "thunder", use = "break", magic = true },
        ["banish"] = { stagger = 17, element = "light", use = "cash", magic = true },
        ["flame sword"] = { stagger = 33, element = "fire", use = "break", phys = true },
        ["ice splitter"] = { stagger = 25, element = "ice", use = "break", phys = true },
        ["tranquility"] = { stagger = 40, use = "break", magic = true },
        ["null moon"] = { stagger = 27, use = "lb-setup" },
        ["infinity drive"] = { stagger = 25, element = "fire", use = "lb-cash" },
        ["hone senses"] = { use = "opener" },
        ["shell"] = { use = "guardbuff" },
        ["protect"] = { use = "guardbuff" },
        ["defend"] = { use = "guard" },
        ["guard"] = { use = "guard" },
        ["blind"] = { use = "debuff" },
        ["cure"] = { use = "heal" },
        ["first aid"] = { use = "heal", patch = true },
        ["libra"] = { use = "scan" },
        -- Vision Resonances. The wheel offers whichever of these the equipped Vision can activate.
        ["fatal impact"] = { element = "earth", phys = true, use = "finish" },
        ["errand's end"] = { element = "fire", magic = true, use = "finish" },
        ["angelic embrace"] = { use = "heal" },
        ["spellblade-dual wield-rapid fire"] = { phys = true, use = "finish" },
        ["alluvial undertow"] = { element = "water", phys = true, use = "finish" },
        ["knight of duality"] = { element = "light", phys = true, use = "finish" },
        ["resolute bastion"] = { use = "heal" },
        ["true ifrit-primed"] = { element = "fire", phys = true, use = "finish" },
        ["ascension"] = { element = "thunder", phys = true, use = "finish" },
        ["weaponsmaster"] = { element = "light", phys = true, use = "finish" },
        ["healing wind"] = { use = "heal" },
        ["zantetsuken"] = { element = "thunder", phys = true, use = "finish" },
        ["armiger unleashed"] = { phys = true, use = "finish" },
        ["job change attack"] = { magic = true, use = "finish" },
        ["true octaslash"] = { phys = true, use = "finish" },
        ["colossal shantotto ii"] = { element = "dark", magic = true, use = "finish" },
        ["blasting zone"] = { element = "fire", phys = true, use = "finish" },
        ["riot blade - lotus"] = { magic = true, use = "finish" },
        ["blitz ace"] = { element = "water", phys = true, use = "finish" },
        ["hibernal fury"] = { element = "ice", magic = true, use = "finish" },
        ["true pyroclasm"] = { element = "fire", phys = true, use = "finish" },
        ["agony"] = { element = "dark", magic = true, use = "finish" },
        ["crystal braver"] = { phys = true, use = "finish" },
        ["towering rampart"] = { use = "buff" },
        ["aetherial wind"] = { element = "wind", magic = true, use = "finish" },
        ["climax edge"] = { element = "wind", magic = true, use = "finish" },
    },
    -- Shop recovery the player can buy again. Elixirs, X-tier, and scrolls stay put.
    items = {
        ["potion"] = "hp",
        ["hi-potion"] = "hp",
        ["mist potion"] = "hp",
        ["ether"] = "mp",
        ["mist ether"] = "mp",
        ["phoenix down"] = "revive",
        ["antidote"] = "cure",
        ["antidote herb"] = "cure",
        ["eye drops"] = "cure",
        ["echo herb"] = "cure",
        ["smelling salts"] = "cure",
        ["unicorn horn"] = "cure",
        ["gold needle"] = "cure",
        ["remedy"] = "cure",
    },
    leave = {
        ["elixir"] = true,
        ["megalixir"] = true,
        ["x-potion"] = true,
        ["mist hi-potion"] = true,
        ["mist x-potion"] = true,
        ["turbo ether"] = true,
        ["mist turbo ether"] = true,
        ["x-ether"] = true,
        ["mist x-ether"] = true,
        ["phoenix pinion"] = true,
        ["tent"] = true,
    },
}
