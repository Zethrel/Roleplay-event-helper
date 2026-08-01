local ADDON_NAME, REH = ...

local L = REH.L

-- Bump whenever the saved-variable layout changes in a way that needs a
-- migration step. Stored in the DB so future versions can upgrade a player's
-- saved presets instead of discarding them.
local DB_VERSION = 1

local CHAT_PREFIX = "|cff8fd3ff[REH]|r "

REH.name = ADDON_NAME

--------------------------------------------------------------------------------
-- Compatibility shims
--------------------------------------------------------------------------------

-- GetAddOnMetadata moved into the C_AddOns namespace; keep a fallback so the
-- addon still loads if it is ever run on a client that predates the move.
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata

REH.version = GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version") or "unknown"

--------------------------------------------------------------------------------
-- Output helpers
--------------------------------------------------------------------------------

--- Print a prefixed line to the default chat frame.
-- Local output only. Nothing here ever reaches other players; sending to a
-- channel is the Announcer's job and always requires an explicit host action.
function REH:Print(message, ...)
	if select("#", ...) > 0 then
		message = message:format(...)
	end
	DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. tostring(message))
end

function REH:PrintWarning(message, ...)
	if select("#", ...) > 0 then
		message = message:format(...)
	end
	DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "|cffffd100" .. tostring(message) .. "|r")
end

--------------------------------------------------------------------------------
-- Database
--------------------------------------------------------------------------------

-- M0 keeps this deliberately thin. The full default preset, preset CRUD and the
-- migration chain arrive in M1 (Core\Defaults.lua and Core\Database.lua); this
-- exists so saved-variable persistence is proven before anything depends on it.
local function InitializeDatabase()
	RoleplayEventHelperDB = RoleplayEventHelperDB or {}
	local db = RoleplayEventHelperDB

	if db.dbVersion == nil then
		db.dbVersion = DB_VERSION
		db.firstInstalledVersion = REH.version
	end

	db.settings = db.settings or {}
	db.presets = db.presets or {}

	-- Proof of persistence for M0: survives /reload and full logout alike.
	db.loadCount = (db.loadCount or 0) + 1
	db.lastVersion = REH.version

	REH.db = db
end

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
-- Slash commands
--------------------------------------------------------------------------------

local function PrintVersionInfo()
	local clientVersion, build = GetBuildInfo()
	REH:Print("%s v%s", L["Roleplay Event Helper"], REH.version)
	REH:Print("Client %s (build %s), interface %s. TOC declares %s.",
		tostring(clientVersion), tostring(build),
		tostring(REH.clientInterface), tostring(REH.declaredInterface))
	REH:Print("Saved data loaded %d time(s).", REH.db and REH.db.loadCount or 0)
end

local function PrintHelp()
	REH:Print(L["Commands:"])
	REH:Print("  |cffffd100/reh|r - %s", L["show this command list"])
	REH:Print("  |cffffd100/reh version|r - %s", L["show addon and client version details"])
end

local function HandleSlashCommand(input)
	local command = (input or ""):match("^%s*(%S*)"):lower()

	if command == "" or command == "help" then
		REH:Print("%s v%s loaded. %s", L["Roleplay Event Helper"], REH.version,
			L["Type /reh help for commands."])
		PrintHelp()
	elseif command == "version" then
		PrintVersionInfo()
	else
		REH:PrintWarning(L["Unknown command '%s'. Type /reh help for the command list."], command)
	end
end

local function RegisterSlashCommands()
	SLASH_ROLEPLAYEVENTHELPER1 = "/reh"
	SLASH_ROLEPLAYEVENTHELPER2 = "/rpevent"
	SlashCmdList["ROLEPLAYEVENTHELPER"] = HandleSlashCommand
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
		-- ADDON_LOADED has fired, so the DB is built here rather than at
		-- file scope.
		InitializeDatabase()
		RegisterSlashCommands()

		self:UnregisterEvent("ADDON_LOADED")

	elseif event == "PLAYER_LOGIN" then
		CheckInterfaceVersion()
		self:UnregisterEvent("PLAYER_LOGIN")
	end
end)

REH.eventFrame = eventFrame

-- Expose the namespace for debugging and for /reh work in later milestones.
_G.RoleplayEventHelper = REH
