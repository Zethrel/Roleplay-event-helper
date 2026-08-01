local ADDON_NAME, REH = ...

local L = REH.L
local Diagnostics = {}
REH.Diagnostics = Diagnostics

-- Reports when the client blocks something this addon tried to do.
--
-- "Interface action failed because of an AddOn" is not a Lua error. It is the
-- ADDON_ACTION_BLOCKED event, and /console scriptErrors never shows it, so
-- without a listener the host sees an alarming message with no way to find out
-- what caused it. This turns that into a named function and the exact point in
-- the announcement it happened at.

local MAX_ENTRIES = 20
local REPEAT_SILENCE = 5

local blocked = {}
local lastReport = { func = nil, at = 0 }
local eventFrame

--- Set by the announcer before each send, so a block can be attributed to a
--- specific message rather than just "something, at some point".
Diagnostics.context = nil

function Diagnostics:SetContext(description)
	self.context = description
end

function Diagnostics:ClearContext()
	self.context = nil
end

function Diagnostics:GetBlocked()
	return blocked
end

function Diagnostics:Clear()
	blocked = {}
	lastReport = { func = nil, at = 0 }
end

local function Record(event, addon, func)
	local entry = {
		event = event,
		addon = addon or "?",
		func = func or "?",
		context = Diagnostics.context,
		time = (date and date("%H:%M:%S")) or "",
	}

	table.insert(blocked, entry)
	if #blocked > MAX_ENTRIES then
		table.remove(blocked, 1)
	end

	return entry
end

function Diagnostics:Handle(event, addon, func)
	local entry = Record(event, addon, func)

	-- Only speak up for our own blocks. Another addon's taint arriving while
	-- this one happens to be running is not something to blame on the host.
	if entry.addon ~= ADDON_NAME then
		return entry
	end

	-- A block that lands mid-announcement is the announcer's to explain: it
	-- knows which message and which channel, and it can stop the queue rather
	-- than let every remaining message produce its own error line.
	if REH.Announcer:IsSending() and REH.Announcer:AbortBlocked(entry.func) then
		lastReport.func = entry.func
		lastReport.at = (GetTime and GetTime()) or 0
		return entry
	end

	-- A blocked action rarely arrives alone: one refusal usually brings several
	-- more for the same function within a moment. The host needs to be told
	-- once, not once per repetition, so the same function stays quiet for a few
	-- seconds after it has been reported. Every occurrence is still recorded
	-- and visible in /reh blocked.
	local now = (GetTime and GetTime()) or 0
	if lastReport.func == entry.func and (now - lastReport.at) < REPEAT_SILENCE then
		return entry
	end

	lastReport.func, lastReport.at = entry.func, now

	REH:PrintError(L["The client blocked '%s'.%s"]:format(
		entry.func,
		entry.context and (" " .. L["This happened while %s."]:format(entry.context)) or ""))
	REH:PrintWarning(L["That is the 'Interface action failed because of an AddOn' message. Run /reh blocked for the details."])

	return entry
end

function Diagnostics:Initialize()
	if eventFrame then
		return eventFrame
	end

	eventFrame = CreateFrame("Frame")
	eventFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
	eventFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")

	eventFrame:SetScript("OnEvent", function(_, event, addon, func)
		Diagnostics:Handle(event, addon, func)
	end)

	return eventFrame
end

--- Everything worth knowing when reporting a problem.
function Diagnostics:Report()
	local clientVersion, build, _, interfaceVersion = GetBuildInfo()

	REH:Print("%s v%s", L["Roleplay Event Helper"], REH.version)
	REH:Print("Client %s (build %s), interface %s.",
		tostring(clientVersion), tostring(build), tostring(interfaceVersion))
	REH:Print("Locale: %s. Roll format: %s",
		(GetLocale and GetLocale()) or "?", tostring(RANDOM_ROLL_RESULT))

	local preset, name = REH.Database:GetActivePreset()
	REH:Print("Preset '%s' announces to %s, %d messages, %.1fs apart, mode %s.",
		name, REH.Announcer:DescribeChannel(preset.channel),
		#REH.Formatter:BuildMessages(preset),
		REH.Database:GetSettings().sendDelay,
		REH.Database:GetSettings().sendMode)

	if #blocked == 0 then
		REH:Print(L["No blocked actions recorded this session."])
		return
	end

	REH:Print(L["Blocked actions (%d):"]:format(#blocked))
	for _, entry in ipairs(blocked) do
		REH:Print("  %s %s blocked '%s'%s", entry.time, entry.addon, entry.func,
			entry.context and (" while " .. entry.context) or "")
	end
end
