-- Load AceConfig-3.0
ClearQuests = LibStub("AceAddon-3.0"):NewAddon("ClearQuests")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDB = LibStub("AceDB-3.0")
local CQ = ClearQuests
local function tableContains(tbl, val) for _, entry in pairs(tbl) do if entry == val then return true end end end

-- Helper function to determine if a quest is trivial
local function isQuestTrivial(playerLevel, questLevel) return playerLevel >= (questLevel or 0) + 10 end

-- Helper function to check if a quest has partial progress
local function hasPartialProgress(questIndex)
	local numObjectives = GetNumQuestLeaderBoards(questIndex)
	if numObjectives == 0 then return false end

	for i = 1, numObjectives do
		local description, objectiveType, isCompleted = GetQuestLogLeaderBoard(i, questIndex)

		-- Quick check: if objective is completed, we have progress
		if isCompleted then return true end

		-- For non-completed objectives, check for partial progress
		if description then
			-- Parse the description to check for progress pattern like "4/6" or "1/1"
			local current, total = description:match("(%d+)/(%d+)")
			if current and total then
				-- Convert to numbers and check if there's any progress
				local currentNum = tonumber(current)
				local totalNum = tonumber(total)
				if currentNum and totalNum and currentNum > 0 then
					return true -- Has some progress
				end
			end
		end
	end
	return false
end

-- Helper function to check if a quest should be kept based on type and settings
local function shouldKeepQuest(titleText, level, questTag, isComplete, isDaily, options, playerLevel, questIndex)
	-- Always keep these special quests regardless of settings
	if titleText:match("Prestige") or titleText:match("Mentorship") then return true end

	-- Check if quest is trivial (more than 9 levels below player)
	local trivial = isQuestTrivial(playerLevel, level)

	-- Path to Ascension quests
	local isPathToAscension = titleText:match("Path to Ascension")
	if options.keepAscension and isPathToAscension then return true end

	-- Completed quests
	if options.keepComplete and isComplete == 1 then
		-- Keep if non-trivial OR if keeping trivial completed is enabled
		if not trivial or options.keepTrivialComplete then return true end
	end

	-- Daily quests
	if options.keepDaily and isDaily == 1 then return true end

	-- Dungeon quests
	if options.keepDungeon and questTag == "Dungeon" then
		-- Keep if non-trivial OR if keeping trivial dungeons is enabled
		if not trivial or options.keepTrivialDungeon then return true end
	end

	-- Partial progress quests
	if options.keepPartialProgress and hasPartialProgress(questIndex) then
		-- Keep if non-trivial OR if keeping trivial partial progress is enabled
		if not trivial or options.keepTrivialPartialProgress then return true end
	end

	-- Whitelist check
	if tableContains(options.whitelist, titleText) then return true end

	return false
end

-- Function to get list of quests that will be abandoned
local function getQuestsToAbandon()
	local options = CQ.db.global
	local playerLevel = UnitLevel("player")
	local questsToAbandon = {}

	for i = 1, GetNumQuestLogEntries() do
		local titleText, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily, questID = GetQuestLogTitle(i)

		-- Skip headers and invalid entries
		if titleText and not isHeader then
			local keepQuest = shouldKeepQuest(titleText, level, questTag, isComplete, isDaily, options, playerLevel, i)

			if not keepQuest then
				table.insert(questsToAbandon, {
					index = i,
					title = titleText,
					level = level or "?",
					tag = questTag or ""
				})
			end
		end
	end

	return questsToAbandon
end

-- Function to show confirmation dialog
local function showConfirmationDialog(questsToAbandon, reopenOptions)
	local AceGUI = LibStub("AceGUI-3.0")
	AceConfigDialog:Close("ClearQuests")

	if #questsToAbandon == 0 then
		-- No quests to abandon
		local frame = AceGUI:Create("Frame")
		frame:SetTitle("Clear Quests - No Action Needed")
		frame:SetLayout("Flow")
		frame:SetWidth(400)
		frame:SetHeight(150)

		local label = AceGUI:Create("Label")
		label:SetText("No quests will be abandoned based on your current settings.")
		label:SetFullWidth(true)
		frame:AddChild(label)

		frame:SetCallback("OnClose", function(widget) if reopenOptions then AceConfigDialog:Open("ClearQuests") end end)

		frame:Show()
		return
	end

	-- Create confirmation dialog
	local frame = AceGUI:Create("Frame")
	frame:SetTitle("Clear Quests - Confirmation")
	frame:SetLayout("Flow")
	frame:SetWidth(400)
	frame:SetHeight(245)

	local label = AceGUI:Create("Label")
	label:SetText("The following " .. #questsToAbandon .. " quest" .. (#questsToAbandon == 1 and "" or "s") .. " will be abandoned:")
	label:SetFullWidth(true)
	frame:AddChild(label)

	-- Create scrollable list of quests
	local scrollContainer = AceGUI:Create("ScrollFrame")
	scrollContainer:SetLayout("List")
	scrollContainer:SetFullWidth(true)
	scrollContainer:SetHeight(160)
	frame:AddChild(scrollContainer)

	-- Add individual quest labels to the scroll container
	for _, quest in ipairs(questsToAbandon) do
		local levelText = quest.level ~= "?" and ("[" .. quest.level .. "] ") or ""
		local tagText = quest.tag ~= "" and (" (" .. quest.tag .. ")") or ""
		local questText = levelText .. quest.title .. tagText

		local questLabel = AceGUI:Create("Label")
		questLabel:SetText(questText)
		questLabel:SetFullWidth(true)
		scrollContainer:AddChild(questLabel)
	end

	-- Add abandon button directly to frame
	local confirmButton = AceGUI:Create("Button")
	confirmButton:SetText("Abandon These Quests")
	confirmButton:SetWidth(250)
	confirmButton:SetHeight(21)
	confirmButton:SetCallback("OnClick", function()
		frame:SetCallback("OnClose", function() end) -- Override with empty function to prevent reopening
		frame:Release()
		CQ:ExecuteClearQuests(questsToAbandon) -- Pass the pre-calculated table
	end)
	frame:AddChild(confirmButton)

	frame:SetCallback("OnClose", function(widget) if reopenOptions then AceConfigDialog:Open("ClearQuests") end end)

	frame:Show()
end

-- The actual quest clearing function
function CQ:ExecuteClearQuests(questsToAbandon)
	if #questsToAbandon == 0 then return end

	-- Abandon quests in reverse order to maintain correct indices
	for i = #questsToAbandon, 1, -1 do
		local quest = questsToAbandon[i]
		SelectQuestLogEntry(quest.index)
		SetAbandonQuest()
		AbandonQuest()
	end

	-- Print summary of abandoned quests
	local questDescriptions = {}
	for _, quest in ipairs(questsToAbandon) do
		local levelText = quest.level ~= "?" and ("[" .. quest.level .. "] ") or ""
		local tagText = quest.tag ~= "" and (" (" .. quest.tag .. ")") or ""
		local questDescription = levelText .. quest.title .. tagText
		table.insert(questDescriptions, questDescription)
	end

	print("|cFFFFD700ClearQuests:|r Abandoned " .. #questsToAbandon .. " quest" .. (#questsToAbandon == 1 and "" or "s") .. ": " .. table.concat(questDescriptions, ", "))
end

-- New main function that shows confirmation first
function CQ:ClearQuests(reopenOptions)
	local questsToAbandon = getQuestsToAbandon()
	showConfirmationDialog(questsToAbandon, reopenOptions)
end

-- Function to open the Whitelist management window
local function OpenWhitelistWindow()
	local AceGUI = LibStub("AceGUI-3.0")
	AceConfigDialog:Close("ClearQuests")
	local frame = AceGUI:Create("Frame")
	frame:SetTitle("Manage Whitelist")
	frame:SetLayout("Flow")
	frame:SetWidth(400)
	frame:SetHeight(300)

	local dropdownlist = AceGUI:Create("Dropdown")
	dropdownlist:SetLabel("Select Quest")
	dropdownlist:SetWidth(300)
	frame:AddChild(dropdownlist)
	tablelist = {}
	for i = 1, GetNumQuestLogEntries() do
		local title, _, _, _, isHeader, _, _, questID = GetQuestLogTitle(i)
		if title and not isHeader then table.insert(tablelist, title) end
	end
	dropdownlist:SetList(tablelist)
	local addButton = AceGUI:Create("Button")
	local list = AceGUI:Create("MultiLineEditBox")

	addButton:SetText("Add")
	addButton:SetWidth(100)
	addButton:SetCallback("OnClick", function()
		local dropdownIndex = dropdownlist:GetValue()
		local newString = tablelist[dropdownIndex]
		if newString and newString ~= "" then
			table.insert(CQ.db.global.whitelist, newString)
			list:SetText(table.concat(CQ.db.global.whitelist, "\n"))
		end
	end)
	frame:AddChild(addButton)

	list:SetLabel("Whitelist")
	list:SetWidth(380)
	list:SetHeight(150)
	list:SetText(table.concat(CQ.db.global.whitelist, "\n"))
	list:SetFullHeight(true)
	list:SetCallback("OnEnterPressed", function(widget, event, text)
		-- Update the list when Enter is pressed
		CQ.db.global.whitelist = {}
		for line in text:gmatch("[^\r\n]+") do table.insert(CQ.db.global.whitelist, line) end
	end)
	frame:AddChild(list)

	frame:SetCallback("OnClose", function(widget)
		AceConfigDialog:Open("ClearQuests") -- Refresh the options when the window is closed
	end)

	frame:Show()
end

local defaults = {
	global = {
		keepComplete = true,
		keepDaily = true,
		keepDungeon = true,
		keepTrivialDungeon = false,
		keepTrivialComplete = false,
		keepAscension = true,
		keepPartialProgress = false,
		keepTrivialPartialProgress = false,
		whitelist = {}
	}
}

local OptionsTable = {
	type = "group",
	get = function(info) return CQ.db.global[info[#info]] end,
	set = function(info, val) CQ.db.global[info[#info]] = val end,
	args = {
		run = {
			name = "Clear Your Quest Log",
			type = "execute",
			width = "full",
			func = function(msg) CQ:ClearQuests(true) end,
			desc = "Runs the script to clear your quest log. Respects the options set below",
			order = 1
		},
		description = {
			name = "Will always keep mentorship quest and prestige quest when clearing the quest log. Set the options below to include other types of quests which you would like to keep.",
			type = "description",
			width = "full",
			order = 2
		},
		optionheader = {
			name = "Options",
			type = "header",
			order = 3
		},
		keepDaily = {
			name = "Keep Daily",
			desc = "Keep quests marked as daily.",
			type = "toggle",
			order = 11
		},
		keepAscension = {
			name = "Keep Path to Ascension",
			desc = "Keep quests related to the Path to Ascension.",
			type = "toggle",
			order = 12
		},
		keepDungeon = {
			name = "Keep Dungeon",
			desc = "Keep non-trivial dungeon quests.",
			type = "toggle",
			order = 13
		},
		keepTrivialDungeon = {
			name = "Keep Trivial Dungeon",
			desc = "Keep dungeon quests more than 9 levels below your level.",
			type = "toggle",
			order = 14
		},
		keepComplete = {
			name = "Keep Complete",
			desc = "Keep non-trivial quests marked as complete.",
			type = "toggle",
			order = 15
		},
		keepTrivialComplete = {
			name = "Keep Trivial Completed",
			desc = "Keep completed quests more than 9 levels below your level.",
			type = "toggle",
			order = 16
		},
		keepPartialProgress = {
			name = "Keep Partial Progress",
			desc = "Keep non-trivial quests with any progress made (objectives completed or partial objectives).",
			type = "toggle",
			order = 17
		},
		keepTrivialPartialProgress = {
			name = "Keep Trivial Partial Progress",
			desc = "Keep quests with partial progress more than 9 levels below your level.",
			type = "toggle",
			order = 18
		},
		manageCustomStrings = {
			name = "Manage Whitelist",
			type = "execute",
			width = "full",
			func = OpenWhitelistWindow,
			order = 19
		}
	}
}

AceConfig:RegisterOptionsTable("ClearQuests", OptionsTable)
AceConfigDialog:AddToBlizOptions("ClearQuests")

function CQ:OnInitialize() self.db = AceDB:New("CQOptions", defaults, true) end

SLASH_CLEARQUESTS1 = "/cq"
SLASH_CLEARQUESTS2 = "/clearquests"
SlashCmdList["CLEARQUESTS"] = function(msg)
	-- Trim whitespace and convert to lowercase
	local command = string.lower(string.trim and string.trim(msg) or msg:match("^%s*(.-)%s*$"))

	if command == "clear" then
		-- Direct execution - run the quest clearing with confirmation dialog
		CQ:ClearQuests(false) -- Don't reopen options when called from command line
	elseif command == "force" then
		-- Immediate execution without confirmation dialog
		local questsToAbandon = getQuestsToAbandon()
		if #questsToAbandon > 0 then
			CQ:ExecuteClearQuests(questsToAbandon)
		else
			print("|cFFFFD700ClearQuests:|r No quests to abandon based on your current settings.")
		end
	elseif command == "help" then
		-- Show help information
		print("|cFFFFD700ClearQuests Commands:|r")
		print("  |c0000FFFF/cq|r or |c0000FFFF/clearquests|r - Open settings GUI")
		print("  |c0000FFFF/cq clear|r - Show confirmation dialog before clearing")
		print("  |c0000FFFF/cq force|r - Clear quests immediately without confirmation")
		print("  |c0000FFFF/cq help|r - Show this help")
	else
		-- Default behavior - open the settings GUI
		AceConfigDialog:SetDefaultSize("ClearQuests", 400, 310)
		AceConfigDialog:Open("ClearQuests")
	end
end
