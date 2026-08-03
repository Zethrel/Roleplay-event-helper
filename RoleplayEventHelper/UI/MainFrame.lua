local ADDON_NAME, REH = ...

local UI = REH.UI
local MainFrame = {}
UI.MainFrame = MainFrame

local WIDTH, HEIGHT = 820, 600
local LIST_WIDTH = 190
local PREVIEW_HEIGHT = 150
local BOTTOM_BAR_HEIGHT = 32
local TAB_HEIGHT = 24
local TITLE_HEIGHT = 28

-- The strip between the preview and the bottom bar where the status line
-- lives ("You are not in a party", "Sending 3 of 13..."). It needs reserving:
-- laid out without it, the preview's bottom edge sits over the text and the
-- host reads half a sentence.
local STATUS_HEIGHT = 18

-- The window can be dragged out. The minimum is the size everything was laid
-- out against, because the bottom bar is a fixed row of buttons and shrinking
-- below that would slide them into each other; the maximum is generous rather
-- than a judgement about what a host needs.
local MIN_WIDTH, MIN_HEIGHT = WIDTH, 460
local MAX_WIDTH, MAX_HEIGHT = 1800, 1200

-- Where the extra height goes. Most of it to the preview, since reading the
-- whole announcement without scrolling is the reason to make the window bigger
-- in the first place; the rest to the editor, which also runs long.
local PREVIEW_SHARE_OF_EXTRA = 0.6

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

	-- Tab strip. Plain buttons rather than Blizzard's tab templates, which have
	-- changed shape more than once.
	--
	-- Built before the scroll area because it wraps: the strip is as many rows
	-- as the tabs need, and the editor below starts under whatever that comes to
	-- rather than under an assumed single row.
	frame.tabButtons = {}

	local tabX, tabY = 8, 4
	local tabRight = editorWidth - 8

	for index, tab in ipairs(REH.Fields:GetTabs()) do
		local width = 8 + math.max(50, #tab.title * 8)

		if tabX > 8 and tabX + width > tabRight then
			tabX = 8
			tabY = tabY + TAB_HEIGHT
		end

		local button = UI.CreateButton(editorPanel, tab.title, width, TAB_HEIGHT - 2, function()
			MainFrame:SelectTab(index)
		end)
		button:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", tabX, -tabY)
		button.stripWidth = width
		frame.tabButtons[index] = button
		tabX = tabX + width + 2
	end

	local tabStripHeight = tabY + TAB_HEIGHT

	local scroll, content = UI.CreateScrollArea(editorPanel,
		editorWidth - 30, listHeight - tabStripHeight - 16)
	scroll:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 8, -(tabStripHeight + 8))
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
	announceButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -22, 8)
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

	local watchButton = UI.CreateCycleButton(frame, WATCH_OPTIONS, 190, function(value)
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
	local logButton = UI.CreateButton(frame, "Start Round", 100, 24)
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

	----------------------------------------------------------------------------
	-- Resizing
	----------------------------------------------------------------------------

	UI.MakeResizable(frame, {
		minWidth = MIN_WIDTH, minHeight = MIN_HEIGHT,
		maxWidth = MAX_WIDTH, maxHeight = MAX_HEIGHT,
		defaultWidth = WIDTH, defaultHeight = HEIGHT,
		tooltip = "Drag to make the window bigger. Most of the extra height goes to the preview.\n\nDouble-click to go back to the default size.",
		onResize = function() MainFrame:Layout() end,
		onSaved = function() MainFrame:SaveSize() end,
	})

	-- Escape closes the window, the way every other panel behaves.
	if UISpecialFrames then
		table.insert(UISpecialFrames, "RoleplayEventHelperFrame")
	end

	MainFrame.frame = frame
	MainFrame:RestoreSize()
	MainFrame:Layout()
	MainFrame:SelectTab(1)
	MainFrame:RefreshAll()

	return frame
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

--- How the interior is divided at a given window size. Pure arithmetic, kept
--- apart from the frames so the sizing rules can be tested directly.
function MainFrame:Measure(width, height)
	local interior = height - TITLE_HEIGHT - BOTTOM_BAR_HEIGHT - STATUS_HEIGHT - 24

	local extra = math.max(height - HEIGHT, 0)
	local previewHeight = PREVIEW_HEIGHT + math.floor(extra * PREVIEW_SHARE_OF_EXTRA)

	-- Never let the preview eat the editor: past this point a taller window is
	-- worth more to the tab you are editing than to the pane below it.
	previewHeight = math.min(previewHeight, math.floor(interior * 0.55))
	previewHeight = math.max(previewHeight, 100)

	local topHeight = math.max(interior - previewHeight, 120)

	return {
		topHeight = topHeight,
		previewHeight = previewHeight,
		editorWidth = width - LIST_WIDTH - 30,
		previewWidth = width - 16,
	}
end

--- Re-wrap the tab strip for the current editor width and return its height.
function MainFrame:LayoutTabs(editorWidth)
	local tabX, tabY = 8, 4
	local tabRight = editorWidth - 8

	for _, button in ipairs(frame.tabButtons) do
		local width = button.stripWidth or button:GetWidth()

		if tabX > 8 and tabX + width > tabRight then
			tabX = 8
			tabY = tabY + TAB_HEIGHT
		end

		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", frame.editorPanel, "TOPLEFT", tabX, -tabY)
		tabX = tabX + width + 2
	end

	return tabY + TAB_HEIGHT
end

--- Fit every piece to the window's current size.
function MainFrame:Layout()
	if not frame then
		return
	end

	local size = self:Measure(frame:GetWidth(), frame:GetHeight())

	frame.presetList:Resize(size.topHeight)
	frame.editorPanel:SetSize(size.editorWidth, size.topHeight)

	local tabStripHeight = self:LayoutTabs(size.editorWidth)

	UI.ResizeScrollArea(frame.editorScroll, size.editorWidth - 30,
		size.topHeight - tabStripHeight - 16)
	frame.editorScroll:ClearAllPoints()
	frame.editorScroll:SetPoint("TOPLEFT", frame.editorPanel, "TOPLEFT", 8,
		-(tabStripHeight + 8))

	frame.editors:SetWidth(size.editorWidth - 40)

	frame.preview:Resize(size.previewWidth, size.previewHeight)
	frame.statusText:SetWidth(math.max(frame:GetWidth() - 200, 100))

	-- The scroll child follows the page that is actually visible, the same as
	-- it does when a tab is chosen.
	local content = frame.editorScroll.content
	if content and frame.editors.GetActiveHeight then
		content:SetHeight(math.max(frame.editors:GetActiveHeight(), 1))
	end
end

--------------------------------------------------------------------------------
-- Remembering the size
--------------------------------------------------------------------------------

function MainFrame:SaveSize()
	if not frame then
		return
	end

	local settings = REH.Database:GetSettings()
	settings.frameSize = {
		width = math.floor(frame:GetWidth() + 0.5),
		height = math.floor(frame:GetHeight() + 0.5),
	}
end

function MainFrame:RestoreSize()
	if not frame then
		return
	end

	local saved = REH.Database:GetSettings().frameSize or {}
	frame:SetSize(
		REH.ClampNumber(saved.width, MIN_WIDTH, MAX_WIDTH, WIDTH),
		REH.ClampNumber(saved.height, MIN_HEIGHT, MAX_HEIGHT, HEIGHT))
end

function MainFrame:ResetSize()
	if not frame then
		return
	end

	frame:SetSize(WIDTH, HEIGHT)
	self:SaveSize()
	self:Layout()
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

	elseif (preset.loot.enabled or #preset.rollEffects > 0)
		and not REH.RollWatcher:IsWatching() then
		-- Results set up with the watcher disarmed is the shape of "it does
		-- nothing and I cannot tell why": no rolls are being read at all, so
		-- neither the loot table nor any effect will ever fire.
		frame.statusText:SetText(
			"|cffffd100Results are set up, but the roll watcher is off, so no rolls are being read.|r")

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
