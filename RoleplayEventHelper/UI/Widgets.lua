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

--- A multi-line entry for list-shaped fields.
---
--- Deliberately has no scroll frame of its own. The editor page it sits on is
--- already inside one, and nesting a scroll frame inside a scroll frame is
--- where mouse input goes to die: the inner frame competes for the click and
--- the edit box beneath it never receives focus, so the field looks present and
--- refuses to be typed in.
---
--- Instead the box grows with its text and `onResize` asks the page to lay
--- itself out again, letting the page's own scrolling reach the whole thing.
function UI.CreateMultiLineBox(parent, width, height, onCommit, onResize)
	local LINE_HEIGHT = 14
	local PADDING = 6

	local container = UI.CreatePanel(parent, 0.6)
	container:SetSize(width, height)
	container:EnableMouse(true)

	local box = CreateFrame("EditBox", nil, container)
	box:SetPoint("TOPLEFT", container, "TOPLEFT", PADDING, -PADDING)
	box:SetWidth(math.max(width - PADDING * 2, 1))
	box:SetHeight(math.max(height - PADDING * 2, 1))
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetJustifyH("LEFT")
	box:EnableMouse(true)
	box:SetTextInsets(2, 2, 2, 2)

	-- The font object itself rather than its name: an edit box with no font
	-- resolved does not render or accept input, and passing a string relies on
	-- the client looking it up.
	box:SetFontObject(_G.ChatFontNormal or "ChatFontNormal")

	box:SetScript("OnEscapePressed", box.ClearFocus)

	box:SetScript("OnEditFocusLost", function(self)
		if onCommit then
			onCommit(self:GetText())
		end
	end)

	local function fitToText(self)
		local lines = 1
		for _ in tostring(self:GetText() or ""):gmatch("\n") do
			lines = lines + 1
		end

		local wanted = math.max(height, lines * LINE_HEIGHT + PADDING * 2)

		if math.abs(wanted - container:GetHeight()) >= 1 then
			container:SetHeight(wanted)
			self:SetHeight(math.max(wanted - PADDING * 2, 1))

			if onResize then
				onResize(wanted)
			end
		end
	end

	box:SetScript("OnTextChanged", fitToText)

	-- Clicking the panel around the text puts the cursor in it, rather than
	-- requiring a hit on the text itself.
	container:SetScript("OnMouseDown", function()
		box:SetFocus()
	end)

	container.editBox = box
	container.minHeight = height

	--- Widen the box in place, for a window the host has dragged wider. The
	--- height is left to fitToText, which owns it.
	function container:SetBoxWidth(newWidth)
		newWidth = math.max(newWidth, 1)
		self:SetWidth(newWidth)
		self.editBox:SetWidth(math.max(newWidth - PADDING * 2, 1))
	end

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

--- Resize a scroll area in place. The content keeps whatever height it has
--- grown to; only the visible window onto it changes.
function UI.ResizeScrollArea(scroll, width, height)
	if not scroll then
		return
	end

	scroll:SetSize(math.max(width, 1), math.max(height, 1))

	if scroll.content then
		scroll.content:SetWidth(math.max(width - 24, 1))
	end

	if scroll.UpdateScrollChildRect then
		scroll:UpdateScrollChildRect()
	end
end

--------------------------------------------------------------------------------
-- Resizing
--------------------------------------------------------------------------------

--- Give a window a resize grip in its bottom-right corner.
---
--- `spec` carries the bounds, the default size to return to, and three
--- callbacks: `onResize` to lay the window out, `onSaved` to remember the new
--- size, and `onReset` for the double-click. Shared by every window that can be
--- dragged out, so they behave identically -- a host who learns the grip on one
--- has learnt it everywhere.
function UI.MakeResizable(frame, spec)
	frame:SetResizable(true)

	-- SetResizeBounds is the current call; the older pair is kept for clients
	-- that have not got it, since being unable to set bounds must not cost the
	-- window its resizing altogether.
	if frame.SetResizeBounds then
		frame:SetResizeBounds(spec.minWidth, spec.minHeight, spec.maxWidth, spec.maxHeight)
	else
		if frame.SetMinResize then
			frame:SetMinResize(spec.minWidth, spec.minHeight)
		end
		if frame.SetMaxResize then
			frame:SetMaxResize(spec.maxWidth, spec.maxHeight)
		end
	end

	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

	grip:SetScript("OnMouseDown", function()
		frame:StartSizing("BOTTOMRIGHT")
	end)

	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		if spec.onSaved then
			spec.onSaved()
		end
	end)

	-- A window dragged to an awkward size is a window the host would otherwise
	-- have to fix by hand, so there is always a way back.
	grip:RegisterForClicks("AnyUp")
	grip:SetScript("OnDoubleClick", function()
		frame:SetSize(spec.defaultWidth, spec.defaultHeight)
		if spec.onSaved then
			spec.onSaved()
		end
		if spec.onResize then
			spec.onResize()
		end
	end)

	UI.SetTooltip(grip, "Resize",
		spec.tooltip or "Drag to resize this window.\n\nDouble-click to go back to the default size.")

	-- One layout pass driven by the frame's actual size, so a drag and a
	-- restored size go through exactly the same code.
	if spec.onResize then
		frame:SetScript("OnSizeChanged", function()
			spec.onResize()
		end)
	end

	frame.resizeGrip = grip
	return grip
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
