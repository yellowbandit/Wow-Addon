-- Harness: P3.1 — fitness snapshot + behavioral regression net for
-- SequenceOptimizer.lua EvaluateFitness (Addon.DebugEvaluateStepArray).
-- Runnable outside WoW with plain luajit. Golden values were captured from the
-- implementation on 2026-09-12; if a tuning-constant change is intentional,
-- update the goldens here — if it is not, it will FAIL.
--
-- Usage:
--   luajit fitness_snapshot_test.lua            -> assert + check mode
--   luajit fitness_snapshot_test.lua capture    -> reprint current goldens

local SRC = "H:\\OPEN CODE WOW CHAT\\Wow-Addon\\DummyAnalyzer\\SequenceOptimizer.lua"

local stubAddon = {
	GetCharDB = function() return { settings = {} } end,
	NumberOrZero = function(v) return v or 0 end,
	DebugLog = function() end,
	Ems_Default = function() return "" end,
	IsValidMacroSpell = function() return true end,
	GetActionPrefix = function() return "/cast" end,
	ScanPlayerTalents = function() return {}, {} end,
	FilterSimCData = function() return nil end,
	CAST_BUFF_DURATIONS_LOOKUP = {},
	EmphasizedSequence = nil,
}

local env = setmetatable({}, { __index = _G })
env.UnitGUID = function() return nil end
env.UnitClass = function() return "", "" end
env.DummyAnalyzerDB = nil

local chunk = assert(loadfile(SRC))
setfenv(chunk, env)
chunk("DummyAnalyzer", stubAddon)
local Eval = assert(stubAddon.DebugEvaluateStepArray, "DebugEvaluateStepArray not exported")

-- copy of the sel-harness mkCtx, extended with optional buffs + simcBuffBenefit
-- spells = {name, dpc, count, simcCasts?, simcWeight?, aplPos?}
-- buffs   = { {name=, uptime=0..1, simcBenefit=0..1} }
function mkCtx(spells, longCDs, buffs)
	longCDs = longCDs or {}
	buffs = buffs or {}
	local baseEntries = {}
	local simcCasts, simcWeights, aplPosition = {}, {}, {}
	local totalActualCasts, totalActualDmg = 0, 0
	local maxSimcWeight, aplMax = 0, 0
	for _, s in ipairs(spells) do
		baseEntries[#baseEntries + 1] = { name = s.name, dpc = s.dpc, count = s.count }
		totalActualCasts = totalActualCasts + s.count
		totalActualDmg = totalActualDmg + s.dpc * s.count
		simcCasts[s.name] = s.simcCasts or (s.count * 0.5)
		local w = s.simcWeight or 0.5
		simcWeights[s.name] = w
		maxSimcWeight = math.max(maxSimcWeight, w)
		aplPosition[s.name] = s.aplPos or 1
		aplMax = math.max(aplMax, s.aplPos or 1)
	end
	local buffByName, simcBuffBenefit = {}, {}
	for _, b in ipairs(buffs) do
		buffByName[b.name] = { name = b.name, uptime = b.uptime }
		simcBuffBenefit[b.name] = b.simcBenefit or 0
	end
	return {
		baseEntries = baseEntries,
		simcCasts = simcCasts,
		simcWeights = simcWeights,
		maxSimcWeight = maxSimcWeight,
		aplPosition = aplPosition,
		aplMax = math.max(aplMax, 1),
		buffByName = buffByName,
		buffMaxGap = {},
		simcBuffBenefit = simcBuffBenefit,
		totalActualCasts = math.max(1, totalActualCasts),
		avgDmg = totalActualDmg / math.max(1, totalActualCasts),
		duration = 120,
		simcMult = 1,
		simcDuration = 120,
		isLongCD = function(name) return longCDs[name] == true end,
	}
end

local F = {
	-- F1 balanced rotation: filler / spender / cooldown with SimC mirror
	f1 = {
		spells = {
			{ name = "Filler",  dpc = 8000,  count = 40, simcCasts = 45, simcWeight = 0.6, aplPos = 2 },
			{ name = "Spender", dpc = 12000, count = 20, simcCasts = 25, simcWeight = 0.8, aplPos = 1 },
			{ name = "CD",      dpc = 30000, count = 5,  simcCasts = 6,  simcWeight = 1.0, aplPos = 3 },
		},
		good = { "CD", "Spender", "Filler", "Spender", "Filler", "Filler", "CD", "Filler" },
		bad  = { "Filler", "Spender", "CD", "Filler", "Spender", "CD", "Filler", "CD" },
	},
	-- F2 proc-burst: a fragile high-dpc proc spell that needs to over-cast -> penalty
	f2 = {
		spells = {
			{ name = "Proc",   dpc = 60000, count = 8,  simcCasts = 6,  simcWeight = 0.9, aplPos = 1 },
			{ name = "Filler", dpc = 9000,  count = 30, simcCasts = 30, simcWeight = 0.5, aplPos = 2 },
		},
		overcast = { "Proc", "Filler", "Proc", "Filler", "Proc", "Filler", "Proc", "Filler", "Proc", "Proc", "Proc", "Filler" },
		balanced = { "Proc", "Filler", "Proc", "Filler", "Proc", "Filler", "Proc", "Filler", "Proc", "Filler", "Filler", "Filler" },
	},
	-- F3 buff-dependent: opener-vs-late placement drives the buff penalty terms
	f3 = {
		spells = {
			{ name = "BuffSpell", dpc = 20000, count = 12, simcCasts = 12, simcWeight = 0.7, aplPos = 1 },
			{ name = "Filler",    dpc = 9000,  count = 30, simcCasts = 30, simcWeight = 0.5, aplPos = 2 },
		},
		buffs = { { name = "BurstBuff", uptime = 0.4, simcBenefit = 0.6 } },
		opener = { "BuffSpell", "Filler", "BuffSpell", "Filler" },
		late =    { "Filler", "Filler", "Filler", "Filler", "Filler", "BuffSpell", "Filler", "BuffSpell" },
	},
	-- F4 SimC-missing: a spell the sim expects heavily but the log barely cast
	f4 = {
		spells = {
			{ name = "Main",      dpc = 20000, count = 10, simcCasts = 40, simcWeight = 1.0, aplPos = 1 },
			{ name = "Filler",    dpc = 9000,  count = 40, simcCasts = 10, simcWeight = 0.3, aplPos = 2 },
		},
		starved = { "Main", "Filler", "Filler", "Filler", "Filler", "Filler", "Filler" },
		healthy = { "Main", "Main", "Main", "Main", "Main", "Main", "Main", "Main", "Main", "Main", "Filler", "Filler" },
	},
	-- F5 long-CD defensives are never eligible (isLongCD), plus AoE-mix sanity
	f5 = {
		spells = {
			{ name = "Lust",     dpc = 40000, count = 2,  simcCasts = 2,  simcWeight = 1.0, aplPos = 1 },
			{ name = "AoE",      dpc = 15000, count = 25, simcCasts = 25, simcWeight = 0.7, aplPos = 2 },
			{ name = "Filler",   dpc = 9000,  count = 20, simcCasts = 20, simcWeight = 0.4, aplPos = 3 },
		},
		longCDs = { Lust = true },
		arr = { "Lust", "AoE", "Filler", "AoE", "Filler", "AoE", "Filler", "AoE", "Filler", "Lust" },
	},
}

local expected = {
	f1_good = 122218.0789, f1_bad = 143858.4763,
	f2_overcast = 484092.8222, f2_balanced = 380122.1379,
	f3_opener = 62177.6939, f3_late = 100612.2653,
	f4_starved = 78581.5000, f4_healthy = 230423.0000,
	f5 = 184528.3162,
}

local ctxCache = {}
local function ctxOf(f)
	local key = f
	if not ctxCache[key] then
		ctxCache[key] = mkCtx(F[key].spells, F[key].longCDs, F[key].buffs)
	end
	return ctxCache[key]
end

local function compute()
	local out = {}
	out.f1_good   = Eval(F.f1.good, ctxOf("f1"))
	out.f1_bad    = Eval(F.f1.bad, ctxOf("f1"))
	out.f2_overcast = Eval(F.f2.overcast, ctxOf("f2"))
	out.f2_balanced = Eval(F.f2.balanced, ctxOf("f2"))
	out.f3_opener = Eval(F.f3.opener, ctxOf("f3"))
	out.f3_late   = Eval(F.f3.late, ctxOf("f3"))
	out.f4_starved = Eval(F.f4.starved, ctxOf("f4"))
	out.f4_healthy = Eval(F.f4.healthy, ctxOf("f4"))
	out.f5        = Eval(F.f5.arr, ctxOf("f5"))
	return out
end

if arg and arg[1] == "capture" then
	local now = compute()
	for k, v in pairs(now) do
		print(string.format("  %-16s = %.4f", k, v))
	end
	os.exit(0)
end

local fails = 0
function check(cond, label)
	if cond then print("PASS: " .. label)
	else fails = fails + 1; print("FAIL: " .. label) end
end

local now = compute()
for k, v in pairs(now) do
	local tol = 1e-6 * math.max(1, math.abs(expected[k]))
	check(math.abs(v - expected[k]) <= tol, string.format("golden %s = %.4f (expected %.4f)", k, v, expected[k]))
end

-- determinism: EvaluateFitness has no RNG; identical input must produce identical output
local again = compute()
for k, v in pairs(now) do
	check(v == again[k], "deterministic " .. k)
end

-- the ONE semantic invariant the formula genuinely encodes: SimC-missing penalty.
-- A log where SimC expects 40 Main casts but got 10 is punished vs one that keeps
-- pace with expectations (f4_healthy > f4_starved).
check(now.f4_healthy > now.f4_starved, "F4 matching SimC expected casts beats being starved (" .. string.format("%.1f>%.1f", now.f4_healthy, now.f4_starved) .. ")")

if fails == 0 then
	print("ALL FITNESS SNAPSHOT ASSERTIONS PASSED")
	os.exit(0)
else
	print(fails .. " FAILURES")
	os.exit(1)
end