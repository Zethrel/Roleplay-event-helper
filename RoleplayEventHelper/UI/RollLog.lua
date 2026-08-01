local ADDON_NAME, REH = ...

local UI = REH.UI
local RollLog = {}
UI.RollLog = RollLog

local WIDTH, HEIGHT = 420, 400

local frame

-- Which round is on screen. nil means "follow the current round", so a log
-- left open during an event keeps up on its own; a number pins it to one round
-- so a host reading back through round two is not yanked forward every time
-- somebody rolls. Round 0 is every round together.
RollLog.viewing = nil

function RollLog:GetViewedRound()
	if self.viewing == nil then
		return REH.RollWatcher:GetCurrentRound()
	end
	return self.viewing
end

function RollLog:SetViewedRound(index)
	local count = REH.RollWatcher:GetRoundCount()

	if index < 0 then
		index = 0
	elseif index > count then
		index = count
	end

	-- Landing back on the current round resumes following it.
	self.viewing = (index == REH.RollWatcher:GetCurrentRound()) and nil or index
	self:Refresh()

	return index
end

--- Called when the watcher starts a round, so the window follows it.
function RollLog:OnRoundChanged()
	self.viewing = nil
	self:Refresh()
end

function RollLog:DescribeRound(index)
	if index == 0 then
		return ("All rounds (%d)"):format(REH.RollWatcher:GetRoundCount())
	end
	return ("Round %d of %d"):format(index, REH.RollWatcher:GetRoundCount())
end

--- Build the log text. Pure, so it can be tested without a frame.
function RollLog:BuildText(roundIndex)
	local watcher = REH.RollWatcher
	roundIndex = roundIndex or self:GetViewedRound()

	local entries, tallies = watcher:GetRound(roundIndex)
	local preset = REH.Database:GetActivePreset()

	if #entries == 0 then
		if roundIndex > 0 and watcher:GetRoundCount() > 1 then
			return "|cff808080Nothing rolled in this round yet.|r"
		end
		return "|cff808080No rolls recorded yet.|r"
	end

	local lines = {}

	for _, entry in ipairs(entries) do
		-- Which round a roll belongs to only needs saying when several are on
		-- screen at once.
		local prefix = ""
		if roundIndex == 0 and entry.round then
			prefix = ("|cff606060R%d|r "):format(entry.round)
		end

		lines[#lines + 1] = ("|cff808080%s|r %s%s"):format(entry.time, prefix,
			watcher:FormatVerdict(preset, entry.name, entry.roll, entry.verdict, true))
	end

	lines[#lines + 1] = ""
	lines[#lines + 1] = "|cffffd100Totals|r"

	for _, name in ipairs(REH.SortedKeys(tallies)) do
		local tally = tallies[name]
		lines[#lines + 1] = ("%s: %d rolls, %d success, %d failure, %d critical"):format(
			watcher:DisplayName(name), tally.total, tally.successes,
			tally.failures, tally.criticals)
	end

	local ignored = watcher:GetIgnoredCount()
	if ignored > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = ("|cffffd100%d rolls were ignored by your filter.|r"):format(ignored)
	end

	return table.concat(lines, "\n")
end

local function Build()
	frame = CreateFrame("Frame", "RoleplayEventHelperLogFrame", UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()

	UI.AddBackground(frame, 0.03, 0.03, 0.05, 0.94)
	UI.AddBorder(frame, 0.3, 0.3, 0.35, 1)

	local title = UI.CreateLabel(frame, "Roll Log", "GameFontNormal")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)

	local close = UI.SafeCreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function()
		RollLog:Hide()
	end)

	----------------------------------------------------------------------------
	-- Round navigation
	----------------------------------------------------------------------------

	local previousButton = UI.CreateButton(frame, "<", 24, 20, function()
		RollLog:SetViewedRound(RollLog:GetViewedRound() - 1)
	end)
	previousButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -28)
	UI.SetTooltip(previousButton, "Earlier round",
		"Step back through the rounds. Before round one is every round together.")

	local roundLabel = UI.CreateLabel(frame, "", "GameFontNormalSmall")
	roundLabel:SetPoint("LEFT", previousButton, "RIGHT", 6, 0)
	roundLabel:SetWidth(150)
	frame.roundLabel = roundLabel

	local nextButton = UI.CreateButton(frame, ">", 24, 20, function()
		RollLog:SetViewedRound(RollLog:GetViewedRound() + 1)
	end)
	nextButton:SetPoint("LEFT", roundLabel, "RIGHT", 6, 0)
	UI.SetTooltip(nextButton, "Later round", "Step forward through the rounds.")

	frame.previousButton = previousButton
	frame.nextButton = nextButton

	local scroll, content = UI.CreateScrollArea(frame, WIDTH - 34, HEIGHT - 96)
	scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -54)
	frame.scrollFrame = scroll
	frame.content = content

	local body = UI.CreateLabel(content, "", "ChatFontNormal")
	body:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
	body:SetWidth(WIDTH - 40)
	body:SetJustifyH("LEFT")
	body:SetJustifyV("TOP")
	frame.bodyText = body

	local newRoundButton = UI.CreateButton(frame, "New round", 100, 22, function()
		REH.RollWatcher:BeginRound()
		RollLog:OnRoundChanged()
	end)
	newRoundButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
	frame.newRoundButton = newRoundButton
	UI.SetTooltip(newRoundButton, "New round", function()
		local preset = REH.Database:GetActivePreset()

		if not preset.rounds.announce then
			return "Starts a fresh round. Earlier rounds stay in the log and can be read back with the arrows.\n\nAnnouncing rounds is switched off on the Watcher tab."
		end

		return ("Starts a fresh round and announces it to %s. Earlier rounds stay in the log and can be read back with the arrows."):format(
			REH.Announcer:DescribeChannel(preset.channel))
	end)

	local clearButton = UI.CreateButton(frame, "Clear", 90, 22, function()
		REH.RollWatcher:ClearLog()
		RollLog:Refresh()
	end)
	clearButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
	frame.clearButton = clearButton

	-- Addons cannot write to the system clipboard, so "copy" means putting the
	-- text somewhere the host can select it themselves.
	local copyBox = UI.CreateMultiLineBox(frame, WIDTH - 20, 60)
	copyBox:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 38)
	copyBox:Hide()
	frame.copyBox = copyBox

	local copyButton = UI.CreateButton(frame, "Copy text", 110, 22, function()
		if copyBox:IsShown() then
			copyBox:Hide()
			return
		end

		local plain = RollLog:BuildText(RollLog:GetViewedRound())
			:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		copyBox.editBox:SetText(plain)
		copyBox:Show()
		copyBox.editBox:HighlightText()
		copyBox.editBox:SetFocus()
	end)
	copyButton:SetPoint("LEFT", clearButton, "RIGHT", 6, 0)
	frame.copyButton = copyButton

	if UISpecialFrames then
		table.insert(UISpecialFrames, "RoleplayEventHelperLogFrame")
	end

	RollLog.frame = frame
	return frame
end

function RollLog:GetFrame()
	if not frame then
		Build()
	end
	return frame
end

function RollLog:Refresh()
	if not frame then
		return
	end

	local viewed = self:GetViewedRound()

	frame.bodyText:SetText(self:BuildText(viewed))
	frame.roundLabel:SetText(self:DescribeRound(viewed))

	-- Nothing before "all rounds", nothing after the newest.
	if frame.previousButton.SetEnabled then
		frame.previousButton:SetEnabled(viewed > 0)
	end
	if frame.nextButton.SetEnabled then
		frame.nextButton:SetEnabled(viewed < REH.RollWatcher:GetRoundCount())
	end

	-- The scroll child has to grow with the text or the scrollbar never has
	-- anything to scroll, and the log looks like it stopped recording once the
	-- first screenful is full.
	if frame.content and frame.bodyText.GetStringHeight then
		frame.content:SetHeight(math.max(frame.bodyText:GetStringHeight() or 0, 1))
	end

	-- Newest rolls are at the bottom, which is where a host watching an event
	-- wants to be looking.
	local scroll = frame.scrollFrame
	if scroll then
		if scroll.UpdateScrollChildRect then
			scroll:UpdateScrollChildRect()
		end
		if scroll.GetVerticalScrollRange then
			scroll:SetVerticalScroll(math.max(scroll:GetVerticalScrollRange() or 0, 0))
		end
	end
end

function RollLog:Show()
	local window = self:GetFrame()
	self:Refresh()
	window:Show()
end

function RollLog:Hide()
	if frame then
		frame:Hide()
	end
end

function RollLog:Toggle()
	if frame and frame:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

function RollLog:IsShown()
	return frame ~= nil and frame:IsShown()
end
