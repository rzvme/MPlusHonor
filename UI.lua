-- MPlusHonor UI
local MPH = MPlusHonor
MPH.UI = {}

-- Create main rating window
function MPH.UI:CreateRatingWindow()
    if self.frame then return end
    
    local frame = CreateFrame("Frame", "MPlusHonorFrame", UIParent, "BackdropTemplate")
    frame:SetSize(600, 280)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("Mythic+ Completed!")
    frame.title = title
    
    -- Dungeon info
    local dungeonInfo = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dungeonInfo:SetPoint("TOP", title, "BOTTOM", 0, -10)
    dungeonInfo:SetText("")
    frame.dungeonInfo = dungeonInfo
    
    -- Left side: Group members
    local memberLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    memberLabel:SetPoint("TOPLEFT", 20, -70)
    memberLabel:SetText("Group Members:")
    
    local memberList = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    memberList:SetPoint("TOPLEFT", memberLabel, "BOTTOMLEFT", 0, -8)
    memberList:SetText("")
    memberList:SetJustifyH("LEFT")
    memberList:SetWidth(180)
    frame.memberList = memberList
    
    -- Right side: URL section
    local urlLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    urlLabel:SetPoint("TOPLEFT", 220, -70)
    urlLabel:SetText("Rating URL:")
    
    -- URL EditBox
    local urlBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    urlBox:SetSize(350, 30)
    urlBox:SetPoint("TOPLEFT", urlLabel, "BOTTOMLEFT", 0, -10)
    urlBox:SetAutoFocus(false)
    urlBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    urlBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    urlBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            -- Prevent user from editing
            self:SetText(frame.currentURL or "")
            self:HighlightText()
        end
    end)
    frame.urlBox = urlBox
    
    -- Copy button
    local copyButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    copyButton:SetSize(140, 30)
    copyButton:SetPoint("TOP", urlBox, "BOTTOM", 0, -15)
    copyButton:SetText("Copy URL")
    copyButton:SetNormalFontObject("GameFontNormal")
    copyButton:SetHighlightFontObject("GameFontHighlight")
    copyButton:SetScript("OnClick", function()
        urlBox:SetFocus()
        urlBox:HighlightText()
        print("|cff00ff00MPlusHonor:|r URL selected! Press Ctrl+C to copy, then paste in your browser.")
    end)
    
    -- Info text
    local infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOP", copyButton, "BOTTOM", 0, -10)
    infoText:SetText("Press Ctrl+C to copy")
    infoText:SetTextColor(0.7, 0.7, 0.7)
    
    -- Instructions
    local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instructions:SetPoint("BOTTOM", 0, 20)
    instructions:SetText("Paste the URL in your browser to rate your group members")
    instructions:SetTextColor(1, 0.82, 0)
    
    -- Close button
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function() frame:Hide() end)
    
    self.frame = frame
end

-- Show the rating window
function MPH.UI:ShowRatingWindow(runData)
    self:CreateRatingWindow()
    
    local frame = self.frame
    
    -- Update dungeon info
    local inTimeText = runData.wasInTime and "|cff00ff00Timed|r" or "|cffff0000Not Timed|r"
    frame.dungeonInfo:SetText(string.format("%s |cffffcc00+%d|r - %s", 
        runData.mapName, runData.level, inTimeText))
    
    -- Update URL
    frame.currentURL = runData.url
    frame.urlBox:SetText(runData.url)
    
    -- Update member list
    local memberText = ""
    for i, member in ipairs(runData.members) do
        local nameColor = member.isPlayer and "|cff00ff00" or "|cffffffff"
        local playerTag = member.isPlayer and " (You)" or ""
        memberText = memberText .. string.format("%s%s-%s%s|r\n", 
            nameColor, member.name, member.realm, playerTag)
    end
    frame.memberList:SetText(memberText)
    
    frame:Show()
end

-- Create character rating display (for tooltip integration)
function MPH.UI:CreateCharacterRatingTooltip()
    -- Use TooltipDataProcessor for modern WoW (11.0+)
    if TooltipDataProcessor then
        print("|cff00ff00MPlusHonor:|r Using TooltipDataProcessor (modern API)")
        
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
            if MPlusHonorDB and MPlusHonorDB.settings and MPlusHonorDB.settings.debug then
                print("|cffff9900MPH Tooltip:|r TooltipDataProcessor fired")
            end
            
            if tooltip ~= GameTooltip then return end
            if not data or not data.guid then return end
            
            -- Get unit from GUID
            local unitToken
            if UnitGUID("mouseover") == data.guid then
                unitToken = "mouseover"
            elseif UnitGUID("target") == data.guid then
                unitToken = "target"
            end
            
            if not unitToken then return end
            if not UnitIsPlayer(unitToken) then return end
            
            local name, realm = UnitFullName(unitToken)
            if not name then return end
            
            realm = realm or GetRealmName()
            if realm then
                realm = realm:gsub("%s+", "")
            end
            
            local fullName = name .. "-" .. (realm or "NoRealm")
            
            if MPlusHonorDB and MPlusHonorDB.settings and MPlusHonorDB.settings.debug then
                print("|cffff9900MPH Tooltip:|r Looking for:", fullName)
            end
            
            local ratingData = MPH:GetCharacterRating(name, realm)
            
            if ratingData then
                if MPlusHonorDB and MPlusHonorDB.settings and MPlusHonorDB.settings.debug then
                    print("|cff00ff00MPH Tooltip:|r FOUND rating data! Adding lines...")
                end
                
                -- Add blank line
                tooltip:AddLine(" ")
                
                -- Add header
                tooltip:AddLine("M+ Honor Rating", 0.25, 0.78, 0.92, true)
                
                if ratingData.averageRating and ratingData.totalRatings > 0 then
                    local stars = string.rep("*", math.floor(ratingData.averageRating))
                    tooltip:AddDoubleLine(
                        "Rating:", 
                        string.format("%.1f/5.0 %s", ratingData.averageRating, stars),
                        1, 1, 1,
                        1, 0.82, 0
                    )
                    tooltip:AddDoubleLine(
                        "Based on:",
                        string.format("%d ratings", ratingData.totalRatings),
                        1, 1, 1,
                        0.7, 0.7, 0.7
                    )
                else
                    tooltip:AddLine("No ratings yet", 0.7, 0.7, 0.7)
                end
                
                tooltip:AddLine("Visit mplushonor.guildhub.eu", 0.5, 0.5, 0.5, true)
                
                -- Force tooltip to update
                tooltip:Show()
                
                if MPlusHonorDB and MPlusHonorDB.settings and MPlusHonorDB.settings.debug then
                    print("|cff00ff00MPH Tooltip:|r Lines added successfully!")
                end
            else
                if MPlusHonorDB and MPlusHonorDB.settings and MPlusHonorDB.settings.debug then
                    print("|cffff0000MPH Tooltip:|r No rating found")
                end
            end
        end)
        
        print("|cff00ff00MPlusHonor:|r Tooltip processor registered!")
        
    else
        -- Fallback for older versions
        print("|cff00ff00MPlusHonor:|r Using legacy tooltip hook")
        
        GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip)
            if MPlusHonorDB and MPlusHonorDB.settings and MPlusHonorDB.settings.debug then
                print("|cffff9900MPH Tooltip:|r Legacy hook fired")
            end
            
            local _, unit = tooltip:GetUnit()
            if not unit then return end
            if not UnitIsPlayer(unit) then return end
            
            local name, realm = UnitFullName(unit)
            if not name then return end
            
            realm = realm or GetRealmName()
            if realm then
                realm = realm:gsub("%s+", "")
            end
            
            local fullName = name .. "-" .. (realm or "NoRealm")
            
            if MPlusHonorDB and MPlusHonorDB.settings and MPlusHonorDB.settings.debug then
                print("|cffff9900MPH Tooltip:|r Looking for:", fullName)
            end
            
            local ratingData = MPH:GetCharacterRating(name, realm)
            
            if ratingData then
                if MPlusHonorDB and MPlusHonorDB.settings and MPlusHonorDB.settings.debug then
                    print("|cff00ff00MPH Tooltip:|r FOUND rating data!")
                end
                
                tooltip:AddLine(" ")
                tooltip:AddLine("M+ Honor Rating", 0.25, 0.78, 0.92)
                
                if ratingData.averageRating and ratingData.totalRatings > 0 then
                    local stars = string.rep("*", math.floor(ratingData.averageRating))
                    tooltip:AddLine(string.format("Rating: %.1f/5.0 %s", ratingData.averageRating, stars), 1, 1, 1)
                    tooltip:AddLine(string.format("Based on: %d ratings", ratingData.totalRatings), 0.7, 0.7, 0.7)
                else
                    tooltip:AddLine("No ratings yet", 0.7, 0.7, 0.7)
                end
                
                tooltip:AddLine("Visit mplushonor.guildhub.eu", 0.5, 0.5, 0.5)
                tooltip:Show()
            end
        end)
        
        print("|cff00ff00MPlusHonor:|r Legacy tooltip hook installed!")
    end
end

-- Initialize UI components
function MPH.UI:Initialize()
    self:CreateRatingWindow()
    self:CreateCharacterRatingTooltip()
end

-- Initialize after player login
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    MPH.UI:Initialize()
end)