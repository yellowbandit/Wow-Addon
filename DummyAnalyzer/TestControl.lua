local AddonName, Addon = ...
-- ============================================
-- TEST CONTROL
-- ============================================
local CreateStyledFrame = Addon.CreateStyledFrame
local ApplyBackdrop = Addon.ApplyBackdrop
local SafeSetFont = Addon.SafeSetFont
local trackDialog = Addon.trackDialog
local ShortNum = Addon.ShortNum
local ResetDamageData = Addon.ResetDamageData
local ReadDamageMeterData = Addon.ReadDamageMeterData
local ResetMeterCapture = Addon.ResetMeterCapture
local CaptureCombatSnapshot = Addon.CaptureCombatSnapshot
local ResetHealthFallback = Addon.ResetHealthFallback
local TrySeedHealthBaseline = Addon.TrySeedHealthBaseline
local ResetBuffTracking = Addon.ResetBuffTracking
local StartBuffTicker = Addon.StartBuffTicker
local FinalizeBuffTracking = Addon.FinalizeBuffTracking
local BOLD_FONT = Addon.BOLD_FONT
local MAIN_FONT = Addon.MAIN_FONT
local C = Addon.C
local IsSecretValue = Addon.IsSecretValue
local ShowReport = Addon.ShowReport

local reportRetryCount = 0
local MAX_REPORT_RETRIES = 8

local function FinalizeReport()
    Addon.pendingReport = false
    ResetDamageData()
    ReadDamageMeterData()
    if Addon.totalDamage == 0 and Addon.healthTotal > 0 then
        Addon.totalDamage = Addon.healthTotal
        Addon.damageFromHealthFallback = true
        if Addon.debugMode then
            print("|cff33ff33[DummyAnalyzer Debug]|r Damage meter empty, using target-health fallback: " .. ShortNum(Addon.totalDamage))
        end
    end
    if Addon.totalDamage == 0 and reportRetryCount < MAX_REPORT_RETRIES then
        reportRetryCount = reportRetryCount + 1
        if Addon.debugMode then
            print("|cff33ff33[DummyAnalyzer Debug]|r Damage read empty, retrying (" .. reportRetryCount .. "/" .. MAX_REPORT_RETRIES .. ")...")
        end
        C_Timer.After(0.5, FinalizeReport)
        return
    end
    reportRetryCount = 0
    ShowReport()
end

local function QueueReportAfterCombat()
    Addon.pendingReport = true
    if InCombatLockdown and InCombatLockdown() then
        print("|cff33ff33[DummyAnalyzer]|r Test complete. Waiting until combat ends to build damage report...")
        if Addon.reportWaitTicker then
            Addon.reportWaitTicker:Cancel()
            Addon.reportWaitTicker = nil
        end
        Addon.reportWaitTicker = C_Timer.NewTicker(0.5, function(ticker)
            if not InCombatLockdown or not InCombatLockdown() then
                ticker:Cancel()
                Addon.reportWaitTicker = nil
                if Addon.pendingReport then
                    C_Timer.After(0.5, FinalizeReport)
                end
            end
        end)
    else
        C_Timer.After(0.5, FinalizeReport)
    end
end

-- ============================================
-- PRACTICE OVERLAY
-- Live DPS / APM / longest-idle / letter grade shown under the countdown while
-- a test is active. Values refresh on the same 0.5s cadence as PollTestMetrics,
-- are frozen for a few seconds when the test ends, then the frame hides as
-- before. All reads are pcall / IsSecretValue guarded for 12.x secret safety.
-- ============================================
local OVERLAY_FROZEN_SECONDS = 3.5
local overlayHideToken = 0

local OVERLAY_GRADE_COLORS = {
    A = {0.20, 1.00, 0.20},
    B = {0.55, 1.00, 0.30},
    C = {1.00, 0.84, 0.00},
    D = {1.00, 0.55, 0.15},
    F = {1.00, 0.30, 0.30},
}

local function OverlaySetVisible(visible)
    if not Addon.timerFrame then return end
    local parts = {Addon.timerDps, Addon.timerApm, Addon.timerIdle, Addon.timerGrade}
    for i = 1, #parts do
        local fs = parts[i]
        if fs then
            if visible then fs:Show() else fs:Hide() end
        end
    end
    Addon.timerFrame:SetHeight(visible and 84 or 50)
end

-- Longest gap between consecutive cast timestamps, ignoring gaps under 0.3s.
local function OverlayLongestIdleGap(history)
    local maxGap = 0
    local prev = nil
    if type(history) == "table" then
        for i = 1, #history do
            local entry = history[i]
            local t = entry and entry.time
            if type(t) == "number" then
                if prev then
                    local gap = t - prev
                    if gap >= 0.3 and gap > maxGap then maxGap = gap end
                end
                prev = t
            end
        end
    end
    return maxGap
end

-- Simple letter grade from APM + longest idle gap (0..6 points -> A..F).
local function OverlayGrade(apm, idle)
    local apmPts = apm >= 50 and 3 or apm >= 35 and 2 or apm >= 20 and 1 or 0
    local idlePts = idle < 1.0 and 3 or idle < 2.0 and 2 or idle < 4.0 and 1 or 0
    local total = apmPts + idlePts
    if total >= 6 then return "A" end
    if total == 5 then return "B" end
    if total == 4 then return "C" end
    if total == 3 then return "D" end
    return "F"
end

local function OverlaySafeNumber(v)
    if type(v) ~= "number" or IsSecretValue(v) then return 0 end
    return v
end

-- final=true uses the frozen test end time (called from StopTest).
local function RefreshPracticeOverlay(final)
    if not Addon.timerFrame or not Addon.timerDps then return end
    pcall(function()
        local ref = final and (Addon.testEndTime or GetTime()) or GetTime()
        local elapsed = ref - (Addon.startTime or ref)
        if elapsed <= 0.05 then elapsed = 0.05 end

        -- Live DPS. In combat the meter's totalAmount/amountPerSecond are SECRET;
        -- computing on them (arithmetic/compare/boolean-test) taints execution and
        -- yields 0 - which is exactly why the old computed path showed "DPS 0".
        -- Instead we pass the value STRAIGHT into the FontString via
        -- AbbreviateNumbers (Blizzard display passthrough), the same technique
        -- EllesmereUIDamageMeters uses to keep its bars live mid-fight.
        local dpsText
        if InCombatLockdown and InCombatLockdown() then
            dpsText = "\226\128\148" -- em dash; only overwritten when the meter has a value
            local src
            if Addon.GetLivePlayerMeterSource then
                local okSrc, s = pcall(Addon.GetLivePlayerMeterSource)
                if okSrc then src = s end
            end
            if src then
                -- Never branch on the (possibly secret) value - only on pcall's
                -- boolean. Pass the raw secret straight to the formatter.
                local okA, a = pcall(AbbreviateNumbers, src.amountPerSecond)
                if okA then
                    dpsText = a
                else
                    local okT, t = pcall(AbbreviateNumbers, src.totalAmount)
                    if okT then dpsText = t end
                end
            end
        else
            local snapTotal = 0
            if Addon.GetCombatSnapTotal then
                local okS, snap = pcall(Addon.GetCombatSnapTotal)
                if okS then snapTotal = OverlaySafeNumber(snap) end
            end
            local total = snapTotal
            if total <= 0 then total = OverlaySafeNumber(Addon.healthTotal) end
            dpsText = ShortNum(total / elapsed)
        end

        if not Addon.overlaySamples then Addon.overlaySamples = {} end
        table.insert(Addon.overlaySamples, { t = elapsed })
        if #Addon.overlaySamples > 40 then table.remove(Addon.overlaySamples, 1) end
        local casts = 0
        if type(Addon.spellHistory) == "table" then casts = #Addon.spellHistory end
        local apm = (casts / elapsed) * 60
        local idle = OverlayLongestIdleGap(Addon.spellHistory)

        Addon.timerDps:SetText(dpsText)
        Addon.timerApm:SetText(string.format("APM %d", math.floor(apm + 0.5)))
        Addon.timerIdle:SetText(string.format("Idle %.1fs", idle))
        local grade = OverlayGrade(apm, idle)
        Addon.timerGrade:SetText(grade)
        local col = OVERLAY_GRADE_COLORS[grade] or OVERLAY_GRADE_COLORS.F
        Addon.timerGrade:SetTextColor(col[1], col[2], col[3], 1)
    end)
end

-- Freeze window: hide the frame after `delay` unless a new test has started.
local function ScheduleOverlayHide(delay)
    overlayHideToken = overlayHideToken + 1
    local token = overlayHideToken
    C_Timer.After(delay, function()
        if token ~= overlayHideToken then return end
        if Addon.testActive then return end
        OverlaySetVisible(false)
        if Addon.timerFrame then Addon.timerFrame:Hide() end
    end)
end

local function CreateTimerFrame()
    if not Addon.timerFrame then
        Addon.timerFrame = CreateStyledFrame("Frame", nil, UIParent); trackDialog(Addon.timerFrame)
        Addon.timerFrame:SetSize(240, 70)
        Addon.timerFrame:SetPoint("TOP", UIParent, "TOP", 0, -100)
        Addon.timerFrame:SetFrameStrata("TOOLTIP")
        ApplyBackdrop(Addon.timerFrame, true)
        Addon.timerFrame:EnableMouse(true)
        Addon.timerFrame:RegisterForDrag("LeftButton")
        Addon.timerFrame:SetScript("OnDragStart", Addon.timerFrame.StartMoving)
        Addon.timerFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            -- Keep the overlay on screen after a drag (clamped to UIParent).
            local point, relTo, relPoint, xOfs, yOfs = self:GetPoint(1)
            if relTo == UIParent and relPoint == "CENTER" then
                local halfW = UIParent:GetWidth() / 2 - self:GetWidth() / 2
                local halfH = UIParent:GetHeight() / 2 - self:GetHeight() / 2
                local nx = math.max(-halfW, math.min(halfW, xOfs or 0))
                local ny = math.max(-halfH, math.min(halfH, yOfs or 0))
                if nx ~= xOfs or ny ~= yOfs then
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", UIParent, "CENTER", nx, ny)
                end
            end
        end)

        Addon.timerText = Addon.timerFrame:CreateFontString(nil, "OVERLAY")
        SafeSetFont(Addon.timerText, BOLD_FONT, 20)
        Addon.timerText:SetPoint("TOP", Addon.timerFrame, "TOP", 0, -5)

        -- Practice Overlay children (hidden unless a test is active).
        -- The "DPS" label is a SEPARATE static fontstring so the value fontstring
        -- can receive a secret meter string directly (never concatenate a secret).
        Addon.timerDpsLabel = Addon.timerFrame:CreateFontString(nil, "OVERLAY")
        SafeSetFont(Addon.timerDpsLabel, BOLD_FONT, 14)
        Addon.timerDpsLabel:SetPoint("TOPLEFT", Addon.timerFrame, "TOPLEFT", 12, -32)
        Addon.timerDpsLabel:SetJustifyH("LEFT")
        Addon.timerDpsLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
        Addon.timerDpsLabel:SetText("DPS")

        Addon.timerDps = Addon.timerFrame:CreateFontString(nil, "OVERLAY")
        SafeSetFont(Addon.timerDps, MAIN_FONT, 14)
        Addon.timerDps:SetPoint("TOPLEFT", Addon.timerDpsLabel, "TOPLEFT", 44, 0)
        Addon.timerDps:SetJustifyH("LEFT")
        Addon.timerDps:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        Addon.timerDps:SetText("\226\128\148")

        Addon.timerApm = Addon.timerFrame:CreateFontString(nil, "OVERLAY")
        SafeSetFont(Addon.timerApm, MAIN_FONT, 14)
        Addon.timerApm:SetPoint("TOPRIGHT", Addon.timerFrame, "TOPRIGHT", -12, -32)
        Addon.timerApm:SetJustifyH("RIGHT")
        Addon.timerApm:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        Addon.timerApm:SetText("APM 0")

        Addon.timerIdle = Addon.timerFrame:CreateFontString(nil, "OVERLAY")
        SafeSetFont(Addon.timerIdle, MAIN_FONT, 14)
        Addon.timerIdle:SetPoint("TOPLEFT", Addon.timerFrame, "TOPLEFT", 12, -52)
        Addon.timerIdle:SetJustifyH("LEFT")
        Addon.timerIdle:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
        Addon.timerIdle:SetText("Idle 0.0s")

        Addon.timerGrade = Addon.timerFrame:CreateFontString(nil, "OVERLAY")
        SafeSetFont(Addon.timerGrade, BOLD_FONT, 20)
        Addon.timerGrade:SetPoint("TOPRIGHT", Addon.timerFrame, "TOPRIGHT", -12, -48)
        Addon.timerGrade:SetJustifyH("RIGHT")
        Addon.timerGrade:SetText("")

    end
    OverlaySetVisible(false)
    Addon.timerFrame:Show()
end

local function StopTest()
    local wasArmed = Addon.armedTest
    Addon.armedTest = false
    Addon.armedMinutes = nil
    if Addon.combatWaitTicker then
        Addon.combatWaitTicker:Cancel()
        Addon.combatWaitTicker = nil
    end
    if wasArmed and not Addon.testActive then
        if Addon.practiceTicker then Addon.practiceTicker:Cancel() Addon.practiceTicker = nil end
        OverlaySetVisible(false)
        if Addon.timerFrame then Addon.timerFrame:Hide() end
        print("|cff33ff33[DummyAnalyzer]|r Armed test canceled.")
        return
    end
    if not Addon.testActive and Addon.pendingReport then return end
    FinalizeBuffTracking()
    Addon.testEndTime = GetTime()
    Addon.testActive = false
    if Addon.updateFrame then Addon.updateFrame:SetScript("OnUpdate", nil) end
    if Addon.practiceTicker then Addon.practiceTicker:Cancel() Addon.practiceTicker = nil end
    -- Practice Overlay: freeze the final numbers so the player can glance at them.
    RefreshPracticeOverlay(true)
    ScheduleOverlayHide(OVERLAY_FROZEN_SECONDS)

    if Addon.debugMode then print("|cff33ff33[DummyAnalyzer Debug]|r Timer finished - queueing report...") end
    QueueReportAfterCombat()
end

local function BeginActiveTest(minutes)
    Addon.currentDuration = minutes * 60
    Addon.spellHistory = {}
    ResetDamageData()
    ResetHealthFallback()
    TrySeedHealthBaseline()
    ResetBuffTracking()
    Addon.testActive = true
    Addon.startTime = GetTime()
    Addon.testEndTime = nil
    -- Seed the in-combat meter capture baseline at test start so later deltas
    -- only count damage dealt after this moment.
    ResetMeterCapture()
    CaptureCombatSnapshot(true)
    -- Snapshot which GRIP-EMS sequence is active at test start. Sourced from the public
    -- SEQUENCE_STEP_ADVANCED event (see Ems_RegisterEvents), not from Engine internals.
    Addon.testStartSequence = Addon.lastActiveSequence
    StartBuffTicker()
    local minuteText = minutes == 0.5 and "30 sec" or (minutes .. " min")
    print(string.format("|cff33ff33[DummyAnalyzer]|r Test started: %s", minuteText))

    CreateTimerFrame()
    -- Practice Overlay: show live stats, refresh on the buff-ticker cadence.
    overlayHideToken = overlayHideToken + 1  -- cancel any pending freeze-hide
    Addon.overlayBaseDamage = Addon.GetLiveDamageTotal and Addon.GetLiveDamageTotal() or 0
    OverlaySetVisible(true)
    RefreshPracticeOverlay(false)
    if Addon.practiceTicker then Addon.practiceTicker:Cancel() end
    Addon.practiceTicker = C_Timer.NewTicker(0.5, function() RefreshPracticeOverlay(false) end)

    if Addon.updateFrame then Addon.updateFrame:SetScript("OnUpdate", nil) end
    Addon.updateFrame:SetScript("OnUpdate", function()
        if not Addon.testActive then return end
        local elapsed = GetTime() - Addon.startTime
        local remaining = Addon.currentDuration - elapsed
        if remaining <= 0 then StopTest() return end
        local mins = math.floor(remaining / 60)
        local secs = remaining % 60
        if Addon.currentDuration == 30 then
            Addon.timerText:SetText(string.format("%d sec", math.floor(remaining)))
        else
            Addon.timerText:SetText(string.format("%02d:%02d", mins, secs))
        end
    end)
end

local function StartTest(minutes)
    if Addon.testActive then StopTest() end
    if Addon.combatWaitTicker then
        Addon.combatWaitTicker:Cancel()
        Addon.combatWaitTicker = nil
    end

    Addon.armedTest = true
    Addon.armedMinutes = minutes
    local minuteText = minutes == 0.5 and "30 sec" or (minutes .. " min")
    print(string.format("|cff33ff33[DummyAnalyzer]|r Armed: %s test. Timer starts when you enter combat.", minuteText))
    CreateTimerFrame()
    overlayHideToken = overlayHideToken + 1  -- cancel a pending overlay freeze-hide
    Addon.timerText:SetText("Waiting for combat")

    Addon.combatWaitTicker = C_Timer.NewTicker(0.2, function(ticker)
        pcall(TrySeedHealthBaseline)
        if not Addon.armedTest then
            ticker:Cancel()
            Addon.combatWaitTicker = nil
            return
        end
        if InCombatLockdown and InCombatLockdown() then
            ticker:Cancel()
            Addon.combatWaitTicker = nil
            Addon.armedTest = false
            BeginActiveTest(Addon.armedMinutes or minutes)
        end
    end)
end

-- ============================================
-- TEST CONTROL EXPORTS (namespace promotion, rule A/B)
-- ============================================
Addon.StartTest = StartTest
Addon.StopTest = StopTest
Addon.CreateTimerFrame = CreateTimerFrame