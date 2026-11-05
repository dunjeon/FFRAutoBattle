-- Planner 2: tactics are weight tables. The scorer multiplies each term by
-- its weight and adds them up. The player picks one in config.ini (later).
-- Starting values; Phase 6 tunes them in the sim and in shadow mode.

return {
    balanced = {
        damage = 1.0,     -- share of the field's HP taken off
        stagger = 1.2,    -- share of a gauge poured
        breakNow = 1.5,   -- emptying a gauge this action (bonus turn)
        cancel = 4.0,     -- a break that lands before a warned body's slot
        kill = 1.0,       -- a body that stops acting
        heal = 1.5,       -- missing HP restored, weighted by danger
        setup = 1.0,      -- a buff or debuff that isn't up yet
        revive = 1.6,     -- a fallen ally back
        item = 1.0,       -- the bag spent (rare items cost more)
        cost = 0.4,       -- MP spent, as a share of what the actor has
        early = 0.5,      -- penalty: breaking one gauge while others are far
    },
    all_out = {
        damage = 1.6, stagger = 1.2, breakNow = 1.5, cancel = 4.0, kill = 1.6,
        heal = 0.8, setup = 0.4, revive = 1.2, item = 0.3, cost = 0.1, early = 0.2,
    },
    safe = {
        damage = 0.8, stagger = 1.0, breakNow = 1.2, cancel = 5.0, kill = 1.0,
        heal = 2.5, setup = 1.2, revive = 2.0, item = 1.0, cost = 0.6, early = 0.6,
    },
}
