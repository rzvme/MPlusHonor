-- MPlusHonor Core
MPlusHonor = {}
local MPH = MPlusHonor

-- HARDCODED Configuration - Change this before distributing addon
MPH.Config = {
    baseURL = "http://mplushonor.guildhub.eu/rate/", -- CHANGE THIS TO YOUR ACTUAL WEBSITE
}

-- Store active dungeon info when challenge starts
MPH.activeDungeonInfo = nil
MPH.challengeActive = false

-- Debug print helper
local function DebugPrint(...)
    if MPlusHonorDB and MPlusHonorDB.settings and MPlusHonorDB.settings.debug then
        print("|cff00ff00[MPH Debug]|r", ...)
    end
end

-- Base64 encoding function
local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64Encode(data)
    return ((data:gsub('.', function(x) 
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b64chars:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

-- URL-safe base64 (replace + and / with - and _)
local function urlSafeBase64Encode(data)
    local encoded = base64Encode(data)
    encoded = encoded:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
    return encoded
end

-- Initialize saved variables
function MPH:Initialize()
    if not MPlusHonorDB then
        MPlusHonorDB = {
            completedRuns = {},
            settings = {
                autoShow = true,
                showInChat = true,
                announceInParty = true,
                debug = false
            }
        }
    end
    
    -- Add new setting if it doesn't exist (for existing users)
    if MPlusHonorDB.settings.announceInParty == nil then
        MPlusHonorDB.settings.announceInParty = true
    end
    
    print("|cff00ff00MPlusHonor|r loaded! Version 1.0.3")
    
    -- Check if rating data is loaded
    if MythicPlusHonorData then
        local stats = MythicPlusHonorData:GetStats()
        print(string.format("|cff00ff00MPlusHonor:|r Rating database loaded - %d players, %d ratings", 
            stats.totalPlayers, stats.totalRatings))
    else
        print("|cffff0000MPlusHonor:|r WARNING - Rating database not loaded!")
    end
    print("|cff00ff00MPlusHonor:|r Type |cffffcc00/mph help|r for commands")
    
    if MPlusHonorDB.settings.debug then
        print("|cff00ff00MPlusHonor:|r Debug mode enabled")
    end
end

-- Get character rating from database
function MPH:GetCharacterRating(name, realm)
    if not MythicPlusHonorData then
        return nil
    end
    return MythicPlusHonorData:GetRating(name, realm)
end

-- Get player's region
function MPH:GetPlayerRegion()
    local regionID = GetCurrentRegion()
    local regions = {
        [1] = "US",
        [2] = "KR",
        [3] = "EU",
        [4] = "TW",
        [5] = "CN"
    }
    return regions[regionID] or "US"
end

-- Get all group members with full details
function MPH:GetGroupMembers()
    local members = {}
    local playerName, playerRealm = UnitFullName("player")
    
    if not playerName then
        DebugPrint("Failed to get player name")
        return members
    end
    
    -- Normalize realm name (remove spaces)
    playerRealm = (playerRealm or GetRealmName()):gsub("%s+", "")
    
    DebugPrint("Getting group members. Player:", playerName, "Realm:", playerRealm)
    
    -- Always include the player
    table.insert(members, {
        name = playerName,
        realm = playerRealm,
        fullName = playerName .. "-" .. playerRealm,
        class = select(2, UnitClass("player")),
        isPlayer = true
    })
    
    -- Get group type
    local groupSize = GetNumGroupMembers()
    local isInRaid = IsInRaid()
    
    DebugPrint("Group size:", groupSize, "Is raid:", isInRaid)
    
    if groupSize > 0 then
        local prefix = isInRaid and "raid" or "party"
        local startIndex = isInRaid and 1 or 1
        local endIndex = isInRaid and groupSize or (groupSize - 1)
        
        for i = startIndex, endIndex do
            local unit = prefix .. i
            if UnitExists(unit) then
                local name, realm = UnitFullName(unit)
                realm = (realm or GetRealmName()):gsub("%s+", "")
                
                if name and name ~= playerName then
                    DebugPrint("Found group member:", name, "-", realm)
                    table.insert(members, {
                        name = name,
                        realm = realm,
                        fullName = name .. "-" .. realm,
                        class = select(2, UnitClass(unit)),
                        isPlayer = false
                    })
                end
            end
        end
    end
    
    DebugPrint("Total members found:", #members)
    return members
end

-- Capture dungeon info when challenge starts (before completion)
function MPH:CaptureActiveDungeonInfo()
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    
    if not mapID then
        DebugPrint("No active challenge map ID when starting")
        return
    end
    
    DebugPrint("Challenge started - Capturing info. Map ID:", mapID)
    
    local name, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    local level, affixes = C_ChallengeMode.GetActiveKeystoneInfo()
    
    if not level then
        DebugPrint("Failed to get keystone level on start")
        return
    end
    
    -- Get affix IDs
    local affixIDs = {}
    if affixes then
        for i = 1, #affixes do
            table.insert(affixIDs, affixes[i])
            DebugPrint("Affix", i, ":", affixes[i])
        end
    end
    
    -- Store members at start too, in case group changes
    local startMembers = self:GetGroupMembers()
    
    self.activeDungeonInfo = {
        mapID = mapID,
        name = name or ("Dungeon " .. mapID),
        level = level,
        timeLimit = timeLimit,
        affixes = affixIDs,
        startMembers = startMembers,
        startTime = time()
    }
    
    self.challengeActive = true
    
    DebugPrint("Dungeon info captured:", self.activeDungeonInfo.name, "Level:", self.activeDungeonInfo.level)
end

-- Create encoded payload
function MPH:CreatePayload(dungeonInfo, members, timestamp, wasInTime)
    local region = self:GetPlayerRegion()
    
    -- Build member array
    local memberData = {}
    for _, member in ipairs(members) do
        table.insert(memberData, {
            n = member.name,
            r = member.realm,
            c = member.class
        })
    end
    
    -- Create compact data structure
    local data = {
        m = dungeonInfo.mapID,           -- map ID
        l = dungeonInfo.level,           -- keystone level
        t = timestamp,                   -- timestamp
        i = wasInTime and 1 or 0,        -- in time (1/0)
        a = dungeonInfo.affixes,         -- affixes
        p = memberData,                  -- players
        g = region,                      -- region
        v = "1.0"                        -- version
    }
    
    -- Simple JSON serialization (manual for control)
    local json = "{"
    json = json .. '"m":' .. data.m .. ','
    json = json .. '"l":' .. data.l .. ','
    json = json .. '"t":' .. data.t .. ','
    json = json .. '"i":' .. data.i .. ','
    json = json .. '"g":"' .. data.g .. '",'
    json = json .. '"v":"' .. data.v .. '",'
    
    -- Add affixes
    json = json .. '"a":['
    if data.a and #data.a > 0 then
        for idx, affix in ipairs(data.a) do
            json = json .. affix
            if idx < #data.a then json = json .. ',' end
        end
    end
    json = json .. '],'
    
    -- Add players
    json = json .. '"p":['
    for idx, player in ipairs(data.p) do
        json = json .. '{"n":"' .. player.n .. '","r":"' .. player.r .. '","c":"' .. player.c .. '"}'
        if idx < #data.p then json = json .. ',' end
    end
    json = json .. ']'
    
    json = json .. "}"
    
    DebugPrint("Payload JSON:", json)
    
    return json
end

-- Handle dungeon completion
function MPH:OnDungeonComplete(isEarlyExit)
    DebugPrint("OnDungeonComplete triggered - Early exit:", tostring(isEarlyExit))
    
    -- Get completion info first (this works for actual completions)
    local completionMapID, completionLevel, completionTime, onTime, keystoneUpgradeLevels = C_ChallengeMode.GetCompletionInfo()
    
    DebugPrint("GetCompletionInfo returned - MapID:", completionMapID, "Level:", completionLevel, "OnTime:", onTime)
    
    -- Use stored dungeon info if we have it from CHALLENGE_MODE_START
    local dungeonInfo = self.activeDungeonInfo
    
    -- If no stored info and completion info is available, try to build minimal info
    if not dungeonInfo and completionMapID and completionMapID > 0 then
        DebugPrint("No stored dungeon info, building from completion info")
        local name = C_ChallengeMode.GetMapUIInfo(completionMapID)
        dungeonInfo = {
            mapID = completionMapID,
            name = name or ("Dungeon " .. completionMapID),
            level = completionLevel,
            affixes = {}, -- We won't have affixes if we didn't capture on start
            startMembers = nil
        }
    end
    
    -- If still no dungeon info, we can't proceed
    if not dungeonInfo then
        print("|cffff0000MPlusHonor:|r Could not retrieve dungeon information.")
        DebugPrint("Failed to get dungeon info - no stored info and no completion info")
        return
    end
    
    -- Get current members (or use start members if early exit)
    local members
    if isEarlyExit and dungeonInfo.startMembers then
        DebugPrint("Using stored members from dungeon start")
        members = dungeonInfo.startMembers
    else
        members = self:GetGroupMembers()
    end
    
    -- Need at least 2 players (self + 1 other)
    if #members < 2 then
        DebugPrint("Not enough players:", #members)
        return
    end
    
    -- Use completion info for final results if available
    local finalMapID = (completionMapID and completionMapID > 0) and completionMapID or dungeonInfo.mapID
    local finalLevel = (completionLevel and completionLevel > 0) and completionLevel or dungeonInfo.level
    
    -- For early exits, we mark as not timed
    local finalOnTime
    if isEarlyExit then
        finalOnTime = false
        DebugPrint("Early exit detected - marking as not timed")
    else
        finalOnTime = onTime or false
    end
    
    DebugPrint("Final values - MapID:", finalMapID, "Level:", finalLevel, "OnTime:", finalOnTime)
    
    local timestamp = time()
    
    -- Update dungeonInfo with final values
    dungeonInfo.mapID = finalMapID
    dungeonInfo.level = finalLevel
    
    -- Create the payload
    local payload = self:CreatePayload(dungeonInfo, members, timestamp, finalOnTime)
    
    -- Encode the payload
    local encodedPayload = urlSafeBase64Encode(payload)
    
    -- Generate the obfuscated URL
    local url = self.Config.baseURL .. encodedPayload
    
    DebugPrint("Generated URL length:", #url)
    
    -- Store the run
    local runData = {
        mapID = finalMapID,
        mapName = dungeonInfo.name,
        level = finalLevel,
        timestamp = timestamp,
        wasInTime = finalOnTime,
        members = members,
        url = url,
        payload = payload -- Store for debugging if needed
    }
    
    table.insert(MPlusHonorDB.completedRuns, runData)
    
    -- Keep only last 50 runs to prevent bloat
    while #MPlusHonorDB.completedRuns > 50 do
        table.remove(MPlusHonorDB.completedRuns, 1)
    end
    
    -- Show the URL to the user
    if MPlusHonorDB.settings.autoShow then
        MPH.UI:ShowRatingWindow(runData)
    end
    
    if MPlusHonorDB.settings.showInChat then
        print("|cff00ff00MPlusHonor:|r Dungeon completed! Rate your group:")
        print("|cff00ccff" .. url .. "|r")
    end
    
    -- Announce in party/raid chat
    if MPlusHonorDB.settings.announceInParty then
        local chatType = IsInRaid() and "RAID" or "PARTY"
        -- Only announce if in a group
        if GetNumGroupMembers() > 1 then
            C_Timer.After(2, function()
                SendChatMessage("I'm using MPlusHonor addon - I will honor you all! Check your character's honors at mplushonor.guildhub.eu", chatType)
                DebugPrint("Sent party announcement to", chatType)
            end)
        end
    end
    
    DebugPrint("Successfully created rating session")
    
    -- Clear the stored dungeon info after successful completion
    self.activeDungeonInfo = nil
    self.challengeActive = false
end

-- Check if player left dungeon (called on zone change)
function MPH:CheckForDungeonExit()
    -- If we had an active challenge but now we don't, player left early
    if self.challengeActive and self.activeDungeonInfo then
        local currentMapID = C_ChallengeMode.GetActiveChallengeMapID()
        
        if not currentMapID then
            DebugPrint("Player left dungeon - generating rating URL")
            -- Player left the dungeon, trigger completion
            C_Timer.After(0.5, function()
                self:OnDungeonComplete(true) -- true = early exit
            end)
        end
    end
end

-- Event handler frame
local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("CHALLENGE_MODE_START")
EventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

EventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "MPlusHonor" then
            MPH:Initialize()
        end
    elseif event == "CHALLENGE_MODE_START" then
        DebugPrint("CHALLENGE_MODE_START event fired")
        -- Capture dungeon info while we're still in the active challenge
        MPH:CaptureActiveDungeonInfo()
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        DebugPrint("CHALLENGE_MODE_COMPLETED event fired")
        -- Reduced wait time since we already have the info stored
        C_Timer.After(1, function()
            MPH:OnDungeonComplete(false) -- false = normal completion
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        DebugPrint("PLAYER_ENTERING_WORLD event fired")
        -- Check if we left a dungeon early
        C_Timer.After(1, function()
            MPH:CheckForDungeonExit()
        end)
    end
end)

-- Slash commands
SLASH_MPLUSHONOR1 = "/mph"
SLASH_MPLUSHONOR2 = "/mplushonor"

SlashCmdList["MPLUSHONOR"] = function(msg)
    msg = msg:lower():trim()
    
    if msg == "" or msg == "help" then
        print("|cff00ff00MPlusHonor Commands:|r")
        print("/mph show - Show last rating URL")
        print("/mph history - Show recent runs")
        print("/mph toggle - Toggle auto-show window")
        print("/mph announce - Toggle party chat announcements")
        print("/mph debug - Show last payload (for debugging)")
        print("/mph debugmode - Toggle debug mode")
        print("/mph test - Test dungeon completion (debug)")
        print("/mph complete - Force record current dungeon (use after completion)")
    elseif msg == "show" then
        local lastRun = MPlusHonorDB.completedRuns[#MPlusHonorDB.completedRuns]
        if lastRun then
            MPH.UI:ShowRatingWindow(lastRun)
        else
            print("|cffff0000MPlusHonor:|r No recent runs found.")
        end
    elseif msg == "history" then
        print("|cff00ff00Recent Mythic+ Runs:|r")
        local count = math.min(5, #MPlusHonorDB.completedRuns)
        if count == 0 then
            print("No runs found yet. Complete a Mythic+ dungeon!")
        else
            for i = #MPlusHonorDB.completedRuns, math.max(1, #MPlusHonorDB.completedRuns - count + 1), -1 do
                local run = MPlusHonorDB.completedRuns[i]
                print(string.format("%s +%d (%s) - %s", run.mapName, run.level, 
                    run.wasInTime and "|cff00ff00Timed|r" or "|cffff0000Not Timed|r",
                    date("%m/%d %H:%M", run.timestamp)))
            end
        end
    elseif msg == "toggle" then
        MPlusHonorDB.settings.autoShow = not MPlusHonorDB.settings.autoShow
        print(string.format("|cff00ff00MPlusHonor:|r Auto-show %s", 
            MPlusHonorDB.settings.autoShow and "enabled" or "disabled"))
    elseif msg == "announce" then
        MPlusHonorDB.settings.announceInParty = not MPlusHonorDB.settings.announceInParty
        print(string.format("|cff00ff00MPlusHonor:|r Party announcements %s", 
            MPlusHonorDB.settings.announceInParty and "|cff00ff00enabled|r" or "|cffff0000disabled|r"))
    elseif msg == "debug" then
        local lastRun = MPlusHonorDB.completedRuns[#MPlusHonorDB.completedRuns]
        if lastRun and lastRun.payload then
            print("|cff00ff00Last Payload (decoded):|r")
            print(lastRun.payload)
            print("|cff00ff00URL:|r")
            print(lastRun.url)
        else
            print("|cffff0000No recent runs found.|r")
        end
    elseif msg == "debugmode" then
        MPlusHonorDB.settings.debug = not MPlusHonorDB.settings.debug
        print(string.format("|cff00ff00MPlusHonor:|r Debug mode %s", 
            MPlusHonorDB.settings.debug and "|cff00ff00enabled|r" or "|cffff0000disabled|r"))
    elseif msg == "test" then
        print("|cff00ff00MPlusHonor:|r Testing dungeon completion...")
        DebugPrint("Manual test triggered")
        MPH:OnDungeonComplete(false)
    elseif msg == "complete" then
        print("|cff00ff00MPlusHonor:|r Forcing dungeon completion recording...")
        DebugPrint("Force complete triggered")
        -- Force record even if GetCompletionInfo returns zeros
        MPH:OnDungeonComplete(false)
    else
        print("|cffff0000MPlusHonor:|r Unknown command. Type /mph help for options.")
    end
end

-- Print confirmation that slash commands are registered
DebugPrint("Slash commands registered: /mph and /mplushonor")
-- Add test command for checking ratings
SLASH_MPHTESTRATING1 = "/mphtest"
SlashCmdList["MPHTESTRATING"] = function(msg)
    msg = msg:trim()
    if msg == "" then
        print("|cff00ff00MPlusHonor Test:|r Usage: /mphtest Name-Realm")
        print("Example: /mphtest Warlokii-Silvermoon")
        return
    end
    
    local name, realm = strsplit("-", msg, 2)
    if name and realm then
        realm = realm:gsub("%s+", "")
        print("|cff00ff00MPlusHonor Test:|r Looking for: " .. name .. "-" .. realm)
        
        local rating = MPH:GetCharacterRating(name, realm)
        if rating then
            print("|cff00ff00Found rating!|r")
            print(string.format("  Average Rating: %.1f/5.0", rating.averageRating))
            print(string.format("  Total Ratings: %d", rating.totalRatings))
        else
            print("|cffff0000No rating found|r")
            print("Make sure name and realm match exactly (case-sensitive)")
            print("Realm should have no spaces (e.g., 'TarrenMill' not 'Tarren Mill')")
        end
    else
        print("|cffff0000Invalid format|r Usage: /mphtest Name-Realm")
    end
end
