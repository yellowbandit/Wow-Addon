local AddonName, Addon = ...
-- ============================================
-- FORMAT HELPERS (original)
-- ============================================
local IsSecretValue = Addon.IsSecretValue

function Addon.FormatNumber(num)
    if not num then return "0" end
    local formatted = tostring(math.floor(num))
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

-- secret-safe concatenation: table.concat is blocked for secret values
local function SecretSafe(val)
    local ok, isSec = pcall(IsSecretValue, val)
    return (ok and isSec) and true or false
end

local function JoinLines(lines)
    local result = ""
    for _, line in ipairs(lines) do
        if not SecretSafe(line) then result = result .. line .. "\n" end
    end
    return result
end

local function ShortNum(n)
    local neg = n and n < 0
    n = math.floor(math.abs(n or 0))
    local result
    if n >= 1000000 then result = string.format("%.2fM", n / 1000000)
    elseif n >= 1000 then result = string.format("%.1fK", n / 1000)
    else result = tostring(n)
    end
    return neg and "-" .. result or result
end
Addon.ShortNum = ShortNum

-- Clean display name for a saved log, skipping the stats text embedded in log.label
local function LogDisplayName(log)
    if not log then return "?" end
    if log.detectedSeqName and log.detectedSeqName ~= "" then return log.detectedSeqName end
    local name = string.match(log.label or "", "%[([^%]]+)%]$")
    if name and name ~= "" then return name end
    if log.isSimC then return "SimC Reference" end
    return "#" .. (log.id or "?")
end

-- ============================================
-- FORMATHELPERS EXPORTS (namespace promotion, rule A/B)
-- ============================================
Addon.JoinLines = JoinLines
Addon.LogDisplayName = LogDisplayName