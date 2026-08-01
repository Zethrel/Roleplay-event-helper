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
Harness.popups = {}
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

	----------------------------------------------------------------------------
	-- Widgets
	----------------------------------------------------------------------------

	UIParent = Harness.newWidget("Frame")
	UISpecialFrames = {}
	StaticPopupDialogs = {}
	ACCEPT, CANCEL, YES, NO = "Accept", "Cancel", "Yes", "No"

	GameTooltip = Harness.newWidget("GameTooltip")

	function StaticPopup_Show(which, arg1)
		Harness.popups[#Harness.popups + 1] = { which = which, arg1 = arg1 }
		return Harness.newWidget("Frame")
	end

	function CreateFrame(frameType, name, parent, template)
		local frame = Harness.newWidget(frameType or "Frame", template)
		frame._name = name
		frame._parent = parent

		if name then
			_G[name] = frame
		end

		frames[#frames + 1] = frame
		return frame
	end
end

--------------------------------------------------------------------------------
-- Widget mock
--------------------------------------------------------------------------------

-- Methods the addon is allowed to call. Anything outside this set raises,
-- rather than silently doing nothing: a no-op stub would let a misspelled or
-- imaginary API method pass the tests and then break in the game. Adding an
-- entry here is a deliberate statement that the method exists in the client.
local WIDGET_METHODS = {
	-- geometry
	SetPoint = true, SetAllPoints = true, ClearAllPoints = true, GetPoint = true,
	SetSize = true, SetWidth = true, SetHeight = true, GetWidth = true, GetHeight = true,
	-- visibility
	Show = true, Hide = true, IsShown = true, IsVisible = true, SetShown = true,
	SetAlpha = true, GetAlpha = true,
	-- hierarchy and identity
	GetParent = true, SetParent = true, GetName = true, SetID = true, GetID = true,
	SetFrameStrata = true, SetFrameLevel = true, SetToplevel = true,
	SetClampedToScreen = true,
	-- scripts and events
	SetScript = true, GetScript = true, HookScript = true,
	RegisterEvent = true, UnregisterEvent = true, IsEventRegistered = true,
	RegisterForDrag = true, RegisterForClicks = true,
	EnableMouse = true, SetMovable = true, StartMoving = true, StopMovingOrSizing = true,
	SetPropagateKeyboardInput = true,
	-- children
	CreateFontString = true, CreateTexture = true,
	-- text
	SetText = true, GetText = true, SetJustifyH = true, SetJustifyV = true,
	SetTextColor = true, SetFontObject = true, SetNormalFontObject = true,
	SetMaxLetters = true, SetMultiLine = true, SetAutoFocus = true, SetNumeric = true,
	SetCursorPosition = true, HighlightText = true, SetFocus = true, ClearFocus = true,
	-- buttons
	Click = true, SetEnabled = true, Enable = true, Disable = true, IsEnabled = true,
	SetChecked = true, GetChecked = true,
	-- textures
	SetColorTexture = true, SetTexture = true, SetVertexColor = true,
	-- scrolling
	SetScrollChild = true, GetScrollChild = true, SetVerticalScroll = true,
	GetVerticalScrollRange = true, UpdateScrollChildRect = true,
	-- tooltip
	SetOwner = true, AddLine = true, AddDoubleLine = true, ClearLines = true,
}

Harness.WIDGET_METHODS = WIDGET_METHODS

local widgetMeta = {}

widgetMeta.__index = function(widget, key)
	if WIDGET_METHODS[key] then
		return function(self, ...)
			return Harness.widgetCall(self, key, ...)
		end
	end
	return nil
end

--- The behaviour of the stubbed methods that actually need to do something.
function Harness.widgetCall(widget, method, a, b, c, d, e)
	if method == "Show" then
		widget._shown = true
	elseif method == "Hide" then
		widget._shown = false
	elseif method == "SetShown" then
		widget._shown = a and true or false
	elseif method == "IsShown" or method == "IsVisible" then
		return widget._shown and true or false
	elseif method == "SetText" then
		widget._text = tostring(a or "")
	elseif method == "GetText" then
		return widget._text or ""
	elseif method == "SetChecked" then
		widget._checked = a and true or false
	elseif method == "GetChecked" then
		return widget._checked and true or false
	elseif method == "SetEnabled" then
		widget._enabled = a and true or false
	elseif method == "Enable" then
		widget._enabled = true
	elseif method == "Disable" then
		widget._enabled = false
	elseif method == "IsEnabled" then
		return widget._enabled ~= false
	elseif method == "SetScript" then
		widget._scripts[a] = b
		if a == "OnEvent" then
			widget._onEvent = b
		end
	elseif method == "GetScript" then
		return widget._scripts[a]
	elseif method == "HookScript" then
		widget._scripts[a] = b
	elseif method == "RegisterEvent" then
		widget._events[a] = true
	elseif method == "UnregisterEvent" then
		widget._events[a] = nil
	elseif method == "IsEventRegistered" then
		return widget._events[a] == true
	elseif method == "SetPoint" then
		widget._point = { a, b, c, d, e }
	elseif method == "GetPoint" then
		local point = widget._point or { "CENTER", nil, "CENTER", 0, 0 }
		return point[1], point[2], point[3], point[4], point[5]
	elseif method == "GetName" then
		return widget._name
	elseif method == "GetParent" then
		return widget._parent
	elseif method == "CreateFontString" then
		return Harness.newWidget("FontString")
	elseif method == "CreateTexture" then
		return Harness.newWidget("Texture")
	elseif method == "SetScrollChild" then
		widget._scrollChild = a
	elseif method == "GetScrollChild" then
		return widget._scrollChild
	elseif method == "Click" then
		local handler = widget._scripts["OnClick"]
		if handler then
			handler(widget, a or "LeftButton")
		end
	end

	return widget
end

function Harness.newWidget(widgetType, template)
	local widget = {
		_type = widgetType,
		_template = template,
		_scripts = {},
		_events = {},
		_shown = false,
	}
	return setmetatable(widget, widgetMeta)
end

--- Fire a named script handler on a widget, as the client would.
function Harness.fireScript(widget, scriptName, ...)
	local handler = widget._scripts[scriptName]
	if not handler then
		return false
	end
	handler(widget, ...)
	return true
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
	RoleplayEventHelperFrame = true,
	SLASH_ROLEPLAYEVENTHELPER1 = true,
	SLASH_ROLEPLAYEVENTHELPER2 = true,
}

return Harness
