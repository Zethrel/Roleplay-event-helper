-- Shared WoW API stub for testing the addon outside the game with Lua 5.1,
-- the same version the client runs.
--
-- Only enough of the API to exercise our own load path is stubbed, and each
-- stub behaves like the real thing in the ways we depend on: ADDON_LOADED
-- carries the addon name, party unit tokens exclude the player, saved variables
-- persist as a plain global across a reload, and so on.

local Harness = {}

local addonName = "RoleplayEventHelper"

--------------------------------------------------------------------------------
-- Paths
--------------------------------------------------------------------------------

local testDir = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "Tests"
Harness.addonDir = testDir .. "/../" .. addonName
Harness.addonName = addonName

--------------------------------------------------------------------------------
-- Assertions
--------------------------------------------------------------------------------

Harness.failures = 0
Harness.passes = 0

function Harness.section(title)
	print("\n== " .. title .. " ==")
end

function Harness.check(label, condition, detail)
	if condition then
		Harness.passes = Harness.passes + 1
		print(("  PASS  %s"):format(label))
	else
		Harness.failures = Harness.failures + 1
		print(("  FAIL  %s%s"):format(label, detail and (" -- " .. tostring(detail)) or ""))
	end
	return condition and true or false
end

function Harness.checkEqual(label, actual, expected)
	return Harness.check(label, actual == expected,
		("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

function Harness.finish()
	print("")
	if Harness.failures == 0 then
		print(("All %d checks passed."):format(Harness.passes))
		os.exit(0)
	end
	print(("%d of %d checks failed."):format(Harness.failures, Harness.passes + Harness.failures))
	os.exit(1)
end

--------------------------------------------------------------------------------
-- TOC
--------------------------------------------------------------------------------

function Harness.readToc()
	local toc, files = {}, {}
	local path = Harness.addonDir .. "/" .. addonName .. ".toc"
	local handle = assert(io.open(path, "r"), "cannot open " .. path)

	for line in handle:lines() do
		local key, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
		if key then
			toc[key] = value
		else
			local file = line:match("^%s*([^#%s].-%.lua)%s*$")
			if file then
				files[#files + 1] = (file:gsub("\\", "/"))
			end
		end
	end

	handle:close()
	Harness.toc, Harness.tocFiles = toc, files
	return toc, files
end

--------------------------------------------------------------------------------
-- Stubbed API
--------------------------------------------------------------------------------

Harness.output = {}
Harness.clientInterface = nil  -- defaults to the TOC value
Harness.playerName = "Testchar"
Harness.now = 1000

local frames = {}
local timers = {}

Harness.sent = {}
Harness.sendError = nil
Harness.group = {
	inGroup = false,
	inRaid = false,
	inGuild = false,
	inInstance = false,
	isLeader = false,
	isAssistant = false,
	channels = {},
}

function Harness.clearOutput()
	Harness.output = {}
end

function Harness.clearSent()
	Harness.sent = {}
end

function Harness.resetGroup()
	Harness.group = {
		inGroup = false, inRaid = false, inGuild = false, inInstance = false,
		isLeader = false, isAssistant = false, channels = {},
	}
end

--- Move the clock forward, firing any timers that come due -- including timers
--- scheduled by the callbacks themselves, which is how the send queue paces
--- itself one message at a time.
function Harness.advance(seconds)
	local target = Harness.now + seconds

	while true do
		local nextTimer, nextIndex
		for index, timer in ipairs(timers) do
			if timer.at <= target and (not nextTimer or timer.at < nextTimer.at) then
				nextTimer, nextIndex = timer, index
			end
		end

		if not nextTimer then
			break
		end

		table.remove(timers, nextIndex)
		Harness.now = math.max(Harness.now, nextTimer.at)
		nextTimer.callback()
	end

	Harness.now = target
end

function Harness.pendingTimers()
	return #timers
end

function Harness.clearTimers()
	timers = {}
end

--- The chat messages the addon would have broadcast, as plain strings.
function Harness.sentMessages()
	local list = {}
	for index, entry in ipairs(Harness.sent) do
		list[index] = entry.message
	end
	return list
end

--- Every line printed since the last clearOutput, stripped of colour escapes.
function Harness.outputText()
	local plain = {}
	for index, line in ipairs(Harness.output) do
		plain[index] = (line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	end
	return table.concat(plain, "\n")
end

function Harness.printOutput()
	for _, line in ipairs(Harness.output) do
		print("      | " .. (line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
	end
end

function Harness.installStubs()
	Harness.readToc()

	DEFAULT_CHAT_FRAME = {
		AddMessage = function(self, message)
			Harness.output[#Harness.output + 1] = message
		end,
	}

	function GetBuildInfo()
		return "12.0.7", "62000", "Aug  1 2026",
			Harness.clientInterface or tonumber(Harness.toc["Interface"])
	end

	function GetTime()
		return Harness.now
	end

	-- WoW exposes date() as a global; standalone Lua has it under os.
	date = os.date

	function UnitName(unit)
		if unit == "player" then
			return Harness.playerName
		end
		return nil
	end

	C_AddOns = {
		GetAddOnMetadata = function(name, key)
			if name ~= addonName then
				return nil
			end
			return Harness.toc[key]
		end,
	}

	SlashCmdList = {}

	----------------------------------------------------------------------------
	-- Chat, group state and timers
	----------------------------------------------------------------------------

	-- Everything the addon would say to other players lands in Harness.sent
	-- instead, so a test can assert on exactly what would have been broadcast.
	function SendChatMessage(message, chatType, languageID, target)
		if Harness.sendError then
			error(Harness.sendError, 0)
		end
		Harness.sent[#Harness.sent + 1] = {
			message = message, chatType = chatType, target = target,
		}
	end

	function IsInGroup()
		return Harness.group.inGroup or Harness.group.inRaid
	end

	function IsInRaid()
		return Harness.group.inRaid
	end

	function IsInGuild()
		return Harness.group.inGuild
	end

	function IsInInstance()
		return Harness.group.inInstance, "none"
	end

	function UnitIsGroupLeader(unit)
		return unit == "player" and Harness.group.isLeader or false
	end

	function UnitIsGroupAssistant(unit)
		return unit == "player" and Harness.group.isAssistant or false
	end

	--- Returns 0 when not joined, matching the live API.
	function GetChannelName(name)
		local id = Harness.group.channels[name]
		if not id then
			return 0
		end
		return id, name
	end

	C_Timer = {
		After = function(delay, callback)
			timers[#timers + 1] = { at = Harness.now + delay, callback = callback }
		end,
	}

	function CreateFrame()
		local frame = {
			_events = {},
			RegisterEvent = function(self, event) self._events[event] = true end,
			UnregisterEvent = function(self, event) self._events[event] = nil end,
			IsEventRegistered = function(self, event) return self._events[event] == true end,
			SetScript = function(self, which, fn)
				if which == "OnEvent" then self._onEvent = fn end
			end,
		}
		frames[#frames + 1] = frame
		return frame
	end
end

--------------------------------------------------------------------------------
-- Loading and events
--------------------------------------------------------------------------------

--- Load every file the TOC lists, in TOC order, as the client would.
--- Existing frames are dropped first so a reload does not double-fire events.
function Harness.loadAddon()
	frames = {}

	local namespace = {}
	for _, file in ipairs(Harness.tocFiles) do
		local path = Harness.addonDir .. "/" .. file
		local chunk, err = loadfile(path)
		if not chunk then
			Harness.check("load " .. file, false, err)
			return namespace
		end

		local ok, runErr = pcall(chunk, addonName, namespace)
		if not ok then
			Harness.check("run " .. file, false, runErr)
			return namespace
		end
	end

	Harness.namespace = namespace
	return namespace
end

function Harness.fire(event, ...)
	for _, frame in ipairs(frames) do
		if frame._events[event] and frame._onEvent then
			frame._onEvent(frame, event, ...)
		end
	end
end

--- Full startup: load the files, then fire the events the client fires.
function Harness.login()
	local namespace = Harness.loadAddon()
	Harness.fire("ADDON_LOADED", addonName)
	Harness.fire("PLAYER_LOGIN")
	return namespace
end

--- Simulate /reload: saved variables persist, everything else is rebuilt.
function Harness.reload()
	return Harness.login()
end

--- Wipe saved variables, as on a fresh install.
function Harness.wipeSavedVariables()
	RoleplayEventHelperDB = nil
end

function Harness.runSlash(input)
	Harness.clearOutput()
	SlashCmdList["ROLEPLAYEVENTHELPER"](input)
	return Harness.outputText()
end

--------------------------------------------------------------------------------
-- Global pollution
--------------------------------------------------------------------------------

-- Every addon shares one environment in WoW, so a stray global can collide with
-- another addon and produce a bug that only reproduces on someone else's
-- machine. Snapshot before loading, compare after.

local globalsBefore

function Harness.snapshotGlobals()
	globalsBefore = {}
	for key in pairs(_G) do
		globalsBefore[key] = true
	end
end

function Harness.checkNoLeakedGlobals(allowed)
	local leaked = {}
	for key in pairs(_G) do
		if not globalsBefore[key] and not allowed[key] then
			leaked[#leaked + 1] = key
		end
	end
	table.sort(leaked)
	return Harness.check("no unexpected globals created", #leaked == 0, table.concat(leaked, ", "))
end

Harness.ALLOWED_GLOBALS = {
	RoleplayEventHelper = true,
	RoleplayEventHelperDB = true,
	SLASH_ROLEPLAYEVENTHELPER1 = true,
	SLASH_ROLEPLAYEVENTHELPER2 = true,
}

return Harness
