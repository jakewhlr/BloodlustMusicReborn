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
local previousHaste = 0
local bloodlustActive = false

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
        "absolutelycrankinmymfnhog", "all-this-money", "amos-moses", "angel-style",
        "back-then", "bad-for-yah-health", "bad-toys", "cataclysm", "chop-suey",
        "cruise-control", "dash-out", "dicke-titten", "divynyls", "do-it-again-remix",
        "ecstasy-of-soul", "first-light", "glitch-inferno", "gravity", "guiles-theme",
        "hard-in-the-paint", "holiday", "intergalactic", "jenova-theme-song", "lightbringer",
        "like-a-train", "love-shack", "maria", "mmmbop", "never-gonna-wake-you-up",
        "possessed-skelton", "ratatata", "ricky", "rise-up", "rockstar", "savior",
        "seep-now-in-the-fire", "september-congratulations", "shatter-me-ft-lzzy-hale",
        "skull-machine", "so-be-it", "star-theme", "still-into-you-remix", "super-freak",
        "surrender", "taste", "the-last-stand", "theme-song", "toxic", "twisted-romantics",
        "u-face", "wdhttoco", "when-it-reigns-it-pours", "you-think-i-aint-worth-a-dollar"
    }

    for _, name in ipairs(clipNames) do
        table.insert(files, path .. name .. ".ogg")
    end

    return files
end

local function GetTimeBasedAudioFile()
    local files = GetAudioFiles()
    local index = (time() % #files) + 1
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
    bloodlustActive = false
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

local function CheckForBloodlust()
    if not BloodlustMusicRebornDB.enabled then
        return
    end

    local currentHaste = GetHaste()
    local hasteMultiplier = (1 + currentHaste / 100) / (1 + previousHaste / 100)

    DebugPrint("Haste check - current: " .. string.format("%.2f", currentHaste) .. "%, prev: " .. string.format("%.2f", previousHaste) .. "%, multiplier: " .. string.format("%.4f", hasteMultiplier))

    -- Detect bloodlust start: multiplier ~1.30 (30% haste buff)
    -- TODO fix thisl, this will probably also trigger on other 30% buffs
    if not bloodlustActive and hasteMultiplier >= 1.28 and hasteMultiplier <= 1.32 then
        bloodlustActive = true
        local file, index = GetTimeBasedAudioFile()
        DebugPrint("Bloodlust detected! Multiplier: " .. string.format("%.4f", hasteMultiplier) .. " (prev: " .. string.format("%.2f", previousHaste) .. "%, curr: " .. string.format("%.2f", currentHaste) .. "%)")
        print("|cFF00FF00[BLMR]|r Bloodlust detected!")
        PlayAudio(file)

    -- Detect bloodlust end: multiplier ~0.769 (30% buff fell off)
    elseif bloodlustActive and hasteMultiplier <= 0.79 and hasteMultiplier >= 0.74 then
        DebugPrint("Bloodlust ended. Multiplier: " .. string.format("%.4f", hasteMultiplier) .. " (prev: " .. string.format("%.2f", previousHaste) .. "%, curr: " .. string.format("%.2f", currentHaste) .. "%)")
        print("|cFF00FF00[BLMR]|r Bloodlust ended")
        StopAudio()
    end

    previousHaste = currentHaste
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
        previousHaste = GetHaste()
        DebugPrint("Initialized haste tracking at " .. string.format("%.2f", previousHaste) .. "%")

    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            CheckForBloodlust()
        end
    end
end)
