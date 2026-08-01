local ADDON_NAME, REH = ...

local UI = {}
REH.UI = UI

-- Small widget helpers built on the plain frame API.
--
-- Two deliberate avoidances:
--
--   Backdrops. BackdropTemplate has moved around between expansions, so panels
--   are drawn with ordinary textures instead. A texture rectangle has worked
--   the same way for twenty years.
--
--   Dropdowns. Blizzard's menu API was replaced wholesale in recent patches.
--   Rather than bet on either the old or the new one, selection is done with a
--   cycling button for short lists and a self-built popup for long ones.
--
-- Templates that are used (InputBoxTemplate, UIPanelButtonTemplate,
-- UICheckButtonTemplate, UIPanelCloseButton, UIPanelScrollFrameTemplate) are
-- long-standing, but every one goes through SafeCreateFrame so a template that
-- disappears degrades the widget instead of breaking the addon at load.

UI.PADDING = 10
UI.ROW_HEIGHT = 22
UI.LABEL_WIDTH = 150

--------------------------------------------------------------------------------
-- Frame creation
--------------------------------------------------------------------------------

--- CreateFrame, but a missing template is survivable.
function UI.SafeCreateFrame(frameType, name, parent, template)
	if template then
		local ok, frame = pcall(CreateFrame, frameType, name, parent, template)
		if ok and frame then
			return frame, true
		end
	end

	return CreateFrame(frameType, name, parent), false
end

function UI.AddBackground(frame, r, g, b, a)
	local texture = frame:CreateTexture(nil, "BACKGROUND")
	texture:SetAllPoints(frame)
	texture:SetColorTexture(r, g, b, a)
	frame.background = texture
	return texture
end

--- A one-pixel border drawn from four textures.
function UI.AddBorder(frame, r, g, b, a)
	local edges = {}

	for index = 1, 4 do
		local texture = frame:CreateTexture(nil, "BORDER")
		texture:SetColorTexture(r, g, b, a)
		edges[index] = texture
	end

	edges[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	edges[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	edges[1]:SetHeight(1)

	edges[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	edges[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	edges[2]:SetHeight(1)

	edges[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	edges[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	edges[3]:SetWidth(1)

	edges[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	edges[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	edges[4]:SetWidth(1)

	frame.borderEdges = edges
	return edges
end

--- A bordered panel.
function UI.CreatePanel(parent, alpha)
	local panel = CreateFrame("Frame", nil, parent)
	UI.AddBackground(panel, 0.05, 0.05, 0.07, alpha or 0.85)
	UI.AddBorder(panel, 0.25, 0.25, 0.30, 0.9)
	return panel
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

function UI.CreateLabel(parent, text, fontObject)
	local label = parent:CreateFontString(nil, "ARTWORK", fontObject or "GameFontNormal")
	label:SetJustifyH("LEFT")
	label:SetText(text or "")
	return label
end

function UI.CreateHeading(parent, text)
	return UI.CreateLabel(parent, text, "GameFontNormalLarge")
end

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------

function UI.CreateButton(parent, text, width, height, onClick)
	local button = UI.SafeCreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width or 100, height or 22)

	if button.SetText then
		button:SetText(text or "")
	end

	if onClick then
		button:SetScript("OnClick", onClick)
	end

	return button
end

--- A button that shows the current value and advances to the next on click.
--- Used instead of a dropdown for short option lists.
function UI.CreateCycleButton(parent, options, width, onChange)
	local button = UI.CreateButton(parent, "", width or 160, UI.ROW_HEIGHT)
	button.options = options
	button.index = 1

	function button:GetValue()
		local option = self.options[self.index]
		return option and option.value
	end

	function button:SetValue(value)
		for index, option in ipairs(self.options) do
			if option.value == value then
				self.index = index
				break
			end
		end

		local option = self.options[self.index]
		if self.SetText then
			self:SetText(option and option.label or "")
		end
	end

	button:SetScript("OnClick", function(self)
		self.index = self.index + 1
		if self.index > #self.options then
			self.index = 1
		end

		local option = self.options[self.index]
		if self.SetText then
			self:SetText(option and option.label or "")
		end

		if onChange then
			onChange(option and option.value)
		end
	end)

	return button
end

function UI.CreateCheckbox(parent, label, onChange)
	local check = UI.SafeCreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(24, 24)

	local text = UI.CreateLabel(check, label)
	text:SetPoint("LEFT", check, "RIGHT", 4, 0)
	check.labelText = text

	check:SetScript("OnClick", function(self)
		if onChange then
			onChange(self:GetChecked() and true or false)
		end
	end)

	return check
end

--------------------------------------------------------------------------------
-- Edit boxes
--------------------------------------------------------------------------------

--- A single-line entry. `onCommit` fires on Enter and on focus loss, never on
--- every keystroke: revalidating a half-typed number would fight the typist.
function UI.CreateEditBox(parent, width, maxLetters, onCommit)
	local box = UI.SafeCreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width or 200, UI.ROW_HEIGHT)
	box:SetAutoFocus(false)

	if maxLetters then
		box:SetMaxLetters(maxLetters)
	end

	local function commit(self)
		if onCommit then
			onCommit(self:GetText())
		end
	end

	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		commit(self)
	end)

	box:SetScript("OnEditFocusLost", commit)

	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)

	return box
end

--- A multi-line entry inside its own scroll frame, for list-shaped fields.
function UI.CreateMultiLineBox(parent, width, height, onCommit)
	local container = UI.CreatePanel(parent, 0.6)
	container:SetSize(width, height)

	local scroll = UI.SafeCreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -26, 4)

	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject("ChatFontNormal")
	box:SetWidth(width - 34)
	box:SetScript("OnEscapePressed", box.ClearFocus)

	box:SetScript("OnEditFocusLost", function(self)
		if onCommit then
			onCommit(self:GetText())
		end
	end)

	scroll:SetScrollChild(box)

	container.editBox = box
	container.scrollFrame = scroll
	return container
end

--------------------------------------------------------------------------------
-- Scrolling
--------------------------------------------------------------------------------

--- A scroll frame with a content frame sized to its width.
function UI.CreateScrollArea(parent, width, height)
	local scroll = UI.SafeCreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	scroll:SetSize(width, height)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(width - 24, height)
	scroll:SetScrollChild(content)

	scroll.content = content
	return scroll, content
end

--------------------------------------------------------------------------------
-- Tooltips
--------------------------------------------------------------------------------

--- Attach a tooltip. `textProvider` may be a string or a function returning
--- one, so a disabled button can explain the current reason rather than a
--- reason baked in when it was created.
function UI.SetTooltip(widget, title, textProvider)
	widget:SetScript("OnEnter", function(self)
		if not GameTooltip then
			return
		end

		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(title, 1, 1, 1)

		local text = textProvider
		if type(text) == "function" then
			text = text()
		end

		if text and text ~= "" then
			GameTooltip:AddLine(text, 0.9, 0.9, 0.9, true)
		end

		GameTooltip:Show()
	end)

	widget:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
end

--------------------------------------------------------------------------------
-- Popup selector
--------------------------------------------------------------------------------

--- A self-built replacement for a dropdown: a panel of clickable rows.
function UI.CreatePopupSelector(parent, width)
	local popup = UI.CreatePanel(parent, 0.95)
	popup:SetWidth(width or 200)
	popup:SetFrameStrata("DIALOG")
	popup:Hide()
	popup.rows = {}

	function popup:Open(options, onSelect, anchorTo)
		for _, row in ipairs(self.rows) do
			row:Hide()
		end

		local top = 6
		for index, option in ipairs(options) do
			local row = self.rows[index]
			if not row then
				row = UI.CreateButton(self, "", (width or 200) - 12, 20)
				self.rows[index] = row
			end

			row:SetPoint("TOPLEFT", self, "TOPLEFT", 6, -top)
			if row.SetText then
				row:SetText(option.label)
			end
			row:SetScript("OnClick", function()
				self:Hide()
				onSelect(option.value)
			end)
			row:Show()

			top = top + 22
		end

		self:SetHeight(top + 6)
		self:ClearAllPoints()
		self:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", 0, 2)
		self:Show()
	end

	function popup:Toggle(options, onSelect, anchorTo)
		if self:IsShown() then
			self:Hide()
		else
			self:Open(options, onSelect, anchorTo)
		end
	end

	return popup
end
