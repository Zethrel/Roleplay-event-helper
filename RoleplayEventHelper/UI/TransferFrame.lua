local ADDON_NAME, REH = ...

local UI = REH.UI
local TransferFrame = {}
UI.TransferFrame = TransferFrame

local WIDTH, HEIGHT = 520, 300

local frame
local pending

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function Build()
	frame = CreateFrame("Frame", "RoleplayEventHelperTransferFrame", UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()

	UI.AddBackground(frame, 0.03, 0.03, 0.05, 0.96)
	UI.AddBorder(frame, 0.3, 0.3, 0.35, 1)

	local title = UI.CreateLabel(frame, "", "GameFontNormal")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
	frame.titleText = title

	local close = UI.SafeCreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function()
		TransferFrame:Hide()
	end)

	local instructions = UI.CreateLabel(frame, "", "GameFontDisableSmall")
	instructions:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -28)
	instructions:SetWidth(WIDTH - 24)
	instructions:SetJustifyH("LEFT")
	frame.instructionText = instructions

	local box = UI.CreateMultiLineBox(frame, WIDTH - 20, HEIGHT - 110)
	box:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -62)
	frame.box = box

	local status = UI.CreateLabel(frame, "", "GameFontNormalSmall")
	status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 36)
	status:SetWidth(WIDTH - 24)
	status:SetJustifyH("LEFT")
	frame.statusText = status

	----------------------------------------------------------------------------
	-- Buttons
	----------------------------------------------------------------------------

	local selectButton = UI.CreateButton(frame, "Select All", 100, 22, function()
		frame.box.editBox:HighlightText()
		frame.box.editBox:SetFocus()
	end)
	selectButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
	frame.selectButton = selectButton

	local importButton = UI.CreateButton(frame, "Import", 100, 22, function()
		TransferFrame:AttemptImport()
	end)
	importButton:SetPoint("LEFT", selectButton, "RIGHT", 6, 0)
	frame.importButton = importButton

	-- Shown only when the incoming name collides with one you already have.
	local overwriteButton = UI.CreateButton(frame, "Overwrite", 110, 22, function()
		TransferFrame:Finish("overwrite")
	end)
	overwriteButton:SetPoint("LEFT", importButton, "RIGHT", 6, 0)
	overwriteButton:Hide()
	frame.overwriteButton = overwriteButton

	local keepBothButton = UI.CreateButton(frame, "Keep both", 110, 22, function()
		TransferFrame:Finish("new")
	end)
	keepBothButton:SetPoint("LEFT", overwriteButton, "RIGHT", 6, 0)
	keepBothButton:Hide()
	frame.keepBothButton = keepBothButton

	if UISpecialFrames then
		table.insert(UISpecialFrames, "RoleplayEventHelperTransferFrame")
	end

	TransferFrame.frame = frame
	return frame
end

function TransferFrame:GetFrame()
	if not frame then
		Build()
	end
	return frame
end

--------------------------------------------------------------------------------
-- Modes
--------------------------------------------------------------------------------

local function ResetButtons()
	frame.overwriteButton:Hide()
	frame.keepBothButton:Hide()
	frame.statusText:SetText("")
	pending = nil
end

function TransferFrame:ShowExport(preset, presetName)
	local window = self:GetFrame()
	ResetButtons()

	local text, reason = REH.Transfer:Export(preset, presetName)
	if not text then
		REH:PrintError(reason)
		return
	end

	window.titleText:SetText("Export '" .. presetName .. "'")
	window.instructionText:SetText(
		"Copy this string and share it. Anyone with the addon can paste it into their own Import window.")
	window.importButton:Hide()

	window.box.editBox:SetText(text)
	window:Show()
	window.box.editBox:HighlightText()
	window.box.editBox:SetFocus()

	window.statusText:SetText(("|cff808080%d characters|r"):format(#text))
	return text
end

function TransferFrame:ShowImport()
	local window = self:GetFrame()
	ResetButtons()

	window.titleText:SetText("Import a preset")
	window.instructionText:SetText(
		"Paste a string starting with REH1: and press Import. Nothing is saved until you confirm.")
	window.importButton:Show()

	window.box.editBox:SetText("")
	window:Show()
	window.box.editBox:SetFocus()
end

--------------------------------------------------------------------------------
-- Importing
--------------------------------------------------------------------------------

function TransferFrame:AttemptImport()
	local window = self:GetFrame()

	local preset, name = REH.Transfer:Import(window.box.editBox:GetText())
	if not preset then
		-- `name` carries the reason when the parse failed.
		window.statusText:SetText("|cffff6060" .. tostring(name) .. "|r")
		window.overwriteButton:Hide()
		window.keepBothButton:Hide()
		pending = nil
		return false
	end

	pending = { preset = preset, name = name }

	-- Show what is about to be imported before anything is saved.
	window.statusText:SetText("|cff80ff80" .. REH.Transfer:Describe(preset, name) .. "|r")

	if REH.Database:FindName(name) then
		window.statusText:SetText(("|cffffd100You already have a preset called '%s'.|r %s")
			:format(name, REH.Transfer:Describe(preset, name)))
		window.overwriteButton:Show()
		window.keepBothButton:Show()
		return true
	end

	return self:Finish("new")
end

function TransferFrame:Finish(mode)
	if not pending then
		return false
	end

	local stored, reason = REH.Transfer:Commit(pending.preset, pending.name, mode)
	if not stored then
		self:GetFrame().statusText:SetText("|cffff6060" .. tostring(reason) .. "|r")
		return false
	end

	REH:Print(("Imported preset '%s'."):format(stored))
	pending = nil

	self:Hide()

	if UI.MainFrame:IsBuilt() then
		UI.MainFrame:RefreshAll()
	end

	return true, stored
end

function TransferFrame:GetPending()
	return pending
end

function TransferFrame:Hide()
	if frame then
		frame:Hide()
	end
end

function TransferFrame:IsShown()
	return frame ~= nil and frame:IsShown()
end
