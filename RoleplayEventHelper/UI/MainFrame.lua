local ADDON_NAME, REH = ...

local UI = REH.UI
local MainFrame = {}
UI.MainFrame = MainFrame

local WIDTH, HEIGHT = 820, 600
local LIST_WIDTH = 190
local PREVIEW_HEIGHT = 150
local BOTTOM_BAR_HEIGHT = 32
local TAB_HEIGHT = 24

local frame

--------------------------------------------------------------------------------
-- Channel options
--------------------------------------------------------------------------------

-- Kinds that need a typed name are handled by the slash command rather than the
-- popup, since the popup only offers a choice, not a text entry.
local POPUP_CHANNEL_KINDS = {
	"PREVIEW", "SAY", "YELL", "EMOTE", "PARTY", "RAID",
	"RAID_WARNING", "INSTANCE_CHAT", "GUILD", "OFFICER",
}

local function BuildChannelOptions()
	local options = {}

	for _, kind in ipairs(POPUP_CHANNEL_KINDS) do
		options[#options + 1] = {
			value = kind,
			label = REH.DISPLAY.channel[kind] or kind,
		}
	end

	return options
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function CreateTitleBar(parent)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
	bar:SetHeight(28)
	UI.AddBackground(bar, 0.12, 0.12, 0.16, 0.95)

	local title = UI.CreateLabel(bar, "Roleplay Event Helper", "GameFontNormal")
	title:SetPoint("LEFT", bar, "LEFT", 10, 0)

	local close = UI.SafeCreateFrame("Button", nil, parent, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function()
		MainFrame:Hide()
	end)

	bar.title = title
	bar.closeButton = close
	return bar
end

local function Build()
	frame = CreateFrame("Frame", "RoleplayEventHelperFrame", UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:Hide()

	UI.AddBackground(frame, 0.03, 0.03, 0.05, 0.94)
	UI.AddBorder(frame, 0.3, 0.3, 0.35, 1)

	local titleBar = CreateTitleBar(frame)
	frame.titleBar = titleBar

	-- The window position is remembered between sessions, so it stays wherever
	-- the host dragged it relative to the rest of their UI.
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()

		local point, _, relativePoint, x, y = self:GetPoint()
		local settings = REH.Database:GetSettings()
		settings.framePoint = {
			point = point, relativePoint = relativePoint, x = x, y = y,
		}
	end)

	----------------------------------------------------------------------------
	-- Preset list
	----------------------------------------------------------------------------

	local listHeight = HEIGHT - 28 - PREVIEW_HEIGHT - BOTTOM_BAR_HEIGHT - 24

	local presetList = UI.PresetList:Create(frame, LIST_WIDTH, listHeight, function()
		MainFrame:RefreshAll()
	end)
	presetList:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -36)
	frame.presetList = presetList

	----------------------------------------------------------------------------
	-- Editor area
	----------------------------------------------------------------------------

	local editorWidth = WIDTH - LIST_WIDTH - 30
	local editorPanel = UI.CreatePanel(frame)
	editorPanel:SetSize(editorWidth, listHeight)
	editorPanel:SetPoint("TOPLEFT", presetList, "TOPRIGHT", 8, 0)
	frame.editorPanel = editorPanel

	local scroll, content = UI.CreateScrollArea(editorPanel,
		editorWidth - 30, listHeight - TAB_HEIGHT - 16)
	scroll:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 8, -(TAB_HEIGHT + 8))
	frame.editorScroll = scroll

	local editors = UI.Editors:Create(content, editorWidth - 40, function()
		MainFrame:RefreshPreview()
		-- The Options tab can hide or show the minimap button.
		UI.MinimapButton:ApplySettings()
	end)
	frame.editors = editors

	-- A field that grew changes the page height, so the scroll child has to
	-- follow or the bottom of the page becomes unreachable.
	editors.onLayoutChanged = function()
		local scrollContent = frame.editorScroll and frame.editorScroll.content
		if scrollContent then
			scrollContent:SetHeight(math.max(editors:GetActiveHeight(), 1))
		end
	end

	-- Tab strip. Plain buttons rather than Blizzard's tab templates, which have
	-- changed shape more than once.
	frame.tabButtons = {}
	local tabX = 8

	for index, tab in ipairs(REH.Fields:GetTabs()) do
		local width = 8 + math.max(50, #tab.title * 8)
		local button = UI.CreateButton(editorPanel, tab.title, width, TAB_HEIGHT - 2, function()
			MainFrame:SelectTab(index)
		end)
		button:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", tabX, -4)
		frame.tabButtons[index] = button
		tabX = tabX + width + 2
	end

	----------------------------------------------------------------------------
	-- Preview
	----------------------------------------------------------------------------

	local preview = UI.Preview:Create(frame, WIDTH - 16, PREVIEW_HEIGHT)
	preview:SetPoint("TOPLEFT", presetList, "BOTTOMLEFT", 0, -8)
	frame.preview = preview

	----------------------------------------------------------------------------
	-- Bottom bar
	----------------------------------------------------------------------------

	local channelButton = UI.CreateButton(frame, "Channel", 220, 24)
	channelButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8)
	frame.channelButton = channelButton

	local popup = UI.CreatePopupSelector(frame, 220)
	frame.channelPopup = popup

	channelButton:SetScript("OnClick", function(self)
		popup:Toggle(BuildChannelOptions(), function(value)
			local preset = REH.Database:GetActivePreset()
			REH.Announcer:SetChannel(preset, value)
			MainFrame:RefreshAll()
		end, self)
	end)

	UI.SetTooltip(channelButton, "Announce to",
		"Where the rules are sent. Custom channels and whispers are set with /reh channel channel <name> or /reh channel whisper <name>.")

	local announceButton = UI.CreateButton(frame, "Announce Rules", 160, 24, function()
		local preset, name = REH.Database:GetActivePreset()
		REH.Announcer:Announce(preset, name)
		MainFrame:RefreshAll()
	end)
	announceButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
	frame.announceButton = announceButton

	local cancelButton = UI.CreateButton(frame, "Cancel", 90, 24, function()
		REH.Announcer:Cancel()
		MainFrame:RefreshAll()
	end)
	cancelButton:SetPoint("RIGHT", announceButton, "LEFT", -6, 0)
	frame.cancelButton = cancelButton

	local WATCH_OPTIONS = {
		{ value = "off", label = "Watcher: off" },
		{ value = "local", label = "Watcher: verdicts to me" },
		{ value = "announce", label = "Watcher: verdicts to channel" },
	}

	local watchButton = UI.CreateCycleButton(frame, WATCH_OPTIONS, 210, function(value)
		REH.RollWatcher:SetMode(value)
		MainFrame:RefreshPreview()
	end)
	watchButton:SetPoint("LEFT", channelButton, "RIGHT", 6, 0)
	frame.watchButton = watchButton

	UI.SetTooltip(watchButton, "Roll watcher",
		"Reads /roll results and calls each one a success or failure against these rules. Always starts off when you log in.")

	-- One press does what a host actually does at that moment: call the round,
	-- tell the room, and put the roll log where they can see it. Right-click
	-- still just opens the log, for checking back without starting anything.
	local logButton = UI.CreateButton(frame, "Start Round", 110, 24)
	logButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	logButton:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			UI.RollLog:Toggle()
			return
		end

		REH.RollWatcher:BeginRound()
		UI.RollLog:Show()
		MainFrame:RefreshPreview()
	end)
	logButton:SetPoint("LEFT", watchButton, "RIGHT", 6, 0)
	frame.logButton = logButton

	UI.SetTooltip(logButton, "Start Round", function()
		local preset = REH.Database:GetActivePreset()
		local where = REH.Announcer:DescribeChannel(preset.channel)

		if not preset.rounds.announce then
			return "Starts a new round and opens the roll log.\n\nAnnouncing rounds is switched off on the Watcher tab.\n\nRight-click: just open the log."
		end

		return ("Starts a new round, announces it to %s, and opens the roll log.\n\nRight-click: just open the log."):format(where)
	end)

	local statusText = UI.CreateLabel(frame, "", "GameFontDisableSmall")
	statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 38)
	statusText:SetWidth(WIDTH - 200)
	frame.statusText = statusText

	-- Escape closes the window, the way every other panel behaves.
	if UISpecialFrames then
		table.insert(UISpecialFrames, "RoleplayEventHelperFrame")
	end

	MainFrame.frame = frame
	MainFrame:SelectTab(1)
	MainFrame:RefreshAll()

	return frame
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

function MainFrame:IsBuilt()
	return frame ~= nil
end

function MainFrame:GetFrame()
	if not frame then
		Build()
		self:RestorePosition()
	end
	return frame
end

function MainFrame:RestorePosition()
	if not frame then
		return
	end

	local saved = REH.Database:GetSettings().framePoint or {}
	frame:ClearAllPoints()
	frame:SetPoint(saved.point or "CENTER", UIParent,
		saved.relativePoint or "CENTER", saved.x or 0, saved.y or 0)
end

function MainFrame:SelectTab(index)
	if not frame then
		return
	end

	frame.activeTab = index
	frame.editors:ShowTab(index)

	for buttonIndex, button in ipairs(frame.tabButtons) do
		if button.SetEnabled then
			button:SetEnabled(buttonIndex ~= index)
		end
	end

	-- The scroll child has to match the page that is now visible, or the
	-- scrollbar will size itself from whichever page happened to be tallest.
	local content = frame.editorScroll.content
	if content then
		content:SetHeight(math.max(frame.editors:GetActiveHeight(), 1))
	end
end

function MainFrame:RefreshPreview()
	if not frame then
		return
	end

	local preset = REH.Database:GetActivePreset()
	frame.preview:Refresh(preset)

	----------------------------------------------------------------------------
	-- Announce controls
	----------------------------------------------------------------------------

	local channel = preset.channel
	frame.channelButton:SetText(REH.Announcer:DescribeChannel(channel))
	frame.watchButton:SetValue(REH.RollWatcher:GetMode())

	local sending = REH.Announcer:IsSending()
	local available, reason = REH.Announcer:CheckAvailability(channel)

	if frame.announceButton.SetEnabled then
		frame.announceButton:SetEnabled(available and not sending)
	end
	if frame.cancelButton.SetEnabled then
		frame.cancelButton:SetEnabled(sending)
	end

	-- A disabled button that does not say why is a bug report waiting to
	-- happen, so the reason goes both on the bar and in the tooltip.
	if sending then
		local sent, total = REH.Announcer:Progress()
		frame.statusText:SetText(("Sending %d of %d..."):format(sent, total))
	elseif not available then
		frame.statusText:SetText("|cffffd100" .. tostring(reason) .. "|r")
	else
		frame.statusText:SetText("")
	end

	UI.SetTooltip(frame.announceButton, "Announce Rules", function()
		if REH.Announcer:IsSending() then
			return "An announcement is already in progress."
		end

		local ok, why = REH.Announcer:CheckAvailability(
			REH.Database:GetActivePreset().channel)
		if not ok then
			return why
		end

		return "Send these rules to the chosen channel."
	end)
end

function MainFrame:RefreshAll()
	if not frame then
		return
	end

	frame.presetList:Refresh()
	frame.editors:Refresh()
	self:RefreshPreview()
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

function MainFrame:Show()
	local window = self:GetFrame()
	self:RefreshAll()
	window:Show()
end

function MainFrame:Hide()
	if frame then
		frame:Hide()
	end
end

function MainFrame:Toggle()
	if frame and frame:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

function MainFrame:IsShown()
	return frame ~= nil and frame:IsShown()
end
