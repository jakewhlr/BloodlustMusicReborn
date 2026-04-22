-- BloodlustMusicReborn
local addonName, addon = ...

-- Default configuration
local defaults = {
    enabled = true,
    debug = false,
    volume = 50
}

local isPlaying = false
local currentSoundHandle = nil
local savedDialogueVolume = nil
local savedDialogueMuted = nil
local bloodlustActive = false
local stopTimer = nil

local BLOODLUST_LOCKOUT_SPELL_IDS = {
    [57724]  = true,  -- Sated (after Bloodlust)
    [57723]  = true,  -- Exhaustion (after Heroism)
    [80354]  = true,  -- Temporal Displacement (after Time Warp)
    [95809]  = true,  -- Insanity (after Ancient Hysteria)
    [160455] = true,  -- Fatigued (after Netherwinds / Primal Rage)
    [390435] = true,  -- Exhaustion (after Fury of the Aspects)
}

local BLOODLUST_DURATION = 40  -- seconds

local function DebugPrint(msg)
    if BloodlustMusicRebornDB.debug then
        print("|cFFFFFF00[BLMR Debug]|r " .. msg)
    end
end

local function SaveDialogueSettings()
    savedDialogueVolume = GetCVar("Sound_DialogVolume")
    savedDialogueMuted = GetCVarBool("Sound_EnableDialog")
    DebugPrint("Saved Dialog settings - Volume: " .. savedDialogueVolume .. ", Enabled: " .. tostring(savedDialogueMuted))
end

local function RestoreDialogueSettings()
    if savedDialogueVolume then
        SetCVar("Sound_DialogVolume", savedDialogueVolume)
        DebugPrint("Restored Dialog volume to " .. savedDialogueVolume)
    end
    if savedDialogueMuted ~= nil then
        SetCVar("Sound_EnableDialog", savedDialogueMuted and "1" or "0")
        DebugPrint("Restored Dialog enabled to " .. tostring(savedDialogueMuted))
    end
    savedDialogueVolume = nil
    savedDialogueMuted = nil
end

local function GetAudioFiles()
    local files = {}
    local path = "Interface\\AddOns\\BloodlustMusicReborn\\clips\\"

    -- List of all available clips (hardcoded for now, WoW doesn't allow scanning for files)
    local clipNames = {
        "9-to-5", "all-night", "all-the-things-she-said", "a-moment-apart",
        "apab", "artemis", "bangarang", "bfg-division", "big-iron", "bloodmeat",
        "came-out-swinging", "crawl", "defying-gravity",
        "diva-dance-from-the-fifth-element-full-version", "dumbest-girl-alive",
        "electric-daisy-violin", "eyeless", "fall-out-boy", "fuel", "gate-crasher",
        "gimme-gimme-gimme", "golden", "grillz", "gucci-gucci", "heart-of-courage",
        "hivemind", "how-its-done-instrumental", "ispy-iwsnt", "kryptonite", "language",
        "levels", "lights", "material-girl", "midnight-city", "money-machine", "nightlight",
        "oh-lord", "opalite", "paper-thin", "parasocialmaxxing", "rocky-road-to-dublin",
        "run-away-with-me", "sandstorm", "sorry-youre-not-a-winner", "srs", "take-on-me",
        "the-artist-in-the-ambulance", "the-only-thing-they-fear-is-you", "thick-neck",
        "through-the-fire-and-flames", "titanium", "toxicity", "twice", "union-dixie-trap",
        "unwritten", "your-graduation", "bullet", "duality", "bring-me-to-life"
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

local function StopAudio()
    if not isPlaying then
        return
    end

    if currentSoundHandle then
        StopSound(currentSoundHandle, 2000)  -- Fade out over 2 seconds (2000ms)
        DebugPrint("Stopped sound handle with 2s fade: " .. tostring(currentSoundHandle))
    end

    RestoreDialogueSettings()
    isPlaying = false
    currentSoundHandle = nil
    print("|cFF00FF00[BLMR]|r Playback stopped")
end

local function PlayAudio(filePath)
    if not BloodlustMusicRebornDB.enabled then
        DebugPrint("Addon disabled, not playing audio")
        return
    end

    if isPlaying then
        StopAudio()
    end

    DebugPrint("Playing: " .. filePath)

    SaveDialogueSettings()

    SetCVar("Sound_EnableDialog", "1")
    SetCVar("Sound_DialogVolume", BloodlustMusicRebornDB.volume / 100)
    DebugPrint("Set Dialog volume to " .. (BloodlustMusicRebornDB.volume / 100))

    local willPlay, soundHandle = PlaySoundFile(filePath, "Dialog")

    if willPlay then
        isPlaying = true
        currentSoundHandle = soundHandle
        print("|cFF00FF00[BLMR]|r Playing audio...")
        DebugPrint("Sound handle: " .. tostring(soundHandle))
    else
        print("|cFFFF0000[BLMR]|r Failed to play audio file")
        RestoreDialogueSettings()
    end
end

local function OnBloodlustDetected()
    if not BloodlustMusicRebornDB.enabled then
        return
    end
    if bloodlustActive then
        return
    end

    bloodlustActive = true
    local file, index = GetTimeBasedAudioFile()
    DebugPrint("Bloodlust detected via lockout debuff (file #" .. index .. ")")
    print("|cFF00FF00[BLMR]|r Bloodlust detected!")
    PlayAudio(file)

    if stopTimer then
        stopTimer:Cancel()
    end
    stopTimer = C_Timer.NewTimer(BLOODLUST_DURATION, function()
        DebugPrint("Bloodlust timer expired")
        print("|cFF00FF00[BLMR]|r Bloodlust ended")
        bloodlustActive = false
        stopTimer = nil
        StopAudio()
    end)
end

local function CheckAddedAurasForBloodlust(addedAuras)
    for _, aura in ipairs(addedAuras) do
        local ok, found = pcall(function()
            return BLOODLUST_LOCKOUT_SPELL_IDS[aura.spellId]
        end)
        if ok and found then
            DebugPrint("Lockout debuff detected: " .. tostring(aura.name) .. " (" .. tostring(aura.spellId) .. ")")
            OnBloodlustDetected()
            return
        end
    end
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
        print("/blmr volume <0-100> - Set volume")
        print("/blmr test - Test music playback")
        print("/blmr stop - Stop current playback")
        print("/blmr list - List available music files")
        print("/blmr status - Show current settings")

    elseif cmd == "enable" then
        BloodlustMusicRebornDB.enabled = true
        print("|cFF00FF00[BLMR]|r Addon enabled")

    elseif cmd == "disable" then
        BloodlustMusicRebornDB.enabled = false
        print("|cFF00FF00[BLMR]|r Addon disabled")

    elseif cmd == "debug" then
        BloodlustMusicRebornDB.debug = not BloodlustMusicRebornDB.debug
        print("|cFF00FF00[BLMR]|r Debug mode " .. (BloodlustMusicRebornDB.debug and "enabled" or "disabled"))

    elseif cmd == "volume" then
        local vol = tonumber(args[2])
        if vol and vol >= 0 and vol <= 100 then
            BloodlustMusicRebornDB.volume = vol
            print("|cFF00FF00[BLMR]|r Volume set to " .. vol)
            DebugPrint("Volume changed to " .. vol)
        else
            print("|cFFFF0000[BLMR]|r Invalid volume. Use: /blmr volume <0-100>")
        end

    elseif cmd == "status" then
        print("|cFF00FF00[BLMR] Current Settings:|r")
        print("  Enabled: " .. (BloodlustMusicRebornDB.enabled and "Yes" or "No"))
        print("  Debug: " .. (BloodlustMusicRebornDB.debug and "Yes" or "No"))
        print("  Volume: " .. BloodlustMusicRebornDB.volume)

    elseif cmd == "test" then
        local file, index = GetTimeBasedAudioFile()
        print("|cFF00FF00[BLMR]|r Testing playback (file #" .. index .. ")")
        PlayAudio(file)

    elseif cmd == "stop" then
        if isPlaying then
            StopAudio()
        else
            print("|cFF00FF00[BLMR]|r No audio currently playing")
        end

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
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterUnitEvent("UNIT_AURA", "player")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
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
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Reset state on zone/login so a lingering timer doesn't carry over
        if stopTimer then
            stopTimer:Cancel()
            stopTimer = nil
        end
        bloodlustActive = false

    elseif event == "UNIT_AURA" then
        local unit, updateInfo = ...
        if unit == "player" and updateInfo and not updateInfo.isFullUpdate
                and updateInfo.addedAuras and #updateInfo.addedAuras > 0 then
            CheckAddedAurasForBloodlust(updateInfo.addedAuras)
        end
    end
end)
