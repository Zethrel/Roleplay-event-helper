local ADDON_NAME, REH = ...

local L = REH.L

REH.name = ADDON_NAME

--------------------------------------------------------------------------------
-- Compatibility shims
--------------------------------------------------------------------------------

-- GetAddOnMetadata moved into the C_AddOns namespace; keep a fallback so the
-- addon still loads if it is ever run on a client that predates the move.
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata

REH.version = GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version") or "unknown"

--------------------------------------------------------------------------------
-- Client version check
--------------------------------------------------------------------------------

-- A TOC whose Interface value trails the live client makes the addon show as
-- "out of date" and silently disabled for anyone who has not ticked the "Load
-- out of date AddOns" box -- a support burden that looks like "your addon is
-- broken". Detect it ourselves and say the exact number to put in the TOC.
local function CheckInterfaceVersion()
	local _, _, _, clientInterface = GetBuildInfo()
	local declared = tonumber(GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Interface"))

	REH.clientInterface = clientInterface
	REH.declaredInterface = declared

	if declared and clientInterface and declared ~= clientInterface then
		REH:PrintWarning(
			"TOC interface is %d but this client reports %d. The addon still works; update '## Interface:' to %d to clear the out-of-date flag.",
			declared, clientInterface, clientInterface
		)
	end
end

--------------------------------------------------------------------------------
-- Bootstrap
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		local loadedAddon = ...
		if loadedAddon ~= ADDON_NAME then
			return
		end

		-- Saved variables are only guaranteed to exist once our own
		-- ADDON_LOADED has fired, so the database is built here rather than at
		-- file scope.
		REH.Database:Initialize()
		REH.Commands:Register()
		REH.RollWatcher:Initialize()

		self:UnregisterEvent("ADDON_LOADED")

	elseif event == "PLAYER_LOGIN" then
		CheckInterfaceVersion()

		-- Built at login rather than at ADDON_LOADED: the minimap exists by
		-- now, and a failure here must not take the rest of the addon with it.
		pcall(function()
			REH.UI.MinimapButton:Initialize()
		end)

		-- A downgrade leaves saved data this build does not understand. Say so
		-- once, because the alternative is the host quietly finding their
		-- presets behaving oddly mid-event.
		if REH.downgradedFrom then
			REH:PrintWarning(
				L["Your saved data is from a newer version (format %d, this build reads %d). It has been left untouched. Update the addon to use it."]
					:format(REH.downgradedFrom, REH.DB_VERSION))
		end

		self:UnregisterEvent("PLAYER_LOGIN")
	end
end)

REH.eventFrame = eventFrame

-- Expose the namespace for debugging and for the UI milestones.
_G.RoleplayEventHelper = REH

-- The TOC points the addon compartment at this global.
function _G.RoleplayEventHelper_OnCompartmentClick(_, mouseButton)
	if mouseButton == "RightButton" then
		REH.UI.RollLog:Toggle()
	else
		REH.UI.MainFrame:Toggle()
	end
end
