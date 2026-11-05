-- What FFRProbe watches. Edit and restart the game; no code change needed.
return {
    -- Extra classes to walk on every snapshot, by short class name, as
    -- FindAllOf takes them. CPP_VM_BtlTimeLine holds the Timeline view
    -- (C++ header dump, 2026-11-03). CPP_BtlManager is left out: walking it
    -- reached thousands of objects and crashed the game in v0.1.
    classes = { "CPP_VM_BtlTimeLine" },

    -- Object links are followed only when the property has one of these
    -- names (and the object's class is in /Script/mucha, or matches
    -- `follow`). Empty: no links are followed.
    followProps = {},
    follow = {},

    -- Property names to leave out (Lua patterns).
    skip = { "Location", "Rotation", "Scale", "Velocity", "Transform", "Delta", "Tick",
             "Instigator", "Owner", "Mimic" },

    -- Also walk when an event tag matches one of these (Lua patterns).
    walkOnTags = { "Break", "Stagger", "Turn", "Phase", "Finish", "Damage" },

    -- Libraries whose functions F7 lists with their parameters (metadata only).
    libraries = {
        "CPP_BFL_Battle", "CPP_BFL_Skill", "CPP_BFL_Item",
        "CPP_UI_BattleSubsystem", "CPP_BtlUnit", "CPP_BtlDelEventCmd",
        "CPP_BtlManager", "CPP_BtlUnitParameter", "CPP_BtlUnitAI", "CPP_BFL_UnitParameterCalc",
        "CPP_VM_BtlTimeLine", "CPP_BtlUnitTimelineScheduler", "CPP_BtlSkill",
    },

    -- Row structs whose fields and first rows F7 writes out.
    tables = {
        "SKILL_DATA", "SKILL_EFFECT_DATA", "PASSIVE_SKILL_DATA", "COMMAND_SKILL_DATA",
        "CONSUMABLES_ITEM_DATA", "UNIT_PARAMETER", "SKILL_GENERAL_DATA",
        "SKILL_DAMAGE_CALC_DATA", "SKILL_RECOVERY_CALC_DATA", "SKILL_TARGET_DATA",
        "SKILL_ATTRIBUTE_DETAIL_DATA", "STATUS_CONDITION_DATA", "STATUS_CONDITION_DETAIL_DATA",
    },
    sampleRows = 3,

    -- v0.4: F7 is off (it crashed the game; the C++ header dump has every
    -- table's fields). Set to "F7" to turn it back on.
    schemaKey = false,
    dumpAll = true,
    snapshot = false,

    -- What runs after each event. walk is the generic value diff (off).
    hits = true,
    vitals = true,
    walk = false,
    crumbs = 6,
    -- Structs and arrays inside an object, two levels. Links are not followed.
    maxDepth = 2,
    maxArray = 16,
}
