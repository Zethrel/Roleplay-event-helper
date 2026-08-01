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

function Harness.clearOutput()
	Harness.output = {}
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
