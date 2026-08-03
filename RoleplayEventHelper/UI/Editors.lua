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
		resize = function(newWidth)
			box:SetWidth(math.max(newWidth - UI.LABEL_WIDTH - 24, 60))
		end,
		apply = function(preset)
			box:SetText(tostring(field.get(preset) or ""))
			box:SetCursorPosition(0)
		end,
	}
end

local function BuildNumberRow(page, field, width, onEdited)
	local row = BuildTextRow(page, field, width, onEdited)
	row.control:SetWidth(90)
	row.resize = nil -- a number field is 90 wide whatever the window is doing
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

local function BuildLinesRow(page, field, width, onEdited, onResize)
	local label = UI.CreateLabel(page, field.label)

	local height = field.height or 120
	local box = UI.CreateMultiLineBox(page, width - 16, height, function(text)
		onEdited(field, text)
	end, onResize)

	if field.tooltip then
		UI.SetTooltip(box, field.label, field.tooltip)
	end

	return {
		field = field,
		label = label,
		control = box,
		height = height,
		labelAbove = true,
		growable = true,
		resize = function(newWidth)
			box:SetBoxWidth(math.max(newWidth - 16, 60))
		end,
		apply = function(preset)
			box.editBox:SetText(tostring(field.get(preset) or ""))
			box.editBox:SetCursorPosition(0)
		end,
	}
end

--- A row that is a single button rather than a value: a way through to a
--- window that edits something too wide for a one-line row.
local function BuildActionRow(page, field, width, onEdited)
	local button = UI.CreateButton(page, field.label, field.width or 200, UI.ROW_HEIGHT,
		function()
			field.onClick()
		end)

	if field.tooltip then
		UI.SetTooltip(button, field.label, field.tooltip)
	end

	return {
		field = field,
		control = button,
		height = UI.ROW_HEIGHT,
		apply = function() end,
	}
end

local BUILDERS = {
	action = BuildActionRow,
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
		local pageInfo = { tab = tab, frame = page, rows = rows, height = 1 }

		-- Positioning is a separate pass from building, so a field that grows
		-- with its contents can push the rows below it down rather than
		-- overlapping them.
		local function layout()
			local top = 0

			for _, row in ipairs(rows) do
				if row.label then
					row.label:ClearAllPoints()
				end
				row.control:ClearAllPoints()

				if row.labelAbove then
					row.label:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -top)
					row.control:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -(top + 18))
					top = top + row.control:GetHeight() + 18 + ROW_SPACING
				else
					if row.label then
						row.label:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -(top + 4))
						row.control:SetPoint("TOPLEFT", page, "TOPLEFT", 4 + UI.LABEL_WIDTH, -top)
					else
						row.control:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -top)
					end
					top = top + row.height + ROW_SPACING
				end
			end

			page:SetHeight(math.max(top, 1))
			pageInfo.height = top

			if controller.onLayoutChanged then
				controller.onLayoutChanged()
			end
		end

		pageInfo.layout = layout

		for _, field in ipairs(tab.fields) do
			local builder = BUILDERS[field.type]
			if builder then
				rows[#rows + 1] = builder(page, field, width, onEdited, layout)
			end
		end

		layout()

		controller.pages[index] = pageInfo
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

		-- Filling a growable box changes its height, so the rows below it need
		-- placing again.
		if page.layout then
			page.layout()
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

	--- Re-width every page for a window the host has dragged wider or narrower.
	--- Only the fields that should follow the window do: a number box stays 90
	--- wide, because a five-digit field stretched across a wide window is not
	--- easier to read, it is just further from its label.
	function controller:SetWidth(newWidth)
		newWidth = math.max(newWidth, 200)

		for _, page in ipairs(self.pages) do
			page.frame:SetWidth(newWidth)

			for _, row in ipairs(page.rows) do
				if row.resize then
					row.resize(newWidth)
				end
			end

			if page.layout then
				page.layout()
			end
		end
	end

	function controller:GetActiveHeight()
		local page = self.pages[self.activeIndex]
		return page and page.height or 1
	end

	return controller
end
