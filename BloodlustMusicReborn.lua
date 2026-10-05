-- BloodlustMusicReborn
local addonName, addon = ...

-- Default configuration
local defaults = {
    enabled = true,
    debug = false,
    channel = "Master"
}

-- Dialog is muted wholesale by the "Enable Dialog" sound option (confirmed via
-- testing - it silences addon-triggered Dialog-channel sounds too, not just NPC
-- voice lines), so it's a bad default. Master has no such on/off toggle, only an
-- overall slider, making it the least likely to go silently muted.
local CHANNEL_ALIASES = {
    master = "Master",
    music = "Music",
    sfx = "SFX",
    ambience = "Ambience",
    dialog = "Dialog",
}

local activeAuraSoundIDs = {}

-- Tracking the buff spell IDs directly triggers a confirmed AddAuraSound engine
-- bug where the "Added" trigger fires twice a few seconds apart (reproduced with
-- a clean, isolated registration; not stale state). The paired lockout debuffs
-- these effects also apply do not exhibit the bug, so we track those instead.
-- Sated (57724) covers Bloodlust, Primal Rage, and Harrier's Cry, which all share it.
local BLOODLUST_LOCKOUT_SPELL_IDS = {
    [57724]  = true,  -- Sated (after Bloodlust / Primal Rage / Harrier's Cry)
    [57723]  = true,  -- Exhaustion (after Heroism)
    [80354]  = true,  -- Temporal Displacement (after Time Warp)
    [95809]  = true,  -- Insanity (after Ancient Hysteria, removed but harmless to keep)
    [160455] = true,  -- Fatigued (after Netherwinds, removed but harmless to keep)
    [390435] = true,  -- Exhaustion (after Fury of the Aspects)
}

local function DebugPrint(msg)
    if BloodlustMusicRebornDB.debug then
        print("|cFFFFFF00[BLMR Debug]|r " .. msg)
    end
end

local displayFrame
local eventLog = {}
local lastRegistration = { file = nil, time = nil, results = {} }

local function LogEvent(msg)
    table.insert(eventLog, 1, ("|cFF808080%s|r %s"):format(date("%H:%M:%S"), msg))
    while #eventLog > 8 do
        table.remove(eventLog)
    end
end

local function UpdateDisplay()
    if not displayFrame or not displayFrame:IsShown() then return end

    local lines = { "|cFF00FF00BLMR Aura Sounds|r" }

    if lastRegistration.file then
        local name = lastRegistration.file:match("clips\\(.+)%.ogg") or lastRegistration.file
        local age = lastRegistration.time and (GetServerTime() - lastRegistration.time) or 0
        table.insert(lines, ("Clip: |cFFFFFF00%s|r (%ds ago)"):format(name, age))
    else
        table.insert(lines, "Clip: |cFFFF0000none registered|r")
    end

    local live = #activeAuraSoundIDs
    table.insert(lines, ("Live handles: %s%d|r"):format(live > 0 and "|cFF7FFF7F" or "|cFFFF0000", live))

    for _, r in ipairs(lastRegistration.results) do
        if r.id then
            table.insert(lines, ("  %d |cFF7FFF7F-> %s|r"):format(r.spellId, tostring(r.id)))
        else
            table.insert(lines, ("  %d |cFFFF0000-> FAILED (nil)|r"):format(r.spellId))
        end
    end

    if #eventLog > 0 then
        table.insert(lines, " ")
        for _, line in ipairs(eventLog) do
            table.insert(lines, line)
        end
    end

    displayFrame.text:SetText(table.concat(lines, "\n"))
end

local function ToggleDisplay()
    if not displayFrame then
        local f = CreateFrame("Frame", "BLMRDisplayFrame", UIParent)
        f:SetSize(340, 300)
        f:SetPoint("CENTER", 0, 150)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.7)

        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.text:SetPoint("TOPLEFT", 10, -10)
        f.text:SetPoint("BOTTOMRIGHT", -10, 10)
        f.text:SetJustifyH("LEFT")
        f.text:SetJustifyV("TOP")

        -- Refresh once a second so the "Ns ago" counter ticks and you can see the
        -- 60s refresh land in real time.
        local elapsed = 0
        f:SetScript("OnUpdate", function(self, e)
            elapsed = elapsed + e
            if elapsed > 1 then
                elapsed = 0
                UpdateDisplay()
            end
        end)

        f:Hide()
        displayFrame = f
    end

    if displayFrame:IsShown() then
        displayFrame:Hide()
        print("|cFF00FF00[BLMR]|r Display hidden")
    else
        displayFrame:Show()
        UpdateDisplay()
        print("|cFF00FF00[BLMR]|r Display shown (drag to move)")
    end
end

local function GetAudioFiles()
    local files = {}
    local path = "Interface\\AddOns\\BloodlustMusicReborn\\clips\\"

    -- List of all available clips (hardcoded for now, WoW doesn't allow scanning for files)
    local clipNames = {
        "shed", "pink-pony-club", "toxic", "feel-the-pressure", "hard-times",
        "close-your-eyes-until-you-feel-good-inc", "holy-visions",
        "we-will-fall-together", "superman", "you-cant-stop-the-beat", "body-movin",
        "of-all-the-gin-joints", "stomp", "you-dropped-a-bomb-on-me", "big-ass-truck",
        "breaking-free", "man-i-feel-like-a-woman", "no-scrubs", "u-and-dat",
        "blow-the-whistle", "callin-baton-rouge", "angel-eyes",
        "whyd-you-come-in-here", "house-tour", "sell-out", "maximum-yodel", "sabotage",
        "back-in-the-saddle", "live-it-up", "do-ya-wanna-taste-it", "given-up",
        "ruffy-ryders-anthem", "hit-me-like-a-pinata", "sons-of-war", "break-stuff",
        "all-that-money", "collard-greens", "trap-queen", "johnny-dang", "gulch",
        "unknown", "asap-ferg", "whats-up", "lowrider", "weeb", "tell-me-when-to-go",
        "slow-motion", "then-leave", "where-the-hood-at", "be-a-man", "earth-air-fire",
        "apartment-512", "kryptonite", "pardon-me", "animal-i-have-become",
        "im-the-one", "anthems-of-the-apocalypse", "summer-nights", "can-you-feel-it",
        "blind"
    }

    for _, name in ipairs(clipNames) do
        table.insert(files, path .. name .. ".ogg")
    end

    return files
end

local function GetTimeBasedAudioFile()
    local files = GetAudioFiles()
    local index = (math.floor(GetServerTime() / 60) % #files) + 1
    return files[index], index
end

-- AddAuraSound is restricted (HasRestrictions in the 12.1 API docs) while
-- RemoveAuraSound is not. Confirmed in-game: adds work under the plain Combat
-- restriction but fail inside a boss encounter, so a refresh there used to
-- remove every handle and leave nothing registered. Only Encounter is listed:
-- adds were confirmed working under Combat (open world) and Map (active for the
-- whole of a dungeon, even out of combat), so blocking those would freeze the
-- song needlessly. Any other restriction that turns out to block adds is caught
-- by the add-before-remove rollback in RegisterBloodlustAuraSounds.
local R = Enum.AddOnRestrictionType
local BLOCKING_RESTRICTIONS = { R and R.Encounter or 1 }

local function IsAuraSoundAddRestricted()
    if not (C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive) then
        return false
    end
    for _, restriction in ipairs(BLOCKING_RESTRICTIONS) do
        if C_RestrictedActions.IsAddOnRestrictionActive(restriction) then
            return true
        end
    end
    return false
end

-- Set when a refresh was skipped because of a restriction; the next time a
-- restriction lifts we register immediately instead of waiting for the ticker.
local refreshPending = false

local function ClearBloodlustAuraSounds()
    local n = #activeAuraSoundIDs
    for _, id in ipairs(activeAuraSoundIDs) do
        C_UnitAuras.RemoveAuraSound(id)
    end
    wipe(activeAuraSoundIDs)
    if n > 0 then
        LogEvent(("|cFFFF7F7F-|r cleared %d"):format(n))
    end
    DebugPrint(("Cleared %d aura sound(s) at :%02d"):format(n, GetServerTime() % 60))
    UpdateDisplay()
end

-- UnitAura APIs return nil/secret for everything while in combat, so we can't
-- detect Bloodlust-family buffs in Lua and react to them ourselves. Instead we
-- register a native aura sound: Blizzard's own (non-tainted) engine plays the
-- file the moment the debuff lands on us, regardless of combat/secrecy state.
--
-- The song is picked from GetServerTime(), not math.random, so that anyone else
-- in the group also running this addon lands on the same song for the same
-- real-world minute without any addon communication. We refresh regularly so
-- the registered file stays aligned with "the current minute" through a long
-- fight, not just whatever was picked at the last combat entry.
local function RegisterBloodlustAuraSounds()
    if not BloodlustMusicRebornDB.enabled then
        ClearBloodlustAuraSounds()
        refreshPending = false
        DebugPrint("Addon disabled, not registering Bloodlust aura sounds")
        lastRegistration.file = nil
        wipe(lastRegistration.results)
        UpdateDisplay()
        return
    end

    -- Don't even try while adds are blocked: keep the handles registered before
    -- the pull so Bloodlust still plays, and catch up once the restriction lifts.
    if IsAuraSoundAddRestricted() then
        if not refreshPending then
            LogEvent("|cFFFFFF00~|r refresh deferred (restricted)")
        end
        refreshPending = true
        DebugPrint("Aura sound adds restricted; keeping current handles, refresh deferred")
        UpdateDisplay()
        return
    end
    refreshPending = false

    local file = GetTimeBasedAudioFile()

    -- Add the new handles BEFORE removing the old ones. Removal is never
    -- restricted but adding can be, so remove-then-add can leave us with nothing
    -- registered. If any add fails, roll back the new ones and keep the old set.
    local newIDs, results = {}, {}
    local attempted, succeeded = 0, 0
    for spellId in pairs(BLOODLUST_LOCKOUT_SPELL_IDS) do
        local ok, id = pcall(C_UnitAuras.AddAuraSound, Enum.UnitAuraSoundTrigger.Added, {
            unitToken = "player",
            spellID = spellId,
            soundFileName = file,
            outputChannel = BloodlustMusicRebornDB.channel,
        })
        if not ok then id = nil end
        attempted = attempted + 1
        if id then
            table.insert(newIDs, id)
            succeeded = succeeded + 1
        end
        table.insert(results, { spellId = spellId, id = id })
    end

    if succeeded < attempted and #activeAuraSoundIDs > 0 then
        for _, id in ipairs(newIDs) do
            C_UnitAuras.RemoveAuraSound(id)
        end
        refreshPending = true
        print(("|cFFFF0000[BLMR]|r WARNING: only %d/%d aura sounds registered for %s; keeping previous song")
            :format(succeeded, attempted, file))
        LogEvent(("|cFFFF0000!|r %d/%d failed, kept previous"):format(attempted - succeeded, attempted))
        UpdateDisplay()
        return
    end

    ClearBloodlustAuraSounds()
    for _, id in ipairs(newIDs) do
        table.insert(activeAuraSoundIDs, id)
    end

    table.sort(results, function(a, b) return a.spellId < b.spellId end)
    lastRegistration.file = file
    lastRegistration.time = GetServerTime()
    lastRegistration.results = results

    -- A nil return from AddAuraSound used to be swallowed silently while the
    -- success message printed anyway - the exact shape of "debug says it picked a
    -- song but nothing plays". Not debug-gated: this always needs to be loud.
    -- (Only reachable here when there was no previous set to fall back to.)
    if succeeded < attempted then
        refreshPending = true
        print(("|cFFFF0000[BLMR]|r WARNING: only %d/%d aura sounds registered for %s")
            :format(succeeded, attempted, file))
    end

    LogEvent(("|cFF7FFF7F+|r %d/%d %s"):format(succeeded, attempted, file:match("clips\\(.+)%.ogg") or "?"))
    DebugPrint(("Registered %d/%d aura sounds at :%02d -> %s")
        :format(succeeded, attempted, GetServerTime() % 60, file))
    UpdateDisplay()
end

-- A plain 60s ticker started at ADDON_LOADED would drift from other players'
-- tickers by however far apart their login times are within a minute, since
-- GetTimeBasedAudioFile()'s bucket only actually changes at the real minute
-- boundary. Align the first refresh to :10 past each minute (not :00) so
-- everyone's ticker lands on the same real-world moment, with a 10s buffer
-- past the boundary itself to absorb timer-firing jitter between clients.
local function ScheduleAlignedRefresh()
    local secondsUntilNext10 = (70 - (GetServerTime() % 60)) % 60
    C_Timer.After(secondsUntilNext10, function()
        RegisterBloodlustAuraSounds()
        C_Timer.NewTicker(60, RegisterBloodlustAuraSounds)
    end)
end

local function SlashCommandHandler(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word:lower())
    end

    local cmd = args[1]

    if not cmd or cmd == "help" then
        print("|cFF00FF00BloodlustMusicReborn Commands:|r")
        print("/blmr enable - Enable addon")
        print("/blmr disable - Disable addon")
        print("/blmr debug - Toggle debug mode")
        print("/blmr channel <master|music|sfx|ambience|dialog> - Set output channel")
        print("/blmr list - List available music files")
        print("/blmr display - Toggle the live aura-sound display")
        print("/blmr status - Show current settings")

    elseif cmd == "enable" then
        BloodlustMusicRebornDB.enabled = true
        RegisterBloodlustAuraSounds()
        print("|cFF00FF00[BLMR]|r Addon enabled")

    elseif cmd == "disable" then
        BloodlustMusicRebornDB.enabled = false
        ClearBloodlustAuraSounds()
        print("|cFF00FF00[BLMR]|r Addon disabled")

    elseif cmd == "debug" then
        BloodlustMusicRebornDB.debug = not BloodlustMusicRebornDB.debug
        print("|cFF00FF00[BLMR]|r Debug mode " .. (BloodlustMusicRebornDB.debug and "enabled" or "disabled"))

    elseif cmd == "channel" then
        local channel = args[2] and CHANNEL_ALIASES[args[2]]
        if channel then
            BloodlustMusicRebornDB.channel = channel
            RegisterBloodlustAuraSounds()
            print("|cFF00FF00[BLMR]|r Output channel set to " .. channel)
        else
            print("|cFFFF0000[BLMR]|r Invalid channel. Use: /blmr channel <master|music|sfx|ambience|dialog>")
        end

    elseif cmd == "display" then
        ToggleDisplay()

    elseif cmd == "status" then
        print("|cFF00FF00[BLMR] Current Settings:|r")
        print("  Enabled: " .. (BloodlustMusicRebornDB.enabled and "Yes" or "No"))
        print("  Debug: " .. (BloodlustMusicRebornDB.debug and "Yes" or "No"))
        print("  Channel: " .. BloodlustMusicRebornDB.channel)

    elseif cmd == "list" then
        local files = GetAudioFiles()
        print("|cFF00FF00[BLMR]|r Available music files (" .. #files .. " total):")
        for i, file in ipairs(files) do
            local name = file:match("clips\\(.+)%.ogg")
            print("  " .. i .. ". " .. name)
        end

    else
        print("|cFFFF0000[BLMR]|r Unknown command. Type /blmr for help")
    end
end

SLASH_BLMR1 = "/blmr"
SlashCmdList["BLMR"] = SlashCommandHandler

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- Catch up on a deferred refresh as soon as the restriction is lifted.
        local _, state = ...
        local inactive = Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive or 0
        if refreshPending and state == inactive and not IsAuraSoundAddRestricted() then
            DebugPrint("Restriction lifted; running deferred refresh")
            RegisterBloodlustAuraSounds()
        end
    elseif event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            if not BloodlustMusicRebornDB then
                BloodlustMusicRebornDB = {}
            end

            for k, v in pairs(defaults) do
                if BloodlustMusicRebornDB[k] == nil then
                    BloodlustMusicRebornDB[k] = v
                end
            end

            print("|cFF00FF00BloodlustMusicReborn loaded!|r Type /blmr for commands")
            RegisterBloodlustAuraSounds()
            ScheduleAlignedRefresh()
        end
    end
end)
