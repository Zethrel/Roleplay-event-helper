-- M0: the addon loads cleanly, registers its commands, persists saved
-- variables across a reload, and notices when the client outruns its TOC.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "Tests"
local H = dofile(here .. "/Harness.lua")

H.installStubs()
H.snapshotGlobals()

H.section("TOC")
local toc, files = H.toc, H.tocFiles
H.check("declares an Interface value", toc["Interface"] ~= nil)
H.check("Interface is a plain number", tonumber(toc["Interface"]) ~= nil, toc["Interface"])
H.checkEqual("declares SavedVariables", toc["SavedVariables"], "RoleplayEventHelperDB")
H.check("declares a Version", (toc["Version"] or "") ~= "")
H.check("lists files to load", #files > 0)
for _, file in ipairs(files) do
	local handle = io.open(H.addonDir .. "/" .. file, "r")
	H.check("file exists: " .. file, handle ~= nil)
	if handle then handle:close() end
end

H.section("Fresh install")
H.wipeSavedVariables()
local REH = H.loadAddon()
H.check("namespace populated", REH.Print ~= nil and REH.L ~= nil and REH.Database ~= nil)

H.fire("ADDON_LOADED", "SomeOtherAddon")
H.check("ignores another addon's ADDON_LOADED", RoleplayEventHelperDB == nil)

H.fire("ADDON_LOADED", H.addonName)
H.check("saved variables created", type(RoleplayEventHelperDB) == "table")
H.checkEqual("dbVersion stamped", RoleplayEventHelperDB.dbVersion, REH.DB_VERSION)
H.checkEqual("loadCount is 1 on first load", RoleplayEventHelperDB.loadCount, 1)
H.check("marked as a fresh install", REH.isFreshInstall == true)
H.check("slash handler registered", SlashCmdList["ROLEPLAYEVENTHELPER"] ~= nil)
H.checkEqual("/reh registered", SLASH_ROLEPLAYEVENTHELPER1, "/reh")
H.checkEqual("/rpevent registered", SLASH_ROLEPLAYEVENTHELPER2, "/rpevent")
H.checkNoLeakedGlobals(H.ALLOWED_GLOBALS)

H.section("Silence at login")
H.clearOutput()
H.fire("PLAYER_LOGIN")
H.check("says nothing at login when the TOC matches the client", H.outputText() == "",
	H.outputText())

H.section("Slash commands")
local out = H.runSlash("help")
H.check("/reh help lists commands", out:find("/reh list", 1, true) ~= nil)

H.runSlash("")
H.check("bare /reh opens the window", REH.UI.MainFrame:IsShown())
H.runSlash("")
H.check("and closes it again", REH.UI.MainFrame:IsShown() == false)

out = H.runSlash("version")
H.check("/reh version reports the interface number",
	out:find(tostring(toc["Interface"]), 1, true) ~= nil)

out = H.runSlash("bogus")
H.check("unknown command is reported", out:find("Unknown command", 1, true) ~= nil)

H.section("Persistence across /reload")
H.reload()
H.checkEqual("loadCount incremented", RoleplayEventHelperDB.loadCount, 2)
H.checkEqual("dbVersion unchanged", RoleplayEventHelperDB.dbVersion, REH.DB_VERSION)
H.checkEqual("firstInstalledVersion preserved",
	RoleplayEventHelperDB.firstInstalledVersion, toc["Version"])
H.check("no longer reported as a fresh install", H.namespace.isFreshInstall == false)

H.section("Client patched ahead of the TOC")
H.clientInterface = tonumber(toc["Interface"]) + 100
H.clearOutput()
H.login()
H.check("warns and names the correct interface number",
	H.outputText():find(tostring(H.clientInterface), 1, true) ~= nil, H.outputText())
H.clientInterface = nil

H.finish()
