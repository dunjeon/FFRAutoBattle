-- lua5.4 tests/test_claims.lua
local H = dofile("Scripts/health.lua")
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end
local hp = { [1] = 500 }
local claims, marks = { [1] = true }, {}
local function review() return H.reviewClaims(claims, marks, { 1 }, function(id) return hp[id] end) end
review()
check(claims[1] and marks[1] == 500, "the first look sets where the claim stands")
hp[1] = 900
review()
check(claims[1] and marks[1] == 900, "a heal landing raises it and keeps the claim")
hp[1] = 900
review()
check(claims[1], "no change keeps the claim")
hp[1] = 150
local freed = review()
check((not claims[1]) and (#freed == 1) and (freed[1] == 1), "a new hit ends the claim, so a healer can act")
check(marks[1] == nil, "and nothing is left over")
claims[1], hp[1] = nil, 400
review()
check(#review() == 0 and marks[1] == nil, "no claim, nothing to do")
claims[1] = true
hp[1] = nil
check(#review() == 0 and claims[1], "an HP that can't be read leaves the claim alone")
os.exit(fails == 0 and 0 or 1)
