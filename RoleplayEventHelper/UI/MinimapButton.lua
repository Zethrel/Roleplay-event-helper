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

-- How far outside the minimap's own edge the button rides. The orbit itself is
-- measured from the live minimap, never assumed: a fixed radius is only correct
-- for one minimap size, and lands the icon on top of the map the moment the
-- client, an interface option or another addon changes that size.
local EDGE_PADDING = 5

-- Used only if the minimap has not been given a size yet at the moment we first
-- place the button; the size hook below corrects it as soon as it has one.
local FALLBACK_MINIMAP_SIZE = 140

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

--- Half the minimap's width and height, plus the padding that puts the button
--- outside the border rather than on the map.
local function OrbitRadii()
	local width = Minimap.GetWidth and Minimap:GetWidth() or 0
	local height = Minimap.GetHeight and Minimap:GetHeight() or 0

	if not width or width <= 0 then
		width = FALLBACK_MINIMAP_SIZE
	end
	if not height or height <= 0 then
		height = FALLBACK_MINIMAP_SIZE
	end

	return width / 2 + EDGE_PADDING, height / 2 + EDGE_PADDING
end

--- Where the button sits for a given angle, in offsets from the minimap centre.
---
--- A round minimap is an ellipse, so the angle maps straight onto the radii. A
--- square one -- what SexyMap and several UI packs give you -- has corners, so
--- the point is pushed out along the diagonal and then clamped to the edges.
local function OrbitOffset(angle)
	local radiusX, radiusY = OrbitRadii()
	local x, y = math.cos(angle), math.sin(angle)

	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	if shape ~= "ROUND" then
		x = math.max(-radiusX, math.min(x * math.sqrt(2) * radiusX, radiusX))
		y = math.max(-radiusY, math.min(y * math.sqrt(2) * radiusY, radiusY))
		return x, y
	end

	return x * radiusX, y * radiusY
end

--- Place the button on its orbit around the minimap.
function MinimapButton:UpdatePosition()
	if not button or not Minimap then
		return
	end

	local x, y = OrbitOffset(math.rad(Settings().minimapPos or 220))
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
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

	-- The minimap is resized by the interface options, by patches, and by UI
	-- packs -- and it is often still unsized when we first place the button at
	-- login. Following its size keeps the icon on the edge instead of stranding
	-- it on the map at whatever size happened to be true at load.
	if Minimap.HookScript then
		Minimap:HookScript("OnSizeChanged", function()
			MinimapButton:UpdatePosition()
		end)
	end

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
