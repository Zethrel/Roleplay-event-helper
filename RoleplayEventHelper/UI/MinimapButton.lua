local ADDON_NAME, REH = ...

local UI = REH.UI
local MinimapButton = {}
UI.MinimapButton = MinimapButton

-- A hand-rolled minimap button rather than LibDBIcon.
--
-- LibDBIcon would bring LibDataBroker, which in turn hard-requires
-- CallbackHandler -- three dependencies to place one icon, against an addon
-- whose stated principle is that it needs none. The button is about seventy
-- lines, its position is already stored with the rest of the settings, and
-- nothing else about the addon needs a broker.
--
-- The trade-off is real and worth stating: without LibDataBroker, broker
-- displays (Titan Panel, ElvUI datatexts, Bazooka) get no plugin entry. If
-- anyone asks for that, adding it later is additive.

local BUTTON_SIZE = 31
local ICON_SIZE = 20
local ORBIT_RADIUS = 80

local ICON_TEXTURE = "Interface\\Icons\\INV_Misc_Dice_01"
local BORDER_TEXTURE = "Interface\\Minimap\\MiniMap-TrackingBorder"

local button

--------------------------------------------------------------------------------
-- Placement
--------------------------------------------------------------------------------

local function Settings()
	local settings = REH.Database:GetSettings()
	settings.minimapButton = settings.minimapButton or {}
	return settings.minimapButton
end

--- Place the button on its orbit around the minimap.
function MinimapButton:UpdatePosition()
	if not button or not Minimap then
		return
	end

	local angle = math.rad(Settings().minimapPos or 220)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER",
		math.cos(angle) * ORBIT_RADIUS, math.sin(angle) * ORBIT_RADIUS)
end

--- Follow the cursor around the minimap while dragging.
local function DragUpdate()
	local centerX, centerY = Minimap:GetCenter()
	if not centerX then
		return
	end

	local cursorX, cursorY = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	cursorX, cursorY = cursorX / scale, cursorY / scale

	Settings().minimapPos = math.deg(math.atan2(cursorY - centerY, cursorX - centerX))
	MinimapButton:UpdatePosition()
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function Build()
	if not Minimap then
		return nil
	end

	button = CreateFrame("Button", "RoleplayEventHelperMinimapButton", Minimap)
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetMovable(true)

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(ICON_SIZE, ICON_SIZE)
	icon:SetPoint("CENTER", button, "CENTER", 0, 1)
	icon:SetTexture(ICON_TEXTURE)
	button.icon = icon

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
	border:SetTexture(BORDER_TEXTURE)
	button.border = border

	button:SetScript("OnDragStart", function(self)
		self.dragging = true
		self:SetScript("OnUpdate", DragUpdate)
	end)

	button:SetScript("OnDragStop", function(self)
		self.dragging = false
		self:SetScript("OnUpdate", nil)
	end)

	button:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			UI.RollLog:Toggle()
		else
			UI.MainFrame:Toggle()
		end
	end)

	UI.SetTooltip(button, "Roleplay Event Helper", function()
		local _, name = REH.Database:GetActivePreset()
		local watching = REH.RollWatcher:IsWatching()

		return ("Active preset: %s\nRoll watcher: %s\n\nLeft-click: open the window\nRight-click: open the roll log\nDrag: move this button")
			:format(name, watching and "on" or "off")
	end)

	MinimapButton.button = button
	MinimapButton:UpdatePosition()

	return button
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

function MinimapButton:Initialize()
	if button then
		self:ApplySettings()
		return button
	end

	Build()
	self:ApplySettings()
	return button
end

function MinimapButton:ApplySettings()
	if not button then
		return
	end

	self:UpdatePosition()

	if Settings().hide then
		button:Hide()
	else
		button:Show()
	end
end

function MinimapButton:SetHidden(hidden)
	Settings().hide = hidden and true or false
	self:ApplySettings()
	return Settings().hide
end

function MinimapButton:IsHidden()
	return Settings().hide and true or false
end

function MinimapButton:IsShown()
	return button ~= nil and button:IsShown()
end
