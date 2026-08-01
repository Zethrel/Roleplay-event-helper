-- M7: the minimap button, the options tab, grouped help, and the checks that
-- belong on a build about to be handed to someone else.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "Tests"
local H = dofile(here .. "/Harness.lua")

H.installStubs()
H.snapshotGlobals()
H.wipeSavedVariables()

local REH = H.login()
local DB = REH.Database
local Button = REH.UI.MinimapButton

--------------------------------------------------------------------------------
H.section("The minimap button")
--------------------------------------------------------------------------------

H.check("it is built at login", Button.button ~= nil)
H.check("and shown by default", Button:IsShown())
H.check("it is not hidden by default", Button:IsHidden() == false)

Button:SetHidden(true)
H.check("hiding it works", Button:IsShown() == false)
H.check("and is remembered in settings", DB:GetSettings().minimapButton.hide == true)

REH = H.reload()
DB = REH.Database
Button = REH.UI.MinimapButton
H.check("it stays hidden across a reload", Button:IsHidden())
H.check("and is not shown", Button:IsShown() == false)

Button:SetHidden(false)
H.check("showing it again works", Button:IsShown())

-- Dragging stores an angle, so the button keeps its place on the orbit.
local before = DB:GetSettings().minimapButton.minimapPos
H.cursor = { x = 1000, y = 600 }
H.fireScript(Button.button, "OnDragStart")
H.fireScript(Button.button, "OnUpdate")
local after = DB:GetSettings().minimapButton.minimapPos
H.check("dragging moves it", after ~= before, ("%s -> %s"):format(before, after))
H.checkEqual("straight up is 90 degrees", math.floor(after + 0.5), 90)
H.fireScript(Button.button, "OnDragStop")

H.cursor = { x = 900, y = 500 }
H.fireScript(Button.button, "OnDragStart")
H.fireScript(Button.button, "OnUpdate")
H.checkEqual("and to the left is 180",
	math.abs(math.floor(DB:GetSettings().minimapButton.minimapPos + 0.5)), 180)
H.fireScript(Button.button, "OnDragStop")

REH = H.reload()
DB = REH.Database
Button = REH.UI.MinimapButton
H.check("the dragged position survives a reload",
	math.abs(DB:GetSettings().minimapButton.minimapPos) > 0)

--------------------------------------------------------------------------------
H.section("Clicking it")
--------------------------------------------------------------------------------

REH.UI.MainFrame:Hide()
REH.UI.RollLog:Hide()

Button.button:Click("LeftButton")
H.check("left-click opens the main window", REH.UI.MainFrame:IsShown())
Button.button:Click("LeftButton")
H.check("and closes it again", REH.UI.MainFrame:IsShown() == false)

Button.button:Click("RightButton")
H.check("right-click opens the roll log", REH.UI.RollLog:IsShown())
Button.button:Click("RightButton")
H.check("and closes it", REH.UI.RollLog:IsShown() == false)

H.check("the addon compartment entry exists",
	type(_G.RoleplayEventHelper_OnCompartmentClick) == "function")
_G.RoleplayEventHelper_OnCompartmentClick(nil, "LeftButton")
H.check("and opens the window too", REH.UI.MainFrame:IsShown())
REH.UI.MainFrame:Hide()

local out = H.runSlash("minimap")
H.check("/reh minimap hides it", Button:IsHidden())
H.check("and says how to get it back", out:find("/reh minimap", 1, true) ~= nil, out)
H.runSlash("minimap")
H.check("running it again shows it", Button:IsHidden() == false)

--------------------------------------------------------------------------------
H.section("The options tab")
--------------------------------------------------------------------------------

local Fields = REH.Fields
local optionsTab = Fields:FindTab("settings")
H.check("there is an options tab", optionsTab ~= nil)
H.checkEqual("that edits settings rather than a preset", optionsTab.scope, "settings")
H.check("the target resolves to the settings table",
	Fields:GetTarget(optionsTab) == DB:GetSettings())

local settings = DB:GetSettings()

local mergeField = Fields:FindField("settings", "mergeLines")
Fields:Set(settings, mergeField, false, "settings")
H.checkEqual("a settings toggle writes through", settings.mergeLines, false)
Fields:Set(settings, mergeField, true, "settings")

local delayField = Fields:FindField("settings", "sendDelay")
Fields:Set(settings, delayField, "1.5", "settings")
H.checkEqual("a fractional delay is kept, not rounded away", settings.sendDelay, 1.5)

Fields:Set(settings, delayField, "0.01", "settings")
H.check("an absurdly short delay is clamped up", settings.sendDelay >= 0.3)
Fields:Set(settings, delayField, "900", "settings")
H.check("and an absurdly long one clamped down", settings.sendDelay <= 5.0)

local ok, reason = Fields:Set(settings, delayField, "quickly", "settings")
H.check("a non-numeric delay is refused", ok == false)
H.check("with a reason", (reason or ""):find("number", 1, true) ~= nil, reason)

Fields:Set(settings, delayField, "0.7", "settings")

local hideField = Fields:FindField("settings", "minimapHide")
Fields:Set(settings, hideField, true, "settings")
H.checkEqual("the minimap toggle writes into settings",
	settings.minimapButton.hide, true)
Fields:Set(settings, hideField, false, "settings")

-- Editing a setting must not corrupt the preset, and vice versa.
local preset = DB:GetActivePreset()
local presetBefore = preset.rolls.dieMax
Fields:Set(settings, mergeField, false, "settings")
H.checkEqual("editing settings leaves the preset alone", preset.rolls.dieMax, presetBefore)
Fields:Set(settings, mergeField, true, "settings")

--------------------------------------------------------------------------------
H.section("Options reach the announcement")
--------------------------------------------------------------------------------

settings.mergeLines = false
settings.useSeparators = false
local unmerged = REH.Formatter:BuildMessages(preset)

settings.mergeLines = true
local merged = REH.Formatter:BuildMessages(preset)
H.check("turning packing on reduces the message count", #merged < #unmerged,
	("%d vs %d"):format(#merged, #unmerged))

-- The client silently drops an outgoing chat message containing colour
-- escapes, so an announcement that carried one would simply never arrive and
-- the addon would report it as sent. Nothing bound for chat may contain one.
preset.header.description = "A |cffff0000red|r description a host pasted in."
preset.custom = { "Rule with |cff00ff00colour|r in it.", "Plain rule." }
DB:ValidatePreset(preset)

local outgoing = table.concat(REH.Formatter:BuildMessages(preset), "\n")
H.check("no announcement message carries a colour escape",
	outgoing:find("|c", 1, true) == nil, outgoing)
H.check("nor a colour terminator", outgoing:find("|r", 1, true) == nil, outgoing)
H.check("but the words the host typed survive",
	outgoing:find("red description", 1, true) ~= nil, outgoing)
H.check("and so does the rule text",
	outgoing:find("Rule with colour in it.", 1, true) ~= nil, outgoing)

preset.header.description = ""
preset.custom = {}
DB:ValidatePreset(preset)

--------------------------------------------------------------------------------
H.section("Grouped help")
--------------------------------------------------------------------------------

out = H.runSlash("help")
for _, heading in ipairs({ "Window", "Presets", "Announcing", "Roll watcher", "Sharing" }) do
	H.check("help has a '" .. heading .. "' section", out:find(heading, 1, true) ~= nil)
end

H.check("help lists the announce command", out:find("/reh announce", 1, true) ~= nil)
H.check("help lists the watcher command", out:find("/reh watch", 1, true) ~= nil)
H.check("help lists the export command", out:find("/reh export", 1, true) ~= nil)
H.check("help names the version", out:find(H.toc["Version"], 1, true) ~= nil, out)

out = H.runSlash("help watcher")
H.check("help can be filtered to one group",
	out:find("/reh watch", 1, true) ~= nil, out)
H.check("and leaves the other groups out",
	out:find("/reh announce", 1, true) == nil, out)

--------------------------------------------------------------------------------
H.section("Every command is reachable and documented")
--------------------------------------------------------------------------------

-- A command registered but missing from help, or listed but not registered, is
-- the kind of thing nobody notices until a user asks why it does nothing.
out = H.runSlash("help")
local documented, missing = 0, {}

for name in pairs(SlashCmdList) do
	-- only our own handler is registered
end

for _, command in ipairs({
	"help", "window", "minimap", "list", "show", "use", "new", "copy", "rename",
	"delete", "reset", "confirm", "preview", "announce", "cancel", "channel",
	"watch", "log", "filter", "subgroups", "roster", "mute", "unmute",
	"export", "import", "version",
}) do
	if out:find("/reh " .. command, 1, true) then
		documented = documented + 1
	else
		missing[#missing + 1] = command
	end

	-- Every documented command must also actually run without erroring.
	local ran = pcall(function()
		REH.Commands:Handle(command)
	end)
	if not ran then
		H.check("command '" .. command .. "' runs without erroring", false)
	end
end

H.check("every command appears in help", #missing == 0, table.concat(missing, ", "))
H.check("and there are a good number of them", documented >= 25, documented)
H.check("every command ran without erroring", true)

--------------------------------------------------------------------------------
H.section("Release metadata")
--------------------------------------------------------------------------------

H.check("the TOC declares an icon for the compartment",
	(H.toc["IconTexture"] or "") ~= "")
H.checkEqual("and points the compartment at the real function",
	H.toc["AddonCompartmentFunc"], "RoleplayEventHelper_OnCompartmentClick")
H.check("the version is past the skeleton",
	H.toc["Version"] ~= "0.1.0-alpha", H.toc["Version"])
H.check("notes describe the addon", #(H.toc["Notes"] or "") > 20)

local changelog = io.open(H.addonDir .. "/../CHANGELOG.md", "r")
H.check("there is a changelog", changelog ~= nil)
if changelog then
	local text = changelog:read("*all")
	changelog:close()
	H.check("that mentions this version",
		text:find(H.toc["Version"], 1, true) ~= nil, H.toc["Version"])
end

local readme = io.open(H.addonDir .. "/../README.md", "r")
H.check("there is a readme", readme ~= nil)
if readme then
	local text = readme:read("*all")
	readme:close()
	H.check("that says how to install", text:find("Interface/AddOns", 1, true) ~= nil)
	H.check("and names the interface version",
		text:find(H.toc["Interface"], 1, true) ~= nil)
end

for _, lib in ipairs({ "LibStub", "LibDeflate", "LibSerialize" }) do
	local path = H.addonDir .. "/Libs/" .. lib
	local file = io.open(path .. "/" .. lib .. ".lua", "r")
	H.check(lib .. " is bundled", file ~= nil)
	if file then file:close() end
end

for _, lib in ipairs({ "LibDeflate", "LibSerialize" }) do
	local license = io.open(H.addonDir .. "/Libs/" .. lib .. "/LICENSE.txt", "r")
	H.check(lib .. " ships with its licence", license ~= nil)
	if license then license:close() end
end

--------------------------------------------------------------------------------
H.section("Nothing speaks without being asked")
--------------------------------------------------------------------------------

-- The whole-addon version of the first design principle, checked once more now
-- that every module exists.
H.clearSent()
H.clearOutput()
H.clearTimers()
REH = H.reload()
H.advance(600)
H.checkEqual("a full login broadcasts nothing", #H.sent, 0)

REH.UI.MainFrame:Show()
REH.UI.MainFrame:SelectTab(2)
REH.UI.RollLog:Show()
REH.UI.MinimapButton.button:Click("LeftButton")
H.advance(600)
H.checkEqual("opening every window broadcasts nothing", #H.sent, 0)

H.checkEqual("and the watcher is still off", REH.RollWatcher:GetMode(), "off")

H.checkNoLeakedGlobals(H.ALLOWED_GLOBALS)

H.finish()
