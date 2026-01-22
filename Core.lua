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
                debug = false,
                debugTooltips = false  -- Separate debug flag for tooltips
            }
        }
    end
    
    -- Add new setting if it doesn't exist (for existing users)
    if MPlusHonorDB.settings.announceInParty == nil then
        MPlusHonorDB.settings.announceInParty = true
    end
    
    if MPlusHonorDB.settings.debugTooltips == nil then
        MPlusHonorDB.settings.debugTooltips = false
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
    DebugPrint("CaptureActiveDungeonInfo called")
    
    -- Check if required APIs exist
    if not C_ChallengeMode.GetActiveChallengeMapID then
        print("|cffff0000MPlusHonor:|r GetActiveChallengeMapID API not available in this version")
        DebugPrint("CRITICAL: GetActiveChallengeMapID does not exist")
        return
    end
    
    if not C_ChallengeMode.GetActiveKeystoneInfo then
        print("|cffff0000MPlusHonor:|r GetActiveKeystoneInfo API not available in this version")
        DebugPrint("CRITICAL: GetActiveKeystoneInfo does not exist")
        return
    end
    
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
    
    DebugPrint("Got level:", level, "from GetActiveKeystoneInfo")
    
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
    DebugPrint("Captured", #startMembers, "members at dungeon start")
    
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
    
    DebugPrint("Dungeon info captured successfully:", self.activeDungeonInfo.name, "Level:", self.activeDungeonInfo.level)
    DebugPrint("Time limit for this dungeon:", timeLimit, "seconds (", math.floor(timeLimit/60), "minutes )")
    DebugPrint("Start time recorded:", self.activeDungeonInfo.startTime)
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

-- Handle dungeon completion
function MPH:OnDungeonComplete(isEarlyExit)
    DebugPrint("OnDungeonComplete triggered - Early exit:", tostring(isEarlyExit))
    
    -- MIDNIGHT FIX: Try multiple methods to get dungeon info
    local completionMapID, completionLevel, completionTime, onTime, keystoneUpgradeLevels
    
    -- Method 1: Try GetCompletionInfo (may not exist in Midnight)
    if C_ChallengeMode.GetCompletionInfo then
        local success, mapID, level, time, onTimeBool, upgrades = pcall(C_ChallengeMode.GetCompletionInfo)
        if success then
            completionMapID = mapID
            completionLevel = level
            completionTime = time
            onTime = onTimeBool
            keystoneUpgradeLevels = upgrades
            DebugPrint("GetCompletionInfo returned - MapID:", tostring(completionMapID), "Level:", tostring(completionLevel), "OnTime:", tostring(onTime))
        else
            DebugPrint("ERROR calling GetCompletionInfo:", tostring(mapID))
        end
    else
        DebugPrint("GetCompletionInfo API does NOT exist in this version - using fallback methods")
    end
    
    -- We no longer need to explore timing - it's calculated in CHALLENGE_MODE_COMPLETED event
    -- Just use the stored wasInTime value
    if onTime == nil then
        DebugPrint("onTime is nil, will use stored wasInTime from activeDungeonInfo")
    else
        DebugPrint("onTime from GetCompletionInfo:", tostring(onTime))
    end
    
    -- Method 2: Try GetActiveChallengeMapID if completion info failed
    if not completionMapID or completionMapID == 0 then
        if C_ChallengeMode.GetActiveChallengeMapID then
            completionMapID = C_ChallengeMode.GetActiveChallengeMapID()
            DebugPrint("Fallback: GetActiveChallengeMapID returned:", tostring(completionMapID))
        else
            DebugPrint("GetActiveChallengeMapID API does NOT exist")
        end
    end
    
    -- Method 3: Try GetActiveKeystoneInfo for level if needed
    if not completionLevel or completionLevel == 0 then
        if C_ChallengeMode.GetActiveKeystoneInfo then
            local level, affixes = C_ChallengeMode.GetActiveKeystoneInfo()
            completionLevel = level
            DebugPrint("Fallback: GetActiveKeystoneInfo returned level:", tostring(level))
        else
            DebugPrint("GetActiveKeystoneInfo API does NOT exist")
        end
    end
    
    -- Use stored dungeon info if we have it from CHALLENGE_MODE_START
    local dungeonInfo = self.activeDungeonInfo
    
    DebugPrint("Stored activeDungeonInfo:", tostring(dungeonInfo ~= nil))
    if dungeonInfo then
        DebugPrint("  - Stored MapID:", tostring(dungeonInfo.mapID))
        DebugPrint("  - Stored Level:", tostring(dungeonInfo.level))
        DebugPrint("  - Stored Name:", tostring(dungeonInfo.name))
        DebugPrint("  - Stored wasInTime:", tostring(dungeonInfo.wasInTime))
        
        -- Use the timing status we captured immediately after completion
        if dungeonInfo.wasInTime ~= nil then
            onTime = dungeonInfo.wasInTime
            DebugPrint("Using stored wasInTime value:", tostring(onTime))
        end
    end
    
    -- MIDNIGHT FIX: If no stored info, try harder to build it from available APIs
    if not dungeonInfo then
        DebugPrint("No stored dungeon info, attempting to build from available APIs")
        
        -- Try to get map ID from any available source
        local mapID = completionMapID
        if not mapID or mapID == 0 then
            mapID = C_ChallengeMode.GetActiveChallengeMapID()
        end
        
        -- Try to get level from any available source
        local level = completionLevel
        if not level or level == 0 then
            local activeLevel, activeAffixes = C_ChallengeMode.GetActiveKeystoneInfo()
            level = activeLevel
        end
        
        -- If we have both mapID and level, build minimal dungeon info
        if mapID and mapID > 0 and level and level > 0 then
            DebugPrint("Building minimal dungeon info - MapID:", mapID, "Level:", level)
            local name = C_ChallengeMode.GetMapUIInfo(mapID)
            dungeonInfo = {
                mapID = mapID,
                name = name or ("Dungeon " .. mapID),
                level = level,
                affixes = {}, -- We won't have affixes if we didn't capture on start
                startMembers = nil
            }
        else
            DebugPrint("Failed to get valid mapID or level - MapID:", tostring(mapID), "Level:", tostring(level))
        end
    end
    
    -- If still no dungeon info, we can't proceed
    if not dungeonInfo then
        print("|cffff0000MPlusHonor:|r Could not retrieve dungeon information.")
        print("|cffff0000MPlusHonor:|r Please enable debug mode (/mph debugmode) and report the issue.")
        DebugPrint("CRITICAL: Failed to get dungeon info - no stored info and no valid completion/active info")
        DebugPrint("  completionMapID:", tostring(completionMapID))
        DebugPrint("  completionLevel:", tostring(completionLevel))
        DebugPrint("  activeDungeonInfo:", tostring(self.activeDungeonInfo))
        return
    end
    
    DebugPrint("Dungeon info acquired:", dungeonInfo.name, "MapID:", dungeonInfo.mapID, "Level:", dungeonInfo.level)
    
    -- Get current members (or use start members if early exit)
    local members
    if isEarlyExit and dungeonInfo.startMembers then
        DebugPrint("Using stored members from dungeon start")
        members = dungeonInfo.startMembers
    else
        DebugPrint("Getting current group members")
        members = self:GetGroupMembers()
    end
    
    DebugPrint("Retrieved", #members, "members")
    
    -- Need at least 2 players (self + 1 other)
    if #members < 2 then
        print("|cffff0000MPlusHonor:|r Not enough group members to generate rating URL (need at least 2)")
        DebugPrint("EARLY EXIT: Not enough players:", #members)
        return
    end
    
    -- Use completion info for final results if available and valid
    local finalMapID = (completionMapID and completionMapID > 0) and completionMapID or dungeonInfo.mapID
    local finalLevel = (completionLevel and completionLevel > 0) and completionLevel or dungeonInfo.level
    
    -- For early exits, we mark as not timed
    local finalOnTime
    if isEarlyExit then
        finalOnTime = false
        DebugPrint("Early exit detected - marking as not timed")
    else
        -- Use whatever timing info we got, default to false if unknown
        finalOnTime = (onTime == true) -- Explicitly check for true, nil becomes false
        DebugPrint("Using onTime value:", tostring(onTime), "-> finalOnTime:", tostring(finalOnTime))
    end
    
    DebugPrint("Final values - MapID:", finalMapID, "Level:", finalLevel, "OnTime:", finalOnTime)
    
    -- Validate final values before proceeding
    if not finalMapID or finalMapID == 0 or not finalLevel or finalLevel == 0 then
        print("|cffff0000MPlusHonor:|r Invalid dungeon data - cannot generate URL")
        DebugPrint("EARLY EXIT: Invalid final values")
        DebugPrint("  finalMapID:", tostring(finalMapID))
        DebugPrint("  finalLevel:", tostring(finalLevel))
        DebugPrint("  completionMapID:", tostring(completionMapID))
        DebugPrint("  completionLevel:", tostring(completionLevel))
        DebugPrint("  dungeonInfo.mapID:", tostring(dungeonInfo.mapID))
        DebugPrint("  dungeonInfo.level:", tostring(dungeonInfo.level))
        return
    end
    
    local timestamp = time()
    
    DebugPrint("Validation passed - proceeding to create payload")
    
    -- Update dungeonInfo with final values
    dungeonInfo.mapID = finalMapID
    dungeonInfo.level = finalLevel
    
    -- Create the payload
    DebugPrint("Creating payload...")
    local payload = self:CreatePayload(dungeonInfo, members, timestamp, finalOnTime)
    
    -- Encode the payload
    DebugPrint("Encoding payload...")
    local encodedPayload = urlSafeBase64Encode(payload)
    
    -- Generate the obfuscated URL
    local url = self.Config.baseURL .. encodedPayload
    
    DebugPrint("Generated URL length:", #url)
    DebugPrint("URL:", url)
    
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
    
    DebugPrint("Successfully created rating session - showing UI")
    
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
    
    -- Clear the stored dungeon info after successful completion
    self.activeDungeonInfo = nil
    self.challengeActive = false
    
    DebugPrint("OnDungeonComplete finished successfully")
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
        
        -- MIDNIGHT: Calculate timing ourselves using start time and time limit
        local wasInTime = nil
        
        if MPH.activeDungeonInfo and MPH.activeDungeonInfo.startTime and MPH.activeDungeonInfo.timeLimit then
            local currentTime = time()
            local elapsedSeconds = currentTime - MPH.activeDungeonInfo.startTime
            local timeLimitSeconds = MPH.activeDungeonInfo.timeLimit
            
            DebugPrint("=== Calculating timing ===")
            DebugPrint("Start time:", MPH.activeDungeonInfo.startTime)
            DebugPrint("Current time:", currentTime)
            DebugPrint("Elapsed seconds:", elapsedSeconds)
            DebugPrint("Time limit (seconds):", timeLimitSeconds)
            
            -- Convert to human-readable format
            local elapsedMinutes = math.floor(elapsedSeconds / 60)
            local elapsedSecondsRemainder = elapsedSeconds % 60
            local limitMinutes = math.floor(timeLimitSeconds / 60)
            local limitSecondsRemainder = timeLimitSeconds % 60
            
            DebugPrint(string.format("Time taken: %d:%02d", elapsedMinutes, elapsedSecondsRemainder))
            DebugPrint(string.format("Time limit: %d:%02d", limitMinutes, limitSecondsRemainder))
            
            wasInTime = (elapsedSeconds <= timeLimitSeconds)
            
            if wasInTime then
                local marginSeconds = timeLimitSeconds - elapsedSeconds
                DebugPrint(string.format("SUCCESS: Key was TIMED with %d seconds to spare!", marginSeconds))
            else
                local overSeconds = elapsedSeconds - timeLimitSeconds
                DebugPrint(string.format("Key was NOT timed - over by %d seconds", overSeconds))
            end
            
            DebugPrint("=== End calculation ===")
        else
            DebugPrint("ERROR: Cannot calculate timing - missing data:")
            DebugPrint("  activeDungeonInfo exists:", tostring(MPH.activeDungeonInfo ~= nil))
            if MPH.activeDungeonInfo then
                DebugPrint("  startTime exists:", tostring(MPH.activeDungeonInfo.startTime ~= nil))
                DebugPrint("  timeLimit exists:", tostring(MPH.activeDungeonInfo.timeLimit ~= nil))
            end
        end
        
        -- Store the timing result
        if MPH.activeDungeonInfo then
            MPH.activeDungeonInfo.wasInTime = wasInTime
            DebugPrint("Stored wasInTime in activeDungeonInfo:", tostring(wasInTime))
        end
        
        C_Timer.After(0.5, function()
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
        print("/mph debugtooltips - Toggle tooltip debug spam (keep OFF normally)")
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
    elseif msg == "debugtooltips" then
        MPlusHonorDB.settings.debugTooltips = not MPlusHonorDB.settings.debugTooltips
        print(string.format("|cff00ff00MPlusHonor:|r Tooltip debug spam %s", 
            MPlusHonorDB.settings.debugTooltips and "|cff00ff00enabled|r" or "|cffff0000disabled|r"))
        if MPlusHonorDB.settings.debugTooltips then
            print("|cffffcc00Warning:|r This will spam your chat when hovering over players. Use /mph debugtooltips to turn off.")
        end
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
