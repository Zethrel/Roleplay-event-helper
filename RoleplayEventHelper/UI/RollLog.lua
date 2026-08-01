local ADDON_NAME, REH = ...

local UI = REH.UI
local RollLog = {}
UI.RollLog = RollLog

local WIDTH, HEIGHT = 420, 380

local frame

--- Build the log text. Pure, so it can be tested without a frame.
function RollLog:BuildText()
	local watcher = REH.RollWatcher
	local entries, tallies = watcher:GetLog()
	local preset = REH.Database:GetActivePreset()

	if #entries == 0 then
		return "|cff808080No rolls recorded yet.|r"
	end

	local lines = {}

	for _, entry in ipairs(entries) do
		lines[#lines + 1] = ("|cff808080%s|r %s"):format(entry.time,
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

	local scroll, content = UI.CreateScrollArea(frame, WIDTH - 34, HEIGHT - 72)
	scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30)

	local body = UI.CreateLabel(content, "", "ChatFontNormal")
	body:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
	body:SetWidth(WIDTH - 40)
	body:SetJustifyH("LEFT")
	body:SetJustifyV("TOP")
	frame.bodyText = body

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

		local plain = RollLog:BuildText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
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
	frame.bodyText:SetText(self:BuildText())
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
