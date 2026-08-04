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
	if rolls.useVerdicts then
		REH:Print("  Rolls: /roll %d, %d+ is %s, below that is %s%s",
			rolls.dieMax, rolls.successThreshold, rolls.successText, rolls.failText, critText)
	else
		REH:Print("  Rolls: /roll %d. Rolls are not called a success or a failure.",
			rolls.dieMax)
	end
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

-- The list has grown past the point where an undifferentiated dump is useful,
-- so each command declares which group it belongs to and /reh help prints them
-- under headings.
local GROUP_ORDER = { "Window", "Presets", "Announcing", "Roll watcher", "Sharing", "Other" }
local currentGroup = "Other"

local function Group(name)
	currentGroup = name
end

local function Register(name, argHint, description, handler)
	handlers[name] = handler
	order[#order + 1] = {
		name = name, argHint = argHint, description = description, group = currentGroup,
	}
end

Group("Other")

Register("help", "[group]", "show this command list", function(argument)
	local wanted = argument ~= "" and argument:lower() or nil

	REH:Print("%s v%s", L["Roleplay Event Helper"], REH.version)

	for _, groupName in ipairs(GROUP_ORDER) do
		if not wanted or groupName:lower():find(wanted, 1, true) then
			local printedHeading = false

			for _, entry in ipairs(order) do
				if entry.group == groupName then
					if not printedHeading then
						REH:Print("|cffffd100%s|r", groupName)
						printedHeading = true
					end

					local usage = "/reh " .. entry.name
					if entry.argHint then
						usage = usage .. " " .. entry.argHint
					end
					REH:Print("  |cff8fd3ff%s|r - %s", usage, entry.description)
				end
			end
		end
	end
end)

Group("Window")

Register("window", nil, "open or close the main window", function()
	if REH.UI and REH.UI.MainFrame then
		REH.UI.MainFrame:Toggle()
	end
end)

Register("minimap", nil, "show or hide the minimap button", function()
	local hidden = REH.UI.MinimapButton:SetHidden(not REH.UI.MinimapButton:IsHidden())
	REH:Print(hidden and L["Minimap button hidden. Use /reh minimap to bring it back."]
		or L["Minimap button shown."])
end)

Register("blocked", nil, "show actions the client blocked, and why", function()
	REH.Diagnostics:Report()
end)

Register("sendmode", "[auto|paced|burst]", "how announcements are sent", function(argument)
	local settings = REH.Database:GetSettings()
	local word = argument:lower()

	if word == "" then
		local preset = REH.Database:GetActivePreset()
		REH:Print(L["Send mode is %s (%s for this preset's channel)."]:format(
			settings.sendMode,
			REH.Announcer:ResolveSendMode(preset.channel.type, settings.sendMode)))
		return
	end

	if word ~= "paced" and word ~= "burst" and word ~= "auto" then
		REH:PrintError(L["Send mode must be auto, paced or burst."])
		return
	end

	settings.sendMode = word
	REH:Print(L["Send mode is %s."]:format(settings.sendMode))

	if word == "burst" then
		REH:Print(L["Messages will go out together, in the call stack of the button you press. Slower on the client, but every send keeps the click behind it."])
	end
end)

Group("Presets")

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

Group("Announcing")

Register("include", "[section] [on|off]", "choose which sections are announced",
	function(argument)
		local preset, presetName = REH.Database:GetActivePreset()
		local word, state = argument:match("^(%S*)%s*(.-)$")
		word = word:lower()

		if word == "" then
			REH:Print(L["'%s' announces:"]:format(presetName))
			for _, key in ipairs(REH.MODULE_KEYS) do
				local tab = REH.Fields:FindTab(key)
				local label = tab and tab.title or key
				if preset.moduleEnabled[key] then
					REH:Print("  |cff40ff40on |r %s", label)
				else
					REH:Print("  |cff808080off|r %s", label)
				end
			end
			REH:Print(L["Change with /reh include <section> on|off."])
			return
		end

		-- Match on the tab title as shown in the window, since that is the name
		-- the host has actually seen.
		local matched
		for _, key in ipairs(REH.MODULE_KEYS) do
			local tab = REH.Fields:FindTab(key)
			if key == word or (tab and tab.title:lower() == word) then
				matched = key
			end
		end

		if not matched then
			REH:PrintError(L["No section called '%s'. Try /reh include with no arguments to see them."]
				:format(word))
			return
		end

		if state == "" then
			preset.moduleEnabled[matched] = not preset.moduleEnabled[matched]
		else
			preset.moduleEnabled[matched] = (state:lower() == "on")
		end

		local tab = REH.Fields:FindTab(matched)
		REH:Print(L["%s is now %s."]:format(tab and tab.title or matched,
			preset.moduleEnabled[matched] and "announced" or "left out"))

		if REH.UI.MainFrame:IsBuilt() then
			REH.UI.MainFrame:RefreshAll()
		end
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
	local ok, reason, warning, note = REH.Announcer:SetChannel(preset, word, target)

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

	if note then
		REH:Print(note)
	end
end)

--------------------------------------------------------------------------------
-- Roll watcher
--------------------------------------------------------------------------------

Group("Roll watcher")

local WATCH_MODE_TEXT = {
	off = "off",
	["local"] = "on, showing verdicts here only",
	announce = "on, announcing verdicts to your channel",
}

Register("watch", "[on|off|announce]", "arm or disarm the roll watcher", function(argument)
	local watcher = REH.RollWatcher
	local word = argument:lower()

	if word == "" or word == "status" then
		REH:Print(L["Roll watcher is %s."]:format(WATCH_MODE_TEXT[watcher:GetMode()]))
		if watcher:IsWatching() then
			local _, count = watcher:GetRoster()
			local preset = REH.Database:GetActivePreset()
			REH:Print(L["Tracking %s (%d in your group)."]:format(
				REH.DISPLAY.rollFilter[preset.rollFilter.mode] or preset.rollFilter.mode, count))
		end
		return
	end

	local mode
	if word == "on" or word == "local" then
		mode = "local"
	elseif word == "off" or word == "stop" then
		mode = "off"
	elseif word == "announce" then
		mode = "announce"
	end

	local ok, reason = watcher:SetMode(mode or word)
	if not ok then
		REH:PrintError(reason)
		return
	end

	REH:Print(L["Roll watcher is %s."]:format(WATCH_MODE_TEXT[watcher:GetMode()]))

	if mode == "announce" then
		local preset = REH.Database:GetActivePreset()
		if preset.channel.type == "PREVIEW" then
			REH:PrintWarning(L["This preset announces to preview only, so verdicts will show here rather than in chat."])
		end
	end
end)

Register("round", "[new]", "start a new round, or show the current one", function(argument)
	local watcher = REH.RollWatcher

	if argument:lower() == "new" then
		local number, created = watcher:BeginRound()
		if created then
			REH:Print(L["Round %d."]:format(number))
		else
			REH:Print(L["Still on round %d; nothing has been rolled in it yet."]:format(number))
		end
		return
	end

	REH:Print(L["Round %d of %d."]:format(watcher:GetCurrentRound(), watcher:GetRoundCount()))
end)

Register("log", "[clear]", "show the roll log for this session", function(argument)
	local watcher = REH.RollWatcher
	local entries, tallies = watcher:GetLog()

	if argument:lower() == "clear" then
		watcher:ClearLog()
		REH:Print(L["Roll log cleared."])
		return
	end

	if #entries == 0 then
		REH:Print(L["No rolls recorded yet."])
		return
	end

	REH:Print(L["Roll log (%d):"]:format(#entries))

	local first = math.max(1, #entries - 19)
	for index = first, #entries do
		local entry = entries[index]
		local preset = REH.Database:GetActivePreset()
		REH:Print("  %s %s", entry.time,
			watcher:FormatVerdict(preset, entry.name, entry.roll, entry.verdict, true,
				entry.maxRoll))
	end

	REH:Print(L["Totals:"])
	for _, name in ipairs(REH.SortedKeys(tallies)) do
		local tally = tallies[name]
		REH:Print("  %s: %d rolls, %d success, %d failure, %d critical",
			watcher:DisplayName(name), tally.total, tally.successes,
			tally.failures, tally.criticals)
	end
end)

Register("loot", "[on|off|test <roll>]", "the result table read off each roll",
	function(argument)
		local preset = REH.Database:GetActivePreset()
		local loot = preset.loot
		local word, rest = argument:match("^(%S*)%s*(.-)$")
		word = word:lower()

		if word == "on" or word == "off" then
			loot.enabled = (word == "on")
			REH:Print(loot.enabled and L["Loot results are on."] or L["Loot results are off."])

			if loot.enabled then
				REH.RollWatcher:WarnIfNotWatching()
			end
			return
		end

		-- Trying a number without waiting for someone to roll it is how a host
		-- checks the table before the event, so it sends nothing and skips the
		-- delay.
		if word == "test" then
			local roll = tonumber(rest)
			if not roll then
				REH:PrintError(L["Usage: %s"]:format("/reh loot test <roll>"))
				return
			end

			local pool = REH.RollWatcher:LootAlternatives(preset, roll)

			if #pool == 0 then
				REH:Print(L["A roll of %d gives nothing."]:format(roll))
				return
			end

			local line = REH.RollWatcher:FormatLoot(preset, UnitName("player") or "You", roll)
			REH:Print(L["A roll of %d: %s"]:format(roll, line))

			-- Several entries written against the same band are alternatives, so
			-- one number showing one fish would be a misleading answer to "what
			-- does a 5 give".
			if #pool > 1 then
				REH:Print(L["One of %d, chosen at random:"]:format(#pool))
				for _, entry in ipairs(pool) do
					REH:Print("  %s", entry.text)
				end
			end
			return
		end

		if word ~= "" then
			REH:PrintError(L["Usage: %s"]:format("/reh loot [on|off|test <roll>]"))
			return
		end

		REH:Print(loot.enabled and L["Loot results are on."] or L["Loot results are off."])

		if #loot.entries == 0 then
			REH:Print(L["No results set. Add them on the Loot tab, one per line: '1-3 an anchovy'."])
			return
		end

		for _, entry in ipairs(loot.entries) do
			if entry.min == entry.max then
				REH:Print("  %d: %s", entry.min, entry.text)
			else
				REH:Print("  %d-%d: %s", entry.min, entry.max, entry.text)
			end
		end
	end)

Register("effects", "[list|test <roll>|all <where>]", "open the roll effects window",
	function(argument)
	local word, rest = argument:match("^(%S*)%s*(.-)$")
	word = word:lower()

	if word == "test" then
		REH.UI.EffectsFrame:Test(tonumber(rest))
		return
	end

	-- Making a whole evening private is one decision; this is that decision
	-- from chat, the same as the window's "Set all to..." button.
	if word == "all" then
		local where = rest:lower():gsub("%s+", "")

		if where == "roller" or where == "whisper" then
			where = "whisper"
		elseif where == "me" or where == "self" then
			where = "self"
		elseif where == "channel" or where == "room" then
			where = "channel"
		else
			REH:PrintError(L["Send effects where? channel, me, or roller."])
			return
		end

		REH.UI.EffectsFrame:SetAllTargets(where)
		return
	end

	if word == "list" then
		local effects = REH.Database:GetActivePreset().rollEffects

		if #effects == 0 then
			REH:Print(L["No roll effects set. Open the window with /reh effects."])
			return
		end

		REH:Print(L["Roll effects (%d):"]:format(#effects))
		for index, effect in ipairs(effects) do
			REH:Print("  %d. %s%s", index, REH.UI.EffectsFrame:Describe(effect),
				effect.enabled and "" or " (off)")
		end
		return
	end

	REH.UI.EffectsFrame:Toggle()
end)

Register("mute", "<name>", "stop adjudicating one name this session", function(argument)
	if argument == "" then
		REH:PrintError(L["Usage: %s"]:format("/reh mute <name>"))
		return
	end

	local ok, full = REH.RollWatcher:Mute(argument)
	if ok then
		REH:Print(L["Muted %s for this session."]:format(REH.RollWatcher:DisplayName(full)))
	end
end)

Register("unmute", "<name>", "adjudicate a muted name again", function(argument)
	if argument == "" then
		REH:PrintError(L["Usage: %s"]:format("/reh unmute <name>"))
		return
	end

	local ok, full = REH.RollWatcher:Unmute(argument)
	if ok then
		REH:Print(L["Unmuted %s."]:format(REH.RollWatcher:DisplayName(full)))
	end
end)

Register("filter", "[group|subgroup|roster|everyone]", "choose whose rolls are tracked",
	function(argument)
		local preset = REH.Database:GetActivePreset()
		local word = argument:lower()

		if word == "" then
			REH:Print(L["Tracking %s."]:format(
				REH.DISPLAY.rollFilter[preset.rollFilter.mode] or preset.rollFilter.mode))
			return
		end

		if not REH.IsValidEnum(REH.ROLL_FILTER_MODES, word) then
			REH:PrintError(L["Filter must be group, subgroup, roster or everyone."])
			return
		end

		preset.rollFilter.mode = word
		REH:Print(L["Tracking %s."]:format(REH.DISPLAY.rollFilter[word] or word))

		if word == "subgroup" and #preset.rollFilter.subgroups == 0 then
			REH:PrintWarning(L["No subgroups chosen yet, so the whole raid counts. Set them with /reh subgroups 1 2."])
		end
	end)

Register("range", "[atmost|exact|any]", "which dice sizes count", function(argument)
	local preset = REH.Database:GetActivePreset()
	local word = argument:lower():gsub("%s", "")

	local aliases = {
		atmost = "atMost", ["or"] = "atMost", smaller = "atMost", lower = "atMost",
		exact = "exact", same = "exact",
		any = "any", all = "any",
	}

	if word == "" then
		REH:Print(L["Counting rolls on %s (these rules use /roll %d)."]:format(
			REH.DISPLAY.rangeMode[preset.rollFilter.rangeMode] or preset.rollFilter.rangeMode,
			preset.rolls.dieMax))
		return
	end

	local mode = aliases[word]
	if not mode then
		REH:PrintError(L["Range must be atmost, exact or any."])
		return
	end

	preset.rollFilter.rangeMode = mode
	REH:Print(L["Counting rolls on %s (these rules use /roll %d)."]:format(
		REH.DISPLAY.rangeMode[mode], preset.rolls.dieMax))

	if REH.UI.MainFrame:IsBuilt() then
		REH.UI.MainFrame:RefreshAll()
	end
end)

Register("subgroups", "<numbers>", "raid subgroups counted as combatants", function(argument)
	local preset = REH.Database:GetActivePreset()

	if argument == "" then
		if #preset.rollFilter.subgroups == 0 then
			REH:Print(L["No subgroups chosen; the whole raid counts."])
		else
			REH:Print(L["Combatant subgroups: %s"]:format(
				table.concat(preset.rollFilter.subgroups, ", ")))
		end
		return
	end

	local chosen = {}
	for number in argument:gmatch("%d+") do
		chosen[#chosen + 1] = tonumber(number)
	end

	preset.rollFilter.subgroups = chosen
	REH.Database:ValidatePreset(preset)

	if #preset.rollFilter.subgroups == 0 then
		REH:PrintWarning(L["No valid subgroups in that. Subgroups are 1 to 8."])
		return
	end

	preset.rollFilter.mode = "subgroup"
	REH:Print(L["Combatant subgroups: %s"]:format(
		table.concat(preset.rollFilter.subgroups, ", ")))
end)

Register("roster", "[import|add <name>|remove <name>|clear]", "edit the saved roster",
	function(argument)
		local preset = REH.Database:GetActivePreset()
		local word, rest = argument:match("^(%S*)%s*(.-)$")
		word = word:lower()

		if word == "" or word == "list" then
			if #preset.rollFilter.roster == 0 then
				REH:Print(L["The saved roster is empty."])
			else
				REH:Print(L["Saved roster (%d):"]:format(#preset.rollFilter.roster))
				for _, name in ipairs(preset.rollFilter.roster) do
					REH:Print("  %s", name)
				end
			end
			return

		elseif word == "import" then
			-- A raid caps at 40. An event that outgrows one needs a roster that
			-- survives group changes, and this is how it gets seeded.
			REH.RollWatcher:RebuildRoster()
			local group = REH.RollWatcher:GetRoster()

			local names = {}
			for full in pairs(group) do
				names[#names + 1] = full
			end
			table.sort(names)

			preset.rollFilter.roster = names
			preset.rollFilter.mode = "roster"
			REH.Database:ValidatePreset(preset)

			REH:Print(L["Imported %d names from your group into the roster."]:format(#names))
			return

		elseif word == "add" and rest ~= "" then
			table.insert(preset.rollFilter.roster, REH.RollWatcher:NormalizeName(rest))
			REH.Database:ValidatePreset(preset)
			REH:Print(L["Added %s to the roster."]:format(rest))
			return

		elseif word == "remove" and rest ~= "" then
			local target = REH.RollWatcher:NormalizeName(rest)
			for index, name in ipairs(preset.rollFilter.roster) do
				if REH.RollWatcher:NormalizeName(name) == target then
					table.remove(preset.rollFilter.roster, index)
					REH:Print(L["Removed %s from the roster."]:format(rest))
					return
				end
			end
			REH:PrintWarning(L["%s is not on the roster."]:format(rest))
			return

		elseif word == "clear" then
			preset.rollFilter.roster = {}
			REH:Print(L["Roster cleared."])
			return
		end

		REH:PrintError(L["Usage: %s"]:format("/reh roster [import|add <name>|remove <name>|clear]"))
	end)

Group("Sharing")

Register("export", "[name]", "get a shareable string for a preset", function(argument)
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

	-- The string is far longer than a chat line, so it goes to a window with a
	-- selectable box rather than being printed where it cannot be copied.
	REH.UI.TransferFrame:ShowExport(preset, name)
end)

Register("import", "[string]", "import a preset from a string", function(argument)
	if argument == "" then
		REH.UI.TransferFrame:ShowImport()
		return
	end

	-- The chat box caps what can be typed, so a pasted string usually has to go
	-- through the window. This path is here for short ones.
	local preset, name = REH.Transfer:Import(argument)
	if not preset then
		REH:PrintError(tostring(name))
		return
	end

	local stored, reason = REH.Transfer:Commit(preset, name, "new")
	if not stored then
		REH:PrintError(tostring(reason))
		return
	end

	REH:Print(L["Imported preset '%s'."]:format(stored))
end)

Group("Presets")

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

Register("templates", nil, "list the starter presets", function()
	REH:Print(L["Starter presets:"])

	for _, template in ipairs(REH.Templates.LIST) do
		REH:Print("  |cff8fd3ff%s|r - %s", template.key, template.name)
		REH:Print("      %s", template.summary)
	end

	REH:Print(L["Create one with /reh template <name>, or with the New button."])
end)

Register("template", "<template> [name]", "create a preset from a starter",
	function(argument)
		local key, name = argument:match("^(%S*)%s*(.-)$")

		if key == "" then
			REH.Commands:Handle("templates")
			return
		end

		local preset, result, template = REH.Database:CreateFromTemplate(key, name)
		if not preset then
			REH:PrintError(result)
			return
		end

		REH.Database:SetActivePreset(result)
		REH:Print(L["Created '%s' from the %s starter."]:format(result, template.name))
		REH:Print("  %s", template.summary)
		REH:Print(L["It announces to preview only. Pick a channel with /reh channel."])

		if REH.UI and REH.UI.MainFrame then
			REH.UI.MainFrame:RefreshAll()
		end
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

Group("Other")

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
