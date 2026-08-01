local ADDON_NAME, REH = ...

local UI = REH.UI
local Editors = {}
UI.Editors = Editors

-- Builds the editor pages from REH.Fields.TABS. Nothing here knows what a
-- "success threshold" is: it knows how to render a number, a toggle, a choice
-- and a list, and the schema supplies the rest.

local ROW_SPACING = 6

--------------------------------------------------------------------------------
-- Row builders
--------------------------------------------------------------------------------

local function BuildTextRow(page, field, width, onEdited)
	local label = UI.CreateLabel(page, field.label)
	label:SetWidth(UI.LABEL_WIDTH)

	local box = UI.CreateEditBox(page, width - UI.LABEL_WIDTH - 24, field.maxLength,
		function(text)
			onEdited(field, text)
		end)

	if field.tooltip then
		UI.SetTooltip(box, field.label, field.tooltip)
	end

	return {
		field = field,
		label = label,
		control = box,
		height = UI.ROW_HEIGHT,
		apply = function(preset)
			box:SetText(tostring(field.get(preset) or ""))
			box:SetCursorPosition(0)
		end,
	}
end

local function BuildNumberRow(page, field, width, onEdited)
	local row = BuildTextRow(page, field, width, onEdited)
	row.control:SetWidth(90)
	row.control:SetNumeric(false) -- negative and signed values must be typeable
	return row
end

local function BuildToggleRow(page, field, width, onEdited)
	local check = UI.CreateCheckbox(page, field.label, function(checked)
		onEdited(field, checked)
	end)

	if field.tooltip then
		UI.SetTooltip(check, field.label, field.tooltip)
	end

	return {
		field = field,
		control = check,
		height = 24,
		apply = function(preset)
			check:SetChecked(field.get(preset) and true or false)
		end,
	}
end

local function BuildSelectRow(page, field, width, onEdited)
	local label = UI.CreateLabel(page, field.label)
	label:SetWidth(UI.LABEL_WIDTH)

	local options = field.options()
	local button = UI.CreateCycleButton(page, options, 200, function(value)
		onEdited(field, value)
	end)

	UI.SetTooltip(button, field.label, field.tooltip or "Click to change.")

	return {
		field = field,
		label = label,
		control = button,
		height = UI.ROW_HEIGHT,
		apply = function(preset)
			button:SetValue(field.get(preset))
		end,
	}
end

local function BuildLinesRow(page, field, width, onEdited)
	local label = UI.CreateLabel(page, field.label)

	local height = field.height or 120
	local box = UI.CreateMultiLineBox(page, width - 16, height, function(text)
		onEdited(field, text)
	end)

	if field.tooltip then
		UI.SetTooltip(box, field.label, field.tooltip)
	end

	return {
		field = field,
		label = label,
		control = box,
		height = height,
		labelAbove = true,
		apply = function(preset)
			box.editBox:SetText(tostring(field.get(preset) or ""))
			box.editBox:SetCursorPosition(0)
		end,
	}
end

local BUILDERS = {
	text = BuildTextRow,
	number = BuildNumberRow,
	decimal = BuildNumberRow,
	toggle = BuildToggleRow,
	select = BuildSelectRow,
	lines = BuildLinesRow,
}

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

--- Create one page per tab inside `parent`. Returns a controller.
function Editors:Create(parent, width, onChanged)
	local controller = { pages = {}, activeIndex = 1 }

	local function editorFor(tab)
		return function(field, rawValue)
			local target = REH.Fields:GetTarget(tab)
			local ok, reason = REH.Fields:Set(target, field, rawValue, tab.scope)

			if not ok then
				REH:PrintError(reason)
			end

			-- Refresh regardless: a rejected edit must put the old value back
			-- on screen, and an accepted one may have been adjusted by
			-- validation.
			controller:Refresh()

			if onChanged then
				onChanged()
			end
		end
	end

	for index, tab in ipairs(REH.Fields:GetTabs()) do
		local onEdited = editorFor(tab)
		local page = CreateFrame("Frame", nil, parent)
		page:SetSize(width, 400)
		page:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
		page:Hide()

		local rows = {}
		local top = 0

		for _, field in ipairs(tab.fields) do
			local builder = BUILDERS[field.type]
			if builder then
				local row = builder(page, field, width, onEdited)

				if row.labelAbove then
					row.label:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -top)
					row.control:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -(top + 18))
					top = top + row.height + 18 + ROW_SPACING
				else
					if row.label then
						row.label:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -(top + 4))
						row.control:SetPoint("TOPLEFT", page, "TOPLEFT", 4 + UI.LABEL_WIDTH, -top)
					else
						row.control:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -top)
					end
					top = top + row.height + ROW_SPACING
				end

				rows[#rows + 1] = row
			end
		end

		page.rows = rows
		page:SetHeight(math.max(top, 1))

		controller.pages[index] = { tab = tab, frame = page, rows = rows, height = top }
	end

	--- Push the active preset's values into every widget on the visible page.
	function controller:Refresh()
		local page = self.pages[self.activeIndex]
		if not page then
			return
		end

		local target = REH.Fields:GetTarget(page.tab)
		if not target then
			return
		end

		for _, row in ipairs(page.rows) do
			row.apply(target)
		end
	end

	function controller:ShowTab(index)
		for pageIndex, page in ipairs(self.pages) do
			if pageIndex == index then
				page.frame:Show()
			else
				page.frame:Hide()
			end
		end

		self.activeIndex = index
		self:Refresh()
	end

	function controller:GetActiveHeight()
		local page = self.pages[self.activeIndex]
		return page and page.height or 1
	end

	return controller
end
