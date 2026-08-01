-- Minimal WoW API stub so M0 can be loaded and exercised outside the game.
-- Verifies: clean load, event bootstrap, slash registration, SavedVariables
-- persistence across a simulated reload, and the interface-version self-check.

local ADDON_DIR = arg[1] or "RoleplayEventHelper"
local ADDON_NAME = "RoleplayEventHelper"

local failures = 0
local function check(label, condition, detail)
	if condition then
		print(("  PASS  %s"):format(label))
	else
		failures = failures + 1
		print(("  FAIL  %s%s"):format(label, detail and (" -- " .. detail) or ""))
	end
end

--------------------------------------------------------------------------------
-- Read the real TOC so the stub reports what the addon actually ships
--------------------------------------------------------------------------------

local toc = {}
local tocOrder = {}
do
	local path = ADDON_DIR .. "/" .. ADDON_NAME .. ".toc"
	local f = assert(io.open(path, "r"), "cannot open " .. path)
	for line in f:lines() do
		local key, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
		if key then
			toc[key] = value
		else
			local file = line:match("^%s*([^#%s].-%.lua)%s*$")
			if file then
				tocOrder[#tocOrder + 1] = (file:gsub("\\", "/"))
			end
		end
	end
	f:close()
end

--------------------------------------------------------------------------------
-- WoW API stubs
--------------------------------------------------------------------------------

local CLIENT_VERSION, CLIENT_BUILD, CLIENT_DATE = "12.0.7", "62000", "Aug  1 2026"
local clientInterface = 120007

local output = {}
DEFAULT_CHAT_FRAME = {
	AddMessage = function(self, msg)
		output[#output + 1] = msg
		print("      | " .. (msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
	end,
}

function GetBuildInfo()
	return CLIENT_VERSION, CLIENT_BUILD, CLIENT_DATE, clientInterface
end

C_AddOns = {
	GetAddOnMetadata = function(name, key)
		if name ~= ADDON_NAME then return nil end
		return toc[key]
	end,
}

SlashCmdList = {}

local frames = {}
function CreateFrame(frameType)
	local frame = {
		_events = {},
		_script = nil,
		RegisterEvent = function(self, event) self._events[event] = true end,
		UnregisterEvent = function(self, event) self._events[event] = nil end,
		SetScript = function(self, which, fn) if which == "OnEvent" then self._script = fn end end,
		Fire = function(self, event, ...)
			if self._events[event] and self._script then
				self._script(self, event, ...)
			end
		end,
	}
	frames[#frames + 1] = frame
	return frame
end

local function FireAll(event, ...)
	for _, frame in ipairs(frames) do
		frame:Fire(event, ...)
	end
end

--------------------------------------------------------------------------------
-- Load the addon exactly as the TOC orders it
--------------------------------------------------------------------------------

local function LoadAddon()
	local namespace = {}
	for _, file in ipairs(tocOrder) do
		local path = ADDON_DIR .. "/" .. file
		local chunk, err = loadfile(path)
		if not chunk then
			failures = failures + 1
			print(("  FAIL  load %s -- %s"):format(file, err))
			return namespace
		end
		local ok, runErr = pcall(chunk, ADDON_NAME, namespace)
		if not ok then
			failures = failures + 1
			print(("  FAIL  run %s -- %s"):format(file, runErr))
			return namespace
		end
	end
	return namespace
end

print("\n== TOC ==")
check("declares an Interface value", toc["Interface"] ~= nil)
check("Interface matches client " .. clientInterface,
	tonumber(toc["Interface"]) == clientInterface,
	"TOC says " .. tostring(toc["Interface"]))
check("declares SavedVariables", toc["SavedVariables"] == "RoleplayEventHelperDB",
	tostring(toc["SavedVariables"]))
check("lists files to load", #tocOrder > 0)
for _, file in ipairs(tocOrder) do
	local fh = io.open(ADDON_DIR .. "/" .. file, "r")
	check("file exists: " .. file, fh ~= nil)
	if fh then fh:close() end
end

print("\n== First login (fresh install) ==")

-- Global pollution is a real hazard in WoW: every addon shares one environment,
-- so an accidental global can collide with another addon's. Snapshot _G and
-- assert the addon only creates names it is entitled to.
local globalsBefore = {}
for key in pairs(_G) do globalsBefore[key] = true end

local ALLOWED_GLOBALS = {
	RoleplayEventHelper = true,
	RoleplayEventHelperDB = true,
	SLASH_ROLEPLAYEVENTHELPER1 = true,
	SLASH_ROLEPLAYEVENTHELPER2 = true,
}

local REH = LoadAddon()
check("namespace populated", REH.Print ~= nil and REH.L ~= nil)

FireAll("ADDON_LOADED", "SomeOtherAddon")
check("ignores other addons' ADDON_LOADED", RoleplayEventHelperDB == nil)

FireAll("ADDON_LOADED", ADDON_NAME)
check("SavedVariables table created", type(RoleplayEventHelperDB) == "table")
check("dbVersion stamped", RoleplayEventHelperDB.dbVersion == 1)
check("presets table created", type(RoleplayEventHelperDB.presets) == "table")
check("settings table created", type(RoleplayEventHelperDB.settings) == "table")
check("loadCount == 1 on first load", RoleplayEventHelperDB.loadCount == 1,
	tostring(RoleplayEventHelperDB.loadCount))
check("slash command /reh registered", SlashCmdList["ROLEPLAYEVENTHELPER"] ~= nil)
check("/reh alias defined", SLASH_ROLEPLAYEVENTHELPER1 == "/reh")
check("/rpevent alias defined", SLASH_ROLEPLAYEVENTHELPER2 == "/rpevent")

local leaked = {}
for key in pairs(_G) do
	if not globalsBefore[key] and not ALLOWED_GLOBALS[key] then
		leaked[#leaked + 1] = key
	end
end
table.sort(leaked)
check("no unexpected globals created", #leaked == 0, table.concat(leaked, ", "))

FireAll("PLAYER_LOGIN")
local warned = false
for _, line in ipairs(output) do
	if line:find("out%-of%-date") or line:find("TOC interface") then warned = true end
end
check("no version warning when TOC matches client", not warned)

print("\n== Slash commands ==")
local handler = SlashCmdList["ROLEPLAYEVENTHELPER"]
output = {}
handler("")
check("bare /reh produces output", #output > 0)

output = {}
handler("help")
check("/reh help lists commands", #output > 0)

output = {}
handler("version")
local sawInterface = false
for _, line in ipairs(output) do
	if line:find("120007") then sawInterface = true end
end
check("/reh version reports the interface number", sawInterface)

output = {}
handler("bogus")
check("unknown command warns", #output == 1 and output[1]:find("Unknown command") ~= nil)

print("\n== Simulated /reload (persistence) ==")
frames = {}
LoadAddon()
FireAll("ADDON_LOADED", ADDON_NAME)
check("loadCount survived reload and incremented", RoleplayEventHelperDB.loadCount == 2,
	tostring(RoleplayEventHelperDB.loadCount))
check("dbVersion not clobbered", RoleplayEventHelperDB.dbVersion == 1)
check("firstInstalledVersion preserved",
	RoleplayEventHelperDB.firstInstalledVersion == toc["Version"])

print("\n== Client patched ahead of TOC (self-check) ==")
clientInterface = 120100
frames = {}
output = {}
LoadAddon()
FireAll("ADDON_LOADED", ADDON_NAME)
FireAll("PLAYER_LOGIN")
local told = false
for _, line in ipairs(output) do
	if line:find("120100") then told = true end
end
check("warns and names the correct interface number", told)

print("")
if failures == 0 then
	print("All checks passed.")
	os.exit(0)
else
	print(failures .. " check(s) failed.")
	os.exit(1)
end
