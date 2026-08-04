local ADDON_NAME, REH = ...

local UI = REH.UI
local EffectsFrame = {}
UI.EffectsFrame = EffectsFrame

-- The roll-effects editor.
--
-- A window rather than another tab on the main frame: an effect is seven fields
-- wide and a host may want a dozen of them, which is a different shape of thing
-- from the one-value-per-row editors. It also means the loot table stays what it
-- is -- the two-minute version for a fishing night -- instead of growing until
-- the simple case needs the complicated UI.
--
-- Rows are pooled, never destroyed. Frames cannot be released in WoW, so
-- rebuilding the list on every edit would leak one row per keystroke; the pool
-- shows what it needs and hides the rest.

local WIDTH, HEIGHT = 640, 480
local MIN_WIDTH, MIN_HEIGHT = 600, 260
local MAX_WIDTH, MAX_HEIGHT = 1400, 1200
local ROW_HEIGHT = 56
local ROW_SPACING = 4

local frame
local rows = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Effects()
	return REH.Database:GetActivePreset().rollEffects
end

--- Write an edit and put the preset back through validation, so an effect can
--- never be left in a state the watcher has to defend against at roll time.
local function Commit()
	REH.Database:ValidatePreset(REH.Database:GetActivePreset())
	EffectsFrame:Refresh()
end

local function TriggerOptions()
	return REH.Fields.OptionsFrom(REH.EFFECT_TRIGGERS, REH.DISPLAY.effectTrigger)
end

local function VerdictOptions()
	return REH.Fields.OptionsFrom(REH.EFFECT_VERDICTS, REH.DISPLAY.effectVerdict)
end

local function TargetOptions()
	return REH.Fields.OptionsFrom(REH.EFFECT_TARGETS, REH.DISPLAY.effectTarget)
end

--- One line of plain English for an effect, used by the tooltip and by
--- /reh effects so the window and the chat command describe a rule the same way.
function EffectsFrame:Describe(effect)
	local when

	if effect.trigger == "any" then
		when = "On any roll"
	elseif effect.trigger == "verdict" then
		when = ("On a %s"):format(REH.DISPLAY.effectVerdict[effect.verdict] or effect.verdict)
	elseif effect.min == effect.max then
		when = ("On a roll of %d"):format(effect.min)
	else
		when = ("On a roll of %d-%d"):format(effect.min, effect.max)
	end

	local oneOf = ""
	if effect.random then
		oneOf = " (one of these)"
	end

	local chance = ""
	if (effect.chance or 100) < 100 then
		chance = (", %d%% of the time"):format(effect.chance)
	end

	local delay = ""
	if (effect.delaySeconds or 0) > 0 then
		delay = (" after %ss"):format(effect.delaySeconds)
	end

	return ("%s%s%s, %s: %s%s"):format(when, chance, delay,
		REH.DISPLAY.effectTarget[effect.target] or effect.target, effect.message, oneOf)
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

--- How wide a row is at the window's current size.
local function RowWidth()
	local width = (frame and frame:GetWidth()) or WIDTH
	return math.max(width - 60, MIN_WIDTH - 60)
end

local function BuildRow(parent, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(RowWidth(), ROW_HEIGHT)

	UI.AddBackground(row, 0.1, 0.1, 0.13, 0.5)

	-- Which effect a row is editing changes as rows are added and removed, so
	-- every control reads row.index at click time rather than closing over the
	-- index it was built with.
	row.index = index

	local function effect()
		return Effects()[row.index]
	end

	local enabled = UI.CreateCheckbox(row, "", function(checked)
		local target = effect()
		if target then
			target.enabled = checked
			Commit()
		end
	end)
	enabled:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
	UI.SetTooltip(enabled, "Enabled", "Off keeps the effect but stops it firing.")
	row.enabled = enabled

	local trigger = UI.CreateCycleButton(row, TriggerOptions(), 110, function(value)
		local target = effect()
		if target then
			target.trigger = value
			Commit()
		end
	end)
	trigger:SetPoint("LEFT", enabled, "RIGHT", 4, 0)
	UI.SetTooltip(trigger, "When it fires",
		"A roll of: a number or a range. A result of: success, failure or a critical. Any roll: every roll that is tracked.")
	row.trigger = trigger

	local minBox
	minBox = UI.CreateEditBox(row, 42, 7, function(text)
		local target = effect()
		if target then
			if not tonumber(text) then
				UI.FlashError(minBox, "A roll has to be a number.")
			end
			target.min = tonumber(text) or target.min
			Commit()
		end
	end)
	minBox:SetPoint("LEFT", trigger, "RIGHT", 6, 0)
	row.minBox = minBox

	local dash = UI.CreateLabel(row, "-")
	dash:SetPoint("LEFT", minBox, "RIGHT", 4, 0)
	row.dash = dash

	local maxBox
	maxBox = UI.CreateEditBox(row, 42, 7, function(text)
		local target = effect()
		if target then
			if not tonumber(text) then
				UI.FlashError(maxBox, "A roll has to be a number.")
			end
			target.max = tonumber(text) or target.max
			Commit()
		end
	end)
	maxBox:SetPoint("LEFT", dash, "RIGHT", 4, 0)
	row.maxBox = maxBox

	-- The verdict picker sits where the number boxes do: a given effect uses one
	-- or the other, never both, and showing both at once invites a host to fill
	-- in the pair that is being ignored.
	local verdict = UI.CreateCycleButton(row, VerdictOptions(), 130, function(value)
		local target = effect()
		if target then
			target.verdict = value
			Commit()
		end
	end)
	verdict:SetPoint("LEFT", trigger, "RIGHT", 6, 0)
	row.verdict = verdict

	local target = UI.CreateCycleButton(row, TargetOptions(), 100, function(value)
		local record = effect()
		if record then
			record.target = value
			Commit()
		end
	end)
	UI.SetTooltip(target, "Where it goes",
		"To my channel: sent to the room.\n\nTo me only: shown in your own chat frame, for something you want to read out yourself.\n\nTo the roller: whispered to whoever rolled, for something only they should know. Your client may refuse a whisper an addon sends after a roll, since there is no click behind it -- the line always reaches your own frame too, so you will see whether it went.")
	row.target = target

	local chance
	chance = UI.CreateEditBox(row, 38, 3, function(text)
		local record = effect()
		if record then
			if not tonumber(text) then
				UI.FlashError(chance, "A chance is a number from 0 to 100.")
			end
			record.chance = tonumber(text) or record.chance
			Commit()
		end
	end)
	UI.SetTooltip(chance, "Chance", "Percent chance the effect fires when it matches. 100 always fires.")
	row.chance = chance

	local chanceLabel = UI.CreateLabel(row, "%", "GameFontNormalSmall")

	local delay
	delay = UI.CreateEditBox(row, 38, 4, function(text)
		local record = effect()
		if record then
			if not tonumber(text) then
				UI.FlashError(delay, "A delay is a number of seconds.")
			end
			record.delaySeconds = tonumber(text) or record.delaySeconds
			Commit()
		end
	end)
	UI.SetTooltip(delay, "Delay", "Seconds to wait after the roll before saying it.")
	row.delay = delay

	local delayLabel = UI.CreateLabel(row, "s", "GameFontNormalSmall")

	local random = UI.CreateCheckbox(row, "", function(checked)
		local record = effect()
		if record then
			record.random = checked
			Commit()
		end
	end)
	random:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -28)
	UI.SetTooltip(random, "One of these at random",
		"Tick this on two or more effects with the same trigger and only one of them fires, chosen at random. Three fish written against 4-7 become one fish.")
	row.random = random

	local message = UI.CreateEditBox(row, RowWidth() - 130, REH.MAX_RULE_LINE_LENGTH, function(text)
		local record = effect()
		if record then
			record.message = text
			Commit()
		end
	end)
	message:SetPoint("LEFT", random, "RIGHT", 8, 0)
	UI.SetTooltip(message, "What it says",
		"{name} is the roller, {roll} the number, {result} the verdict, {item} whatever the loot table gives that roll.")
	row.message = message

	local remove = UI.CreateButton(row, "X", 24, 20, function()
		local list = Effects()
		if list[row.index] then
			table.remove(list, row.index)
			Commit()
		end
	end)
	remove:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
	UI.SetTooltip(remove, "Remove", "Deletes this effect.")
	row.remove = remove

	-- The right-hand controls are chained leftwards from the remove button
	-- rather than each placed at a measured offset. That way they stay together
	-- when the window is dragged wider, and none of them can end up underneath
	-- the button at the corner.
	delayLabel:SetPoint("RIGHT", remove, "LEFT", -6, 0)
	delay:SetPoint("RIGHT", delayLabel, "LEFT", -2, 0)
	chanceLabel:SetPoint("RIGHT", delay, "LEFT", -8, 0)
	chance:SetPoint("RIGHT", chanceLabel, "LEFT", -2, 0)
	target:SetPoint("RIGHT", chance, "LEFT", -10, 0)

	return row
end

--- Point a pooled row at one effect.
local function ApplyRow(row, index, effect)
	row.index = index

	row.enabled:SetChecked(effect.enabled and true or false)
	row.random:SetChecked(effect.random and true or false)
	row.trigger:SetValue(effect.trigger)
	row.target:SetValue(effect.target)
	row.verdict:SetValue(effect.verdict)

	row.minBox:SetText(tostring(effect.min))
	row.minBox:SetCursorPosition(0)
	row.maxBox:SetText(tostring(effect.max))
	row.maxBox:SetCursorPosition(0)
	row.chance:SetText(tostring(effect.chance))
	row.chance:SetCursorPosition(0)
	row.delay:SetText(tostring(effect.delaySeconds))
	row.delay:SetCursorPosition(0)
	row.message:SetText(effect.message or "")
	row.message:SetCursorPosition(0)

	-- Only the controls the trigger actually uses are on screen.
	if effect.trigger == "band" then
		row.minBox:Show()
		row.dash:Show()
		row.maxBox:Show()
		row.verdict:Hide()
	elseif effect.trigger == "verdict" then
		row.minBox:Hide()
		row.dash:Hide()
		row.maxBox:Hide()
		row.verdict:Show()
	else
		row.minBox:Hide()
		row.dash:Hide()
		row.maxBox:Hide()
		row.verdict:Hide()
	end

	row:Show()
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local function Build()
	frame = CreateFrame("Frame", "RoleplayEventHelperEffectsFrame", UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("HIGH")
	frame:Hide()

	UI.MakeFloating(frame, "effects")

	UI.AddBackground(frame, 0.03, 0.03, 0.05, 0.94)
	UI.AddBorder(frame, 0.3, 0.3, 0.35, 1)

	local title = UI.CreateLabel(frame, "Roll Effects", "GameFontNormal")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)

	local close = UI.SafeCreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function()
		EffectsFrame:Hide()
	end)

	local hint = UI.CreateLabel(frame,
		"Each effect answers a roll. Several can answer the same one.",
		"GameFontNormalSmall")
	hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -28)
	hint:SetWidth(WIDTH - 30)
	hint:SetJustifyH("LEFT")

	local scroll, content = UI.CreateScrollArea(frame, WIDTH - 34, HEIGHT - 130)
	scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -48)
	frame.scrollFrame = scroll
	frame.content = content

	local empty = UI.CreateLabel(content,
		"|cff808080No effects yet. Add one, or leave this empty and nothing changes.|r",
		"GameFontNormalSmall")
	empty:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -6)
	frame.emptyText = empty

	----------------------------------------------------------------------------
	-- Bottom bar
	----------------------------------------------------------------------------

	local addButton = UI.CreateButton(frame, "Add effect", 100, 22, function()
		local list = Effects()

		if #list >= REH.MAX_ROLL_EFFECTS then
			REH:PrintWarning(("An event can have at most %d effects."):format(REH.MAX_ROLL_EFFECTS))
			return
		end

		list[#list + 1] = REH.CreateRollEffect()
		Commit()
		REH.RollWatcher:WarnIfNotWatching()
	end)
	addButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
	frame.addButton = addButton

	-- Trying a number is how a host checks a table before the event rather than
	-- during it, so this sends nothing and ignores both chance and delay.
	local testLabel = UI.CreateLabel(frame, "Test a roll of", "GameFontNormalSmall")
	testLabel:SetPoint("LEFT", addButton, "RIGHT", 12, 0)

	local testBox = UI.CreateEditBox(frame, 50, 7)
	testBox:SetPoint("LEFT", testLabel, "RIGHT", 6, 0)
	frame.testBox = testBox

	local testButton = UI.CreateButton(frame, "Try it", 70, 22, function()
		EffectsFrame:Test(tonumber(frame.testBox:GetText()))
	end)
	testButton:SetPoint("LEFT", testBox, "RIGHT", 6, 0)
	frame.testButton = testButton

	UI.SetTooltip(testButton, "Try it",
		"Shows what this roll would set off, in your own chat frame. Nothing is sent, and chance and delay are ignored so you see every effect that matches.")

	UI.MakeResizable(frame, {
		minWidth = MIN_WIDTH, minHeight = MIN_HEIGHT,
		maxWidth = MAX_WIDTH, maxHeight = MAX_HEIGHT,
		defaultWidth = WIDTH, defaultHeight = HEIGHT,
		tooltip = "Drag to make the window bigger. The extra width goes to the message boxes, which is where a long line runs out of room.\n\nDouble-click to go back to the default size.",
		onResize = function() EffectsFrame:Layout() end,
		onSaved = function() EffectsFrame:SaveSize() end,
	})

	if UISpecialFrames then
		table.insert(UISpecialFrames, "RoleplayEventHelperEffectsFrame")
	end

	EffectsFrame.frame = frame
	EffectsFrame:RestoreSize()
	return frame
end

--------------------------------------------------------------------------------
-- Sizing
--------------------------------------------------------------------------------

--- Fit the rows to the window's current size. Extra width goes to the message
--- boxes: everything else on a row is a number or a choice with a natural size,
--- and the message is the one field a host can run out of room in.
function EffectsFrame:Layout()
	if not frame then
		return
	end

	UI.ResizeScrollArea(frame.scrollFrame, frame:GetWidth() - 34, frame:GetHeight() - 130)

	local rowWidth = RowWidth()

	for _, row in ipairs(rows) do
		row:SetWidth(rowWidth)
		row.message:SetWidth(math.max(rowWidth - 130, 100))
	end
end

function EffectsFrame:SaveSize()
	if not frame then
		return
	end

	REH.Database:GetSettings().effectsSize = {
		width = math.floor(frame:GetWidth() + 0.5),
		height = math.floor(frame:GetHeight() + 0.5),
	}
end

function EffectsFrame:RestoreSize()
	if not frame then
		return
	end

	local saved = REH.Database:GetSettings().effectsSize or {}
	frame:SetSize(
		REH.ClampNumber(saved.width, MIN_WIDTH, MAX_WIDTH, WIDTH),
		REH.ClampNumber(saved.height, MIN_HEIGHT, MAX_HEIGHT, HEIGHT))
end

--------------------------------------------------------------------------------
-- Testing a roll
--------------------------------------------------------------------------------

function EffectsFrame:Test(roll)
	local preset = REH.Database:GetActivePreset()

	if not roll then
		REH:PrintError("Type a number to try, e.g. 1.")
		return 0
	end

	roll = math.floor(roll)

	local lines = REH.RollWatcher:PreviewEffects(preset, roll)

	if #lines == 0 then
		REH:Print("A roll of %d sets off nothing.", roll)
		return 0
	end

	REH:Print("A roll of %d sets off %d effect(s), nothing sent:", roll, #lines)

	for _, line in ipairs(lines) do
		local note = ""
		if line.chance < 100 then
			note = (" |cff808080(%d%% chance)|r"):format(line.chance)
		end
		REH:Print("  %s%s", line.text, note)
	end

	return #lines
end

--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

function EffectsFrame:GetFrame()
	if not frame then
		Build()
	end
	return frame
end

function EffectsFrame:Refresh()
	if not frame then
		return
	end

	local list = Effects()
	local top = 0

	for index, effect in ipairs(list) do
		local row = rows[index]
		if not row then
			row = BuildRow(frame.content, index)
			rows[index] = row
		end

		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 4, -top)
		ApplyRow(row, index, effect)

		top = top + ROW_HEIGHT + ROW_SPACING
	end

	for index = #list + 1, #rows do
		rows[index]:Hide()
	end

	if #list == 0 then
		frame.emptyText:Show()
	else
		frame.emptyText:Hide()
	end

	-- Rows added since the last resize are built at whatever width the window
	-- was, so every refresh ends by fitting them all to what it is now.
	self:Layout()

	-- The scroll child has to grow with the rows or the ones past the first
	-- screenful can never be reached.
	frame.content:SetHeight(math.max(top, 1))

	if frame.scrollFrame.UpdateScrollChildRect then
		frame.scrollFrame:UpdateScrollChildRect()
	end

	if REH.UI.MainFrame then
		REH.UI.MainFrame:RefreshPreview()
	end
end

function EffectsFrame:Show()
	local window = self:GetFrame()
	self:Refresh()
	UI.ShowFloating(window, "effects")
end

function EffectsFrame:Hide()
	if frame then
		frame:Hide()
	end
end

function EffectsFrame:Toggle()
	if frame and frame:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

function EffectsFrame:IsShown()
	return frame ~= nil and frame:IsShown()
end
