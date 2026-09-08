local AddonName, Addon = ...
-- ============================================
-- SimC IMPORT
-- ============================================
local DebugLog = Addon.DebugLog
local GetCharDB = Addon.GetCharDB
local SafeSetFont = Addon.SafeSetFont
local CreateStyledFrame = Addon.CreateStyledFrame
local trackDialog = Addon.trackDialog
local ApplyBackdrop = Addon.ApplyBackdrop
local CreateStyledButton = Addon.CreateStyledButton
local RegisterAddonWindow = Addon.RegisterAddonWindow
local C = Addon.C
local MAIN_FONT = Addon.MAIN_FONT
local BOLD_FONT = Addon.BOLD_FONT

-- FilterSimCData is assigned in SequenceCore.lua (#12), which loads after this
-- module; deferred resolution through Addon keeps the load order safe.
local function FilterSimCData(castCounts, damageData) return Addon.FilterSimCData(castCounts, damageData) end

local SIMC_SPELL_MAP = {
    -- Generic
    ["auto_attack"] = "Auto Attack",
    ["autoattack"] = "Auto Attack",
    -- Warrior (Arms/Fury/Prot)
    ["mortal_strike"] = "Mortal Strike",
    ["execute"] = "Execute",
    ["colossus_smash"] = "Colossus Smash",
    ["bladestorm"] = "Bladestorm",
    ["rend"] = "Rend",
    ["slam"] = "Slam",
    ["overpower"] = "Overpower",
    ["thunder_clap"] = "Thunder Clap",
    ["shield_slam"] = "Shield Slam",
    ["revenge"] = "Revenge",
    ["devastate"] = "Devastate",
    ["ignite_weapon"] = "Ignite Weapon",
    ["spear_of_bastion"] = "Spear of Bastion",
    ["condemn"] = "Condemn",
    ["shield_block"] = "Shield Block",
    ["shield_charge"] = "Shield Charge",
    ["ravager"] = "Ravager",
    ["ignore_pain"] = "Ignore Pain",
    ["demoralizing_shout"] = "Demoralizing Shout",
    ["avatar"] = "Avatar",
    ["charge"] = "Charge",
    ["whirlwind"] = "Whirlwind",
    ["cleave"] = "Cleave",
    ["heroic_strike"] = "Heroic Strike",
    ["pummel"] = "Pummel",
    ["spell_reflection"] = "Spell Reflection",
    ["intervene"] = "Intervene",
    ["taunt"] = "Taunt",
    ["last_stand"] = "Last Stand",
    ["shield_wall"] = "Shield Wall",
    ["berserker_rage"] = "Berserker Rage",
    ["victory_rush"] = "Victory Rush",
    ["impending_victory"] = "Impending Victory",
    ["storm_bolt"] = "Storm Bolt",
    ["shockwave"] = "Shockwave",
    ["intimidating_shout"] = "Intimidating Shout",
    -- Paladin (Protection/Holy/Ret)
    ["crusader_strike"] = "Crusader Strike",
    ["judgment"] = "Judgment",
    ["divine_storm"] = "Divine Storm",
    ["templars_verdict"] = "Templar's Verdict",
    ["blade_of_justice"] = "Blade of Justice",
    ["consecration"] = "Consecration",
    ["hammer_of_wrath"] = "Hammer of Wrath",
    ["wake_of_ashes"] = "Wake of Ashes",
    ["final_reckoning"] = "Final Reckoning",
    ["shield_of_the_righteous"] = "Shield of the Righteous",
    ["avengers_shield"] = "Avenger's Shield",
    ["holy_power"] = "Holy Power",
    ["ardent_defender"] = "Ardent Defender",
    ["divine_shield"] = "Divine Shield",
    ["lay_on_hands"] = "Lay on Hands",
    ["blessing_of_protection"] = "Blessing of Protection",
    ["blessing_of_freedom"] = "Blessing of Freedom",
    ["blessing_of_sacrifice"] = "Blessing of Sacrifice",
    ["hand_of_reckoning"] = "Hand of Reckoning",
    ["rebuke"] = "Rebuke",
    ["hammer_of_justice"] = "Hammer of Justice",
    ["turn_evil"] = "Turn Evil",
    ["divine_toll"] = "Divine Toll",
    ["ashen_hallow"] = "Ashen Hallow",
    ["vanquishers_hammer"] = "Vanquisher's Hammer",
    -- Hunter
    ["kill_command"] = "Kill Command",
    ["cobra_shot"] = "Cobra Shot",
    ["steady_shot"] = "Steady Shot",
    ["arcane_shot"] = "Arcane Shot",
    ["multi_shot"] = "Multi-Shot",
    ["barbed_shot"] = "Barbed Shot",
    ["wildfire_bomb"] = "Wildfire Bomb",
    ["chakrams"] = "Chakrams",
    ["flayed_shot"] = "Flayed Shot",
    -- Rogue
    ["sinister_strike"] = "Sinister Strike",
    ["backstab"] = "Backstab",
    ["eviscerate"] = "Eviscerate",
    ["rupture"] = "Rupture",
    ["slice_and_dice"] = "Slice and Dice",
    ["shadowstrike"] = "Shadowstrike",
    ["shuriken_storm"] = "Shuriken Storm",
    ["gloomblade"] = "Gloomblade",
    ["black_powder"] = "Black Powder",
    ["flagellation"] = "Flagellation",
    -- Priest
    ["mind_blast"] = "Mind Blast",
    ["shadow_word_pain"] = "Shadow Word: Pain",
    ["vampiric_touch"] = "Vampiric Touch",
    ["mind_flay"] = "Mind Flay",
    ["devouring_plague"] = "Devouring Plague",
    ["power_word_shield"] = "Power Word: Shield",
    ["penance"] = "Penance",
    ["holy_fire"] = "Holy Fire",
    ["smite"] = "Smite",
    -- Death Knight
    ["death_strike"] = "Death Strike",
    ["heart_strike"] = "Heart Strike",
    ["death_coil"] = "Death Coil",
    ["scourge_strike"] = "Scourge Strike",
    ["festering_strike"] = "Festering Strike",
    ["obliterate"] = "Obliterate",
    ["howling_blast"] = "Howling Blast",
    ["remorseless_winter"] = "Remorseless Winter",
    -- Shaman
    ["lava_burst"] = "Lava Burst",
    ["flame_shock"] = "Flame Shock",
    ["lightning_bolt"] = "Lightning Bolt",
    ["chain_lightning"] = "Chain Lightning",
    ["stormstrike"] = "Stormstrike",
    ["lava_lash"] = "Lava Lash",
    ["earth_shock"] = "Earth Shock",
    ["frost_shock"] = "Frost Shock",
    ["primordial_wave"] = "Primordial Wave",
    -- Mage
    ["fireball"] = "Fireball",
    ["pyroblast"] = "Pyroblast",
    ["fire_blast"] = "Fire Blast",
    ["living_bomb"] = "Living Bomb",
    ["combustion"] = "Combustion",
    ["frostbolt"] = "Frostbolt",
    ["ice_lance"] = "Ice Lance",
    ["flurry"] = "Flurry",
    ["arcane_blast"] = "Arcane Blast",
    ["arcane_missiles"] = "Arcane Missiles",
    ["arcane_barrage"] = "Arcane Barrage",
    -- Warlock
    ["shadow_bolt"] = "Shadow Bolt",
    ["incinerate"] = "Incinerate",
    ["chaos_bolt"] = "Chaos Bolt",
    ["immolate"] = "Immolate",
    ["corruption"] = "Corruption",
    ["agony"] = "Agony",
    ["unstable_affliction"] = "Unstable Affliction",
    ["drain_life"] = "Drain Life",
    ["summon_demonic_tyrant"] = "Summon Demonic Tyrant",
    -- Monk
    ["rising_sun_kick"] = "Rising Sun Kick",
    ["fists_of_fury"] = "Fists of Fury",
    ["blackout_kick"] = "Blackout Kick",
    ["tiger_palm"] = "Tiger Palm",
    ["spinning_crane_kick"] = "Spinning Crane Kick",
    ["touch_of_death"] = "Touch of Death",
    ["whirling_dragon_punch"] = "Whirling Dragon Punch",
    -- Druid
    ["shred"] = "Shred",
    ["rake"] = "Rake",
    ["rip"] = "Rip",
    ["ferocious_bite"] = "Ferocious Bite",
    ["thrash"] = "Thrash",
    ["swipe"] = "Swipe",
    ["moonfire"] = "Moonfire",
    ["sunfire"] = "Sunfire",
    ["starsurge"] = "Starsurge",
    ["wrath"] = "Wrath",
    ["starfire"] = "Starfire",
    -- Demon Hunter
    ["demons_bite"] = "Demon's Bite",
    ["chaos_strike"] = "Chaos Strike",
    ["annihilation"] = "Annihilation",
    ["immolation_aura"] = "Immolation Aura",
    ["eye_beam"] = "Eye Beam",
    ["blade_dance"] = "Blade Dance",
    ["death_sweep"] = "Death Sweep",
    ["fel_rush"] = "Fel Rush",
    ["throw_glaive"] = "Throw Glaive",
    -- Evoker
    ["disintegrate"] = "Disintegrate",
    ["fire_breath"] = "Fire Breath",
    ["eternity_surge"] = "Eternity Surge",
    ["azure_strike"] = "Azure Strike",
    ["living_flame"] = "Living Flame",
    ["spiritbloom"] = "Spiritbloom",
    ["emerald_blossom"] = "Emerald Blossom",
}

local SIMC_BUFF_MAP = {
    -- Warrior
    shield_block = "Shield Block",
    avatar = "Avatar",
    ignore_pain = "Ignore Pain",
    phalanx = "Phalanx",
    shield_wall = "Shield Wall",
    ravager = "Ravager",
    revenge = "Revenge Proc",
    demoralizing_shout_debuff = "Demoralizing Shout",
    devastating_focus = "Devastating Focus",
    violent_outburst = "Violent Outburst",
    seeing_red = "Seeing Red",
    -- Paladin
    shield_of_the_righteous = "Shield of the Righteous",
    avengers_shield = "Avenger's Shield",
    divine_shield = "Divine Shield",
    ardent_defender = "Ardent Defender",
    blessing_of_protection = "Blessing of Protection",
    blessing_of_freedom = "Blessing of Freedom",
    blessing_of_sacrifice = "Blessing of Sacrifice",
    divine_toll = "Divine Toll",
    ashen_hallow = "Ashen Hallow",
}

local function SimCName(name)
    return SIMC_SPELL_MAP[name] or SIMC_BUFF_MAP[name] or name:gsub("_", " "):gsub("(%l)(%w*)", function(a,b) return a:upper()..b end)
end

function Addon.ParseSimC(text)
    if not text or text == "" then return nil end

    local dps = tonumber(text:match("DPS=([%d%.]+)")) or 0
    local maxTime = tonumber(text:match("max_time=(%d+)")) or 120
    local duration = maxTime
    local totalDamage = dps * duration

    local damageData = {}
    local castCounts = {}
    local totalCasts = 0
    local simcBuffs = {}
    local spellWeights = {}
    local buffBenefit = {}
    local rageGains = {}
    local rawApl = ""
    local activeBranch = ""
    local inActions = false
    local inBuffs = false
    local inAPL = false
    local currentBranch = ""
    local inDefaultBranch = false

    for line in text:gmatch("[^\r\n]+") do
        local isSectionHeader = false
        if line:find("^%s*Actions:") then
            inActions = true; inBuffs = false; inAPL = false; isSectionHeader = true
            if Addon.debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Entered Actions section") end
        elseif line:find("^%s*Priorities %(actions%.default%)") then
            inActions = false; inBuffs = false; inAPL = true
            currentBranch = "default"
            inDefaultBranch = true; isSectionHeader = true
            if Addon.debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Entered Priorities (default)") end
        elseif line:find("^%s*Priorities %(actions%.") then
            inActions = false; inBuffs = false; inAPL = true
            local branch = line:match("actions%.([%w_]+)%)")
            currentBranch = branch or ""
            inDefaultBranch = false; isSectionHeader = true
            if Addon.debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Entered Priorities (actions." .. (branch or "?") .. ")") end
        elseif line:find("^%s*Dynamic Buffs:") then
            inActions = false; inBuffs = true; inAPL = false; isSectionHeader = true
            if Addon.debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Entered Buffs section") end
        elseif line:find("^%s*Gains:") then
            inActions = false; inBuffs = false; inAPL = false; isSectionHeader = true
            if Addon.debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Entered Gains section") end
        elseif line:find("^%s*Up%-Times:") or line:find("^%s*Queue:") or line:find("^%s*Player:") or line:find("^%s*Snapshot Stats:") then
            inAPL = false; isSectionHeader = true
        end

        if not isSectionHeader then

        -- Parse Actions
        if inActions then
            local rawName = line:match("^%s+(.-)%s*Count=")
            if rawName then
                local count = tonumber(line:match("Count=%s*([%d%.]+)"))
                local pct = tonumber(line:match("|%s*([%d%.]+)%%"))
                if Addon.debugMode then
                    local linePreview = #line > 120 and line:sub(1, 120) .. "..." or line
                    print(string.format("|cff33ff33[DummyAnalyzer Debug]|r Action: %s | count=%s pct=%s", tostring(rawName), tostring(count), tostring(pct)))
                end
                if count and count > 0 then
                    local display = SimCName(rawName)
                    count = math.floor(count + 0.5)
                    totalCasts = totalCasts + count
                    if castCounts[display] then castCounts[display] = castCounts[display] + count
                    else castCounts[display] = count end
                    DebugLog("debug", "ParseSimC", string.format("include count=%d: %s→%s", count, rawName, display))
                    if pct and pct > 0 then
                        local total = totalDamage * (pct / 100)
                        if damageData[display] then damageData[display] = {total = damageData[display].total + total}
                        else damageData[display] = {total = total} end
                    end
                else
                    DebugLog("debug", "ParseSimC", string.format("skip count=%s: %s→%s", tostring(count), rawName, SimCName(rawName)))
                end
                -- pDPS per spell
                local pdps = tonumber(line:match("pDPS=%s*([%d%.]+)"))
                if pdps and pdps > 0 then
                    local display = SimCName(rawName)
                    spellWeights[display] = pdps
                end
            end
        end

        -- Parse Priorities (APL)
        if inAPL then
            -- Strip action branch prefix: actions.branch+=/spell → spell
            local apline = line:match("^%s*actions%.[%w_]+%+?=?/?(.*)") or line
            -- Parse spell name from APL line (first word before ,if= or similar)
            local spellName = apline:match("^%s*([%w_]+)")
            if spellName and spellName ~= "run_action_list" and spellName ~= "" then
                if inDefaultBranch then
                    -- Default branch: could be run_action_list dispatcher or actual spell
                    local branchName = line:match("run_action_list,name=([%w_]+)")
                    if branchName then
                        activeBranch = branchName
                    else
                        -- No dispatcher, parse as direct spell in default branch
                        local display = SimCName(spellName)
                        if display and not Addon.ROTATION_EXCLUDE[display] then
                            rawApl = rawApl .. apline .. "\n"
                        end
                    end
                elseif currentBranch ~= "" and currentBranch ~= "default" then
                    -- Named branch: check if this is the active one
                    if currentBranch == activeBranch or activeBranch == "" then
                        local display = SimCName(spellName)
                        if display and not Addon.ROTATION_EXCLUDE[display] then
                            rawApl = rawApl .. apline .. "\n"
                        end
                    end
                end
            end
        end

        -- Parse Dynamic Buffs (uptime + benefit)
        if inBuffs then
            local rawName = line:match("^%s*(%S+)")
            local uptime = tonumber(line:match("uptime=%s*([%d%.]+)"))
            if rawName and uptime then
                local display = SimCName(rawName)
                simcBuffs[display] = {name = display, uptime = (uptime / 100) * duration}
                local benefit = tonumber(line:match("benefit=%s*([%d%.]+)"))
                if benefit then buffBenefit[display] = benefit end
                if Addon.debugMode then print(string.format("|cff33ff33[DummyAnalyzer Debug]|r Buff: %s uptime=%s benefit=%s", tostring(display), tostring(uptime), tostring(benefit or 0))) end
            end
        end

        end -- if not isSectionHeader

        -- Parse Gains
        local gainAmount, gainSource = line:match("%s*([%d%.]+)%s*:%s*(.+)%s*%((.+)%)")
        if gainAmount and gainSource then
            local gainName = SimCName(gainSource:match("^%s*(.-)%s*$") or gainSource)
            local amt = tonumber(gainAmount)
            if gainName and amt then
                rageGains[gainName] = (rageGains[gainName] or 0) + amt
            end
        end
    end

    -- Build APL order from rawApl
    local aplOrder = {}
    if rawApl and rawApl ~= "" then
        for line in rawApl:gmatch("[^\r\n]+") do
            -- Split on '/' to handle multi-action lines (SimC format: ravager/demoralizing_shout)
            for action in line:gmatch("([^/]+)") do
                local spellName = action:match("^%s*([%w_]+)")
                if spellName then
                    local display = SimCName(spellName)
                    if display and not Addon.ROTATION_EXCLUDE[display] and castCounts[display] then
                        local already = false
                        for _, s in ipairs(aplOrder) do if s == display then already = true; break end end
                        if not already then table.insert(aplOrder, display) end
                    end
                end
            end
        end
    end

    -- Parse player stats (haste, crit, etc.)
    local haste = tonumber(text:match("haste=([%d%.]+)")) or 0
    local crit = tonumber(text:match("crit=([%d%.]+)")) or 0
    local spec = text:match("spec=([%w_]+)") or ""
    local heroTree = text:match("hero_tree=([%w_]+)") or ""

    if dps == 0 then return nil end

    return {
        dps = dps,
        duration = duration,
        totalDamage = totalDamage,
        damageData = damageData,
        castCounts = castCounts,
        totalCasts = totalCasts,
        buffs = simcBuffs,
        -- Extended SimC data
        spellWeights = spellWeights,
        aplOrder = aplOrder,
        rawApl = rawApl,
        activeBranch = activeBranch,
        buffBenefit = buffBenefit,
        rageGains = rageGains,
        haste = haste,
        crit = crit,
        spec = spec,
        heroTree = heroTree,
    }
end

local function ShowSimCImportDialog()
    if Addon.simcDialog then Addon.simcDialog:Hide() Addon.simcDialog = nil end

    Addon.simcDialog = CreateStyledFrame("Frame", "DummyAnalyzerSimCImport", UIParent); trackDialog(Addon.simcDialog)
    Addon.simcDialog:SetSize(600, 480)
    Addon.simcDialog:SetPoint("CENTER")
    Addon.simcDialog:SetFrameStrata("DIALOG")
    Addon.simcDialog:SetMovable(true)
    Addon.simcDialog:SetClampedToScreen(true)
    Addon.simcDialog:EnableMouse(true)
    Addon.simcDialog:RegisterForDrag("LeftButton")
    Addon.simcDialog:SetScript("OnDragStart", Addon.simcDialog.StartMoving)
    Addon.simcDialog:SetScript("OnDragStop", Addon.simcDialog.StopMovingOrSizing)
    ApplyBackdrop(Addon.simcDialog, false)

    local titleBar = CreateStyledFrame("Frame", nil, Addon.simcDialog)
    titleBar:SetPoint("TOPLEFT", Addon.simcDialog, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", Addon.simcDialog, "TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    titleBar:SetBackdropColor(C.title[1], C.title[2], C.title[3], C.title[4])
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() Addon.simcDialog:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() Addon.simcDialog:StopMovingOrSizing() end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    SafeSetFont(titleText, BOLD_FONT, 15)
    titleText:SetText("Import SimC Output")
    titleText:SetPoint("CENTER")
    titleText:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])

    local closeBtn = CreateStyledFrame("Button", nil, titleBar)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -8, 0)
    closeBtn:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    closeBtn:SetBackdropColor(C.btn[1], C.btn[2], C.btn[3], C.btn[4])
    closeBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], C.border[4])
    local closeX = closeBtn:CreateFontString(nil, "OVERLAY")
    SafeSetFont(closeX, BOLD_FONT, 16)
    closeX:SetText("X")
    closeX:SetPoint("CENTER")
    closeX:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], C.textMuted[4])
    closeBtn:SetScript("OnEnter", function()
        closeX:SetTextColor(C.textHl[1], C.textHl[2], C.textHl[3], C.textHl[4])
    end)
    closeBtn:SetScript("OnLeave", function()
        closeX:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], C.textMuted[4])
    end)
    closeBtn:SetScript("OnClick", function() Addon.simcDialog:Hide() end)

    local instrText = Addon.simcDialog:CreateFontString(nil, "OVERLAY")
    SafeSetFont(instrText, MAIN_FONT, 11)
    instrText:SetText("Paste SimC output below (Ctrl+V) then click Import:")
    instrText:SetPoint("TOPLEFT", Addon.simcDialog, "TOPLEFT", 20, -50)
    instrText:SetTextColor(C.text[1], C.text[2], C.text[3], C.text[4])

    local statusText = Addon.simcDialog:CreateFontString(nil, "OVERLAY")
    SafeSetFont(statusText, MAIN_FONT, 11)
    statusText:SetText("")
    statusText:SetPoint("TOPLEFT", Addon.simcDialog, "TOPLEFT", 20, -65)
    statusText:SetTextColor(0.5, 1.0, 0.5, 1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, Addon.simcDialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", Addon.simcDialog, "TOPLEFT", 22, -87)
    scrollFrame:SetPoint("BOTTOMRIGHT", Addon.simcDialog, "BOTTOMRIGHT", -22, 50)
    scrollFrame:SetClipsChildren(true)
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetWidth(510)
    editBox:SetHeight(400)
    editBox:SetAutoFocus(true)
    editBox:EnableMouse(true)
    scrollFrame:SetScript("OnMouseDown", function() editBox:SetFocus() end)
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
    editBox:SetScript("OnEditFocusGained", function()
        statusText:SetTextColor(0.5, 1.0, 0.5, 1)
        statusText:SetText("Paste SimC output (Ctrl+V) then click Import")
    end)
    editBox:SetScript("OnEditFocusLost", function()
        if editBox and #(editBox:GetText() or "") == 0 then
            statusText:SetText("")
        end
    end)
    editBox:SetScript("OnTextChanged", function()
        local text = editBox:GetText() or ""
        local len = #text
        if len > 0 then
            local lines = select(2, text:gsub("\n", "\n")) + 1
            statusText:SetText(string.format("Pasted: %d chars (%d lines). Click Import.", len, lines))
        end
    end)
    scrollFrame:SetScrollChild(editBox)
    editBox:SetHeight(300)

    local function doImport()
        local text = editBox:GetText() or ""
        if Addon.debugMode then
            print(string.format("|cff33ff33[DummyAnalyzer Debug]|r Import text: %d chars total", #text))
            if #text > 0 then
                print("|cff33ff33[DummyAnalyzer Debug]|r First 200 chars: " .. text:sub(1, 200))
                print("|cff33ff33[DummyAnalyzer Debug]|r Last 200 chars: " .. text:sub(-200))
            end
        end
        if not text or text == "" then
            print("|cff33ff33[DummyAnalyzer]|r Paste SimC output first.")
            return
        end
        local parsed = Addon.ParseSimC(text)
        if not parsed then
            print("|cff33ff33[DummyAnalyzer]|r Could not parse SimC output. Make sure you pasted the full text from the Actions section onwards.")
            return
        end
        -- Filter SimC data to only include spells DummyAnalyzer can track
        -- (removes procs, passives, auto-attacks that don't show in the combat log as casts)
        parsed.castCounts, parsed.damageData = FilterSimCData(parsed.castCounts, parsed.damageData)
        local db = GetCharDB()
        local label = "SimC: " .. string.format("%.0fK DPS", parsed.dps / 1000)
        -- Store extended SimC data for optimizer access
        db.simcData = {
            totalDPS = parsed.dps,
            activeBranch = parsed.activeBranch,
aplOrder = parsed.aplOrder,
              rawApl = parsed.rawApl,
              spellWeights = parsed.spellWeights,
              castCounts = parsed.castCounts,
              buffBenefit = parsed.buffBenefit,
            rageGains = parsed.rageGains,
            haste = parsed.haste,
            crit = parsed.crit,
            spec = parsed.spec,
            heroTree = parsed.heroTree,
        }
        local existingId = db.simcLogId or 0
        if existingId > 0 then
            for i, log in ipairs(db.logs) do
                if log.id == existingId then
                    log.label = label
                    log.dps = parsed.dps
                    log.duration = parsed.duration
                    log.totalDamage = parsed.totalDamage
                    log.damageData = parsed.damageData
                    log.castCounts = parsed.castCounts
                    log.totalCasts = parsed.totalCasts
                    log.buffUptime = parsed.buffs
                    log.date = "SimC Simulation"
                    log.isSimC = true
                    local upCount = 0
                    local upSample = ""
                    if parsed.damageData then
                        for _ in pairs(parsed.damageData) do upCount = upCount + 1 end
                        for name, d in pairs(parsed.damageData) do
                            upSample = upSample .. string.format(" %s=%.0f", name, d.total or 0)
                            if #upSample > 100 then break end
                        end
                    end
                    Addon.simcDialog:Hide()
                    print(string.format("|cff33ff33[DummyAnalyzer]|r Updated SimC reference: %s (%d dmg entries%s)", label, upCount, upCount > 0 and (":" .. upSample) or ""))
                    return
                end
            end
        end
        local newId = db.nextId
        db.nextId = newId + 1
        db.simcLogId = newId
        table.insert(db.logs, {
            id = newId,
            label = label,
            dps = parsed.dps,
            duration = parsed.duration,
            totalDamage = parsed.totalDamage,
            damageData = parsed.damageData,
            castCounts = parsed.castCounts,
            totalCasts = parsed.totalCasts,
            buffUptime = parsed.buffs,
            date = "SimC Simulation",
            isSimC = true,
        })
        local dmgCount = 0
        local dmgSample = ""
        if parsed.damageData then
            for _ in pairs(parsed.damageData) do dmgCount = dmgCount + 1 end
            for name, d in pairs(parsed.damageData) do
                dmgSample = dmgSample .. string.format(" %s=%.0f", name, d.total or 0)
                if #dmgSample > 100 then break end
            end
        end
        Addon.simcDialog:Hide()
        print(string.format("|cff33ff33[DummyAnalyzer]|r Imported SimC reference: %s (%d dmg entries%s)", label, dmgCount, dmgCount > 0 and (":" .. dmgSample) or ""))
    end

    local bottomBar = CreateStyledFrame("Frame", nil, Addon.simcDialog)
    bottomBar:SetPoint("BOTTOMLEFT", Addon.simcDialog, "BOTTOMLEFT", 0, 0)
    bottomBar:SetPoint("BOTTOMRIGHT", Addon.simcDialog, "BOTTOMRIGHT", 0, 0)
    bottomBar:SetHeight(45)
    bottomBar:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 0})
    bottomBar:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    bottomBar:SetFrameLevel(Addon.simcDialog:GetFrameLevel() + 5)

    local importBtn = CreateStyledButton(bottomBar, "Import", 100, 30, doImport, "primary")
    importBtn:SetPoint("RIGHT", bottomBar, "CENTER", -55, 0)
    importBtn:SetFrameLevel(bottomBar:GetFrameLevel() + 2)

    local cancelBtn = CreateStyledButton(bottomBar, "Cancel", 100, 30, function() Addon.simcDialog:Hide() end)
    cancelBtn:SetPoint("LEFT", bottomBar, "CENTER", 55, 0)
    cancelBtn:SetFrameLevel(bottomBar:GetFrameLevel() + 2)

    RegisterAddonWindow(Addon.simcDialog)
    Addon.simcDialog:Show()
    C_Timer.After(0, function() if editBox and editBox.SetFocus then editBox:SetFocus() end end)
end

-- ============================================
-- SIMCIMPORT EXPORTS (namespace promotion, rule A/B)
-- ============================================
Addon.ShowSimCImportDialog = ShowSimCImportDialog