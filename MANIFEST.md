# The Golden Rule

**The code must work everywhere if it works anywhere.**

No one-off solutions. No edge-case patches. A decision that is right for one battle, one party, one skill, or one loadout, and wrong for another, does not go in. A win does not justify keeping it.

## What that means

**Same logic, every fight.** Any battle, any party, any Visions, any gear, any skills. Nothing in the code is for a boss, a character, or a loadout. If the party does not hold that skill, or the foe does not work that way, the same rule still has to make sense.

**Read the battle. Don't memorize it.** Weaknesses, gauges, dangerous moves, and damage cuts come from the game's own rows. Everything else comes from what happens in this fight. The code never names the fight it is in. A warned hit is answered because the game warned it, whoever threw it.

**A special case is a failed rule.** A heal line, an MP band, a gauge ratio, or a score weight we picked is an edge case. So is a plan that only pays off for the party we happened to bring. The replacement is a number the game already stores, or a comparison this fight's own results already support. That same comparison has to be the right one in the next fight, with a different party.

**The party answers with whatever it holds.** Ask what is about to happen, who it kills, and which action this party actually has that deals with it. A party with none of the usual answers still gets an answer, including "keep casting."

**Judge the logic, not the result.** One loss does not prove a rule wrong, and one win does not prove it right. If the code only does the right thing where we have already fought, it does not work.

## Before adding a rule

1. **Would this still be right in a fight that is not this one?** If it only fits here, it is a one-off.
2. **Would this still be right with a party that is not this one?** If it needs a role, a skill, a Vision, or a character the player may not have brought, it is an edge case.
3. **Does it name a boss, a skill, a character, or a Vision?** Rewrite it around what that thing does, so anything else that does the same thing is treated the same way.
4. **Does the number come from the game, or from this fight's own results?** A number we chose does not go in.

If a fight still beats us after that, let it. Fix the thinking, not the fight.
