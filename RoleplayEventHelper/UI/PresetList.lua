local ADDON_NAME, REH = ...

local UI = REH.UI
local PresetList = {}
UI.PresetList = PresetList

local ROW_HEIGHT = 20

--------------------------------------------------------------------------------
-- Name prompts
--------------------------------------------------------------------------------

-- StaticPopup is used for the name prompts because it is the client's own
-- modal, so it behaves the way players expect. It is registered lazily and
-- guarded: if the API is ever unavailable the buttons explain the slash command
-- instead of erroring.

local POPUP_KEY = "ROLEPLAYEVENTHELPER_NAME"
local popupRegistered = false

local function EnsurePopup()
	if popupRegistered or not StaticPopupDialogs then
		return popupRegistered
	end

	StaticPopupDialogs[POPUP_KEY] = {
		text = "%s",
		button1 = ACCEPT or "Accept",
		button2 = CANCEL or "Cancel",
		hasEditBox = true,
		maxLetters = REH.MAX_PRESET_NAME_LENGTH,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,

		OnShow = function(self)
			local box = self.editBox or (self.GetEditBox and self:GetEditBox())
			if box then
				box:SetText(self.data and self.data.initial or "")
				box:HighlightText()
				box:SetFocus()
			end
		end,

		OnAccept = function(self)
			local box = self.editBox or (self.GetEditBox and self:GetEditBox())
			local text = box and box:GetText() or ""
			if self.data and self.data.callback then
				self.data.callback(text)
			end
		end,

		EditBoxOnEnterPressed = function(self)
			local parent = self:GetParent()
			local text = self:GetText()
			local data = parent.data
			parent:Hide()
			if data and data.callback then
				data.callback(text)
			end
		end,

		EditBoxOnEscapePressed = function(self)
			self:GetParent():Hide()
		end,
	}

	popupRegistered = true
	return true
end

--- Ask for a name, then call `callback(name)`.
local function PromptForName(prompt, initial, fallbackCommand, callback)
	if EnsurePopup() and StaticPopup_Show then
		local dialog = StaticPopup_Show(POPUP_KEY, prompt)
		if dialog then
			dialog.data = { callback = callback, initial = initial }
			return true
		end
	end

	REH:PrintWarning(("Use %s instead."):format(fallbackCommand))
	return false
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

function PresetList:Create(parent, width, height, onChanged)
	local frame = UI.CreatePanel(parent)
	frame:SetSize(width, height)

	local heading = UI.CreateLabel(frame, "Presets", "GameFontNormalSmall")
	heading:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6)

	local buttonAreaHeight = 3 * (UI.ROW_HEIGHT + 4) + 6
	local scroll, content = UI.CreateScrollArea(frame,
		width - 30, height - 30 - buttonAreaHeight)
	scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -24)

	frame.rows = {}
	frame.content = content

	local function notify()
		if onChanged then
			onChanged()
		end
	end

	--- Rebuild the row buttons from the database.
	function frame:Refresh()
		local names = REH.Database:GetPresetNames()
		local _, activeName = REH.Database:GetActivePreset()

		for _, row in ipairs(self.rows) do
			row:Hide()
		end

		for index, name in ipairs(names) do
			local row = self.rows[index]
			if not row then
				row = CreateFrame("Button", nil, self.content)
				row:SetHeight(ROW_HEIGHT)
				row:SetWidth(width - 36)

				row.text = UI.CreateLabel(row, "")
				row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
				row.text:SetWidth(width - 44)

				row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
				row.highlight:SetAllPoints(row)
				row.highlight:SetColorTexture(1, 1, 1, 0.1)

				self.rows[index] = row
			end

			row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
			row.presetName = name

			if name == activeName then
				row.text:SetText("|cff40ff40" .. name .. "|r")
			else
				row.text:SetText(name)
			end

			row:SetScript("OnClick", function(self)
				REH.Database:SetActivePreset(self.presetName)
				notify()
			end)

			row:Show()
		end

		self.content:SetHeight(math.max(#names * ROW_HEIGHT, 1))
	end

	----------------------------------------------------------------------------
	-- Buttons
	----------------------------------------------------------------------------

	local buttonWidth = (width - 22) / 2

	local newButton = UI.CreateButton(frame, "New", buttonWidth, UI.ROW_HEIGHT, function()
		PromptForName("Name for the new preset:", "", "/reh new <name>", function(name)
			local preset, result = REH.Database:CreatePreset(name)
			if not preset then
				REH:PrintError(result)
				return
			end
			REH.Database:SetActivePreset(result)
			notify()
		end)
	end)
	newButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8 + 2 * (UI.ROW_HEIGHT + 4))

	local copyButton = UI.CreateButton(frame, "Copy", buttonWidth, UI.ROW_HEIGHT, function()
		local _, activeName = REH.Database:GetActivePreset()
		PromptForName("Name for the copy:", activeName .. " copy", "/reh copy <name>",
			function(name)
				local preset, result = REH.Database:CopyPreset(activeName, name)
				if not preset then
					REH:PrintError(result)
					return
				end
				REH.Database:SetActivePreset(result)
				notify()
			end)
	end)
	copyButton:SetPoint("LEFT", newButton, "RIGHT", 6, 0)

	local renameButton = UI.CreateButton(frame, "Rename", buttonWidth, UI.ROW_HEIGHT, function()
		local _, activeName = REH.Database:GetActivePreset()
		PromptForName("New name for '" .. activeName .. "':", activeName,
			"/reh rename <name>", function(name)
				local ok, result = REH.Database:RenamePreset(activeName, name)
				if not ok then
					REH:PrintError(result)
					return
				end
				notify()
			end)
	end)
	renameButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8 + (UI.ROW_HEIGHT + 4))

	-- Deleting is the one destructive action reachable by a single click, so it
	-- gets the client's own confirmation modal rather than doing it silently.
	local deleteButton = UI.CreateButton(frame, "Delete", buttonWidth, UI.ROW_HEIGHT, function()
		local _, activeName = REH.Database:GetActivePreset()

		if StaticPopupDialogs and StaticPopup_Show then
			StaticPopupDialogs["ROLEPLAYEVENTHELPER_DELETE"] = {
				text = "Delete the preset '%s'?",
				button1 = YES or "Yes",
				button2 = NO or "No",
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
				OnAccept = function()
					local ok, result = REH.Database:DeletePreset(activeName)
					if not ok then
						REH:PrintError(result)
						return
					end
					REH:Print(("Deleted preset '%s'."):format(result))
					notify()
				end,
			}
			StaticPopup_Show("ROLEPLAYEVENTHELPER_DELETE", activeName)
		else
			REH:PrintWarning("Use /reh delete <name> instead.")
		end
	end)
	deleteButton:SetPoint("LEFT", renameButton, "RIGHT", 6, 0)

	frame.newButton = newButton
	frame.copyButton = copyButton
	frame.renameButton = renameButton
	frame.deleteButton = deleteButton

	return frame
end
