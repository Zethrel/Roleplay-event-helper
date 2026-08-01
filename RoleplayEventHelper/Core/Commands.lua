local ADDON_NAME, REH = ...

local L = REH.L
local Commands = {}
REH.Commands = Commands

-- Destructive commands are confirmed rather than executed immediately. Preset
-- names are typed by hand and often similar ("Duel Ring" / "Duel Ring 2"), so a
-- mistyped delete is an easy way to lose an evening's setup.
local CONFIRM_TIMEOUT = 30
local pendingAction = nil

local function Now()
	return (GetTime and GetTime()) or 0
end

local function SetPending(description, action)
	pendingAction = { description = description, action = action, expires = Now() + CONFIRM_TIMEOUT }
	REH:PrintWarning(L["%s Type /reh confirm within %d seconds to proceed."]
		:format(description, CONFIRM_TIMEOUT))
end

local function ClearPending()
	pendingAction = nil
end

--- Exposed for tests and for the UI to cancel a pending prompt.
function Commands:ClearPending()
	ClearPending()
end

--------------------------------------------------------------------------------
-- Display helpers
--------------------------------------------------------------------------------

local function DescribePreset(preset, name)
	local rolls = preset.rolls

	REH:Print("|cffffd100%s|r", name)
	REH:Print("  Event: %s%s", preset.header.eventName,
		preset.header.hostName ~= "" and (" (host: " .. preset.header.hostName .. ")") or "")

	local critText = ""
	if rolls.useCritical then
		critText = (", crit success at %d+, crit fail at %d-"):format(rolls.critSuccessAt, rolls.critFailAt)
	end
	REH:Print("  Rolls: /roll %d, %d+ is %s, below that is %s%s",
		rolls.dieMax, rolls.successThreshold, rolls.successText, rolls.failText, critText)
	REH:Print("  Ties: %s. Rolls per turn: %d.",
		REH.DISPLAY.tieBreakShort[rolls.tieBreak] or rolls.tieBreak, rolls.rollsPerTurn)

	local parts = {}
	for _, row in ipairs(preset.health.rows) do
		parts[#parts + 1] = ("%s %d"):format(row.label, row.hp)
	end
	for _, modifier in ipairs(preset.health.modifiers) do
		parts[#parts + 1] = ("%s %+d"):format(modifier.label, modifier.bonus)
	end
	REH:Print("  Health: %s", #parts > 0 and table.concat(parts, ", ") or "none set")

	REH:Print("  Damage: %d per hit, %d on a crit.", preset.damage.perHit, preset.damage.onCrit)
	REH:Print("  Turns: %s%s.",
		REH.DISPLAY.initiativeShort[preset.turns.mode] or preset.turns.mode,
		preset.turns.turnTimeSeconds > 0 and (", " .. preset.turns.turnTimeSeconds .. "s per turn") or "")
	REH:Print("  Custom rules: %d. Etiquette lines: %d.", #preset.custom, #preset.etiquette)
	REH:Print("  Roll watcher tracks: %s.",
		REH.DISPLAY.rollFilter[preset.rollFilter.mode] or preset.rollFilter.mode)
	REH:Print("  Announce target: %s%s", preset.channel.type,
		preset.channel.target ~= "" and (" -> " .. preset.channel.target) or "")
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

-- Each handler receives the remainder of the command line as a single string,
-- because preset names may contain spaces.

local handlers = {}
local order = {}

local function Register(name, argHint, description, handler)
	handlers[name] = handler
	order[#order + 1] = { name = name, argHint = argHint, description = description }
end

Register("help", nil, "show this command list", function()
	REH:Print("%s v%s", L["Roleplay Event Helper"], REH.version)
	REH:Print(L["Commands:"])
	for _, entry in ipairs(order) do
		local usage = "/reh " .. entry.name
		if entry.argHint then
			usage = usage .. " " .. entry.argHint
		end
		REH:Print("  |cffffd100%s|r - %s", usage, entry.description)
	end
end)

Register("window", nil, "open or close the main window", function()
	if REH.UI and REH.UI.MainFrame then
		REH.UI.MainFrame:Toggle()
	end
end)

Register("list", nil, "list your presets", function()
	local names = REH.Database:GetPresetNames()
	local _, activeName = REH.Database:GetActivePreset()

	REH:Print(L["Presets (%d):"]:format(#names))
	for _, name in ipairs(names) do
		if name == activeName then
			REH:Print("  |cff40ff40> %s|r (active)", name)
		else
			REH:Print("    %s", name)
		end
	end
end)

Register("show", "[name]", "show a preset's rules in detail", function(argument)
	local preset, name
	if argument ~= "" then
		preset, name = REH.Database:GetPreset(argument)
		if not preset then
			REH:PrintError(L["No preset named '%s'."]:format(argument))
			return
		end
	else
		preset, name = REH.Database:GetActivePreset()
	end

	DescribePreset(preset, name)
end)

Register("preview", "[name]", "show exactly what would be sent to chat", function(argument)
	local preset, name
	if argument ~= "" then
		preset, name = REH.Database:GetPreset(argument)
		if not preset then
			REH:PrintError(L["No preset named '%s'."]:format(argument))
			return
		end
	else
		preset, name = REH.Database:GetActivePreset()
	end

	REH.Formatter:Preview(preset, name)
end)

Register("announce", "[name]", "send a preset's rules to the chosen channel", function(argument)
	local preset, name
	if argument ~= "" then
		preset, name = REH.Database:GetPreset(argument)
		if not preset then
			REH:PrintError(L["No preset named '%s'."]:format(argument))
			return
		end
	else
		preset, name = REH.Database:GetActivePreset()
	end

	REH.Announcer:Announce(preset, name)
end)

Register("cancel", nil, "stop an announcement in progress", function()
	if not REH.Announcer:Cancel() then
		REH:Print(L["Nothing is being announced."])
	end
end)

Register("channel", "[type] [name]", "choose where announcements are sent", function(argument)
	local preset, presetName = REH.Database:GetActivePreset()

	if argument == "" then
		REH:Print(L["'%s' announces to: %s"]:format(presetName,
			REH.Announcer:DescribeChannel(preset.channel)))

		local available, reason = REH.Announcer:CheckAvailability(preset.channel)
		if not available then
			REH:PrintWarning(L["Not available right now: %s"]:format(reason))
		end

		REH:Print(L["Set with: /reh channel <preview|say|yell|emote|party|raid|warning|instance|guild|officer|channel <name>|whisper <name>>"])
		return
	end

	local word, target = argument:match("^(%S+)%s*(.-)$")
	local ok, reason, warning = REH.Announcer:SetChannel(preset, word, target)

	if not ok then
		REH:PrintError(reason)
		return
	end

	REH:Print(L["'%s' will announce to: %s"]:format(presetName,
		REH.Announcer:DescribeChannel(preset.channel)))

	-- Setting a target you cannot use yet is allowed on purpose: hosts set up
	-- "raid warning" before the raid exists. The warning is so it is not a
	-- surprise at the moment they press announce.
	if warning then
		REH:PrintWarning(L["Not available right now: %s"]:format(warning))
	end
end)

Register("use", "<name>", "switch the active preset", function(argument)
	if argument == "" then
		REH:PrintError(L["Usage: %s"]:format("/reh use <name>"))
		return
	end

	local ok, result = REH.Database:SetActivePreset(argument)
	if ok then
		REH:Print(L["Active preset is now '%s'."]:format(result))
	else
		REH:PrintError(result)
	end
end)

Register("new", "<name>", "create a preset from the defaults", function(argument)
	if argument == "" then
		REH:PrintError(L["Usage: %s"]:format("/reh new <name>"))
		return
	end

	local preset, result = REH.Database:CreatePreset(argument)
	if not preset then
		REH:PrintError(result)
		return
	end

	REH.Database:SetActivePreset(result)
	REH:Print(L["Created preset '%s' and made it active."]:format(result))
end)

Register("copy", "<new name>", "copy the active preset", function(argument)
	if argument == "" then
		REH:PrintError(L["Usage: %s"]:format("/reh copy <new name>"))
		return
	end

	local _, activeName = REH.Database:GetActivePreset()
	local preset, result = REH.Database:CopyPreset(activeName, argument)
	if not preset then
		REH:PrintError(result)
		return
	end

	REH.Database:SetActivePreset(result)
	REH:Print(L["Copied '%s' to '%s' and made it active."]:format(activeName, result))
end)

Register("rename", "<new name>", "rename the active preset", function(argument)
	if argument == "" then
		REH:PrintError(L["Usage: %s"]:format("/reh rename <new name>"))
		return
	end

	local _, activeName = REH.Database:GetActivePreset()
	local ok, result = REH.Database:RenamePreset(activeName, argument)
	if ok then
		REH:Print(L["Renamed '%s' to '%s'."]:format(activeName, result))
	else
		REH:PrintError(result)
	end
end)

Register("delete", "<name>", "delete a preset (asks to confirm)", function(argument)
	if argument == "" then
		REH:PrintError(L["Usage: %s"]:format("/reh delete <name>"))
		return
	end

	local preset, resolved = REH.Database:GetPreset(argument)
	if not preset then
		REH:PrintError(L["No preset named '%s'."]:format(argument))
		return
	end

	SetPending(L["This will delete the preset '%s'."]:format(resolved), function()
		local ok, result = REH.Database:DeletePreset(resolved)
		if ok then
			REH:Print(L["Deleted preset '%s'."]:format(result))
		else
			REH:PrintError(result)
		end
	end)
end)

Register("reset", nil, "reset the active preset to defaults (asks to confirm)", function()
	local _, activeName = REH.Database:GetActivePreset()

	SetPending(L["This will reset '%s' to the default rules."]:format(activeName), function()
		local ok, result = REH.Database:ResetPreset(activeName)
		if ok then
			REH:Print(L["Reset preset '%s' to defaults."]:format(result))
		else
			REH:PrintError(result)
		end
	end)
end)

Register("confirm", nil, "confirm the pending action", function()
	if not pendingAction then
		REH:Print(L["Nothing is waiting for confirmation."])
		return
	end

	if Now() > pendingAction.expires then
		ClearPending()
		REH:PrintWarning(L["That confirmation expired. Run the command again."])
		return
	end

	local action = pendingAction.action
	ClearPending()
	action()
end)

Register("version", nil, "show addon and client version details", function()
	local clientVersion, build = GetBuildInfo()
	REH:Print("%s v%s", L["Roleplay Event Helper"], REH.version)
	REH:Print("Client %s (build %s), interface %s. TOC declares %s.",
		tostring(clientVersion), tostring(build),
		tostring(REH.clientInterface), tostring(REH.declaredInterface))
	REH:Print("Presets: %d. Saved data loaded %d time(s).",
		REH.Database:CountPresets(), REH.db and REH.db.loadCount or 0)
end)

--------------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------------

function Commands:Handle(input)
	local text = REH.Trim(input or "")
	local command, argument = text:match("^(%S+)%s*(.-)$")

	-- A bare /reh opens the window; the command list moved to /reh help.
	if not command then
		if REH.UI and REH.UI.MainFrame then
			REH.UI.MainFrame:Toggle()
		else
			handlers.help("")
		end
		return
	end

	command = command:lower()
	argument = REH.Trim(argument or "")

	local handler = handlers[command]
	if handler then
		-- Any command other than an explicit confirm cancels a pending one, so
		-- a stale prompt can never be answered by a later, unrelated confirm.
		if command ~= "confirm" then
			ClearPending()
		end
		handler(argument)
	else
		REH:PrintError(L["Unknown command '%s'. Type /reh help for the command list."]:format(command))
	end
end

function Commands:Register()
	SLASH_ROLEPLAYEVENTHELPER1 = "/reh"
	SLASH_ROLEPLAYEVENTHELPER2 = "/rpevent"
	SlashCmdList["ROLEPLAYEVENTHELPER"] = function(input)
		Commands:Handle(input)
	end
end
