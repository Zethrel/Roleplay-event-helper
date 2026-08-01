-- Diagnostics and send modes.
--
-- "Interface action failed because of an AddOn" is not a Lua error, so
-- /console scriptErrors never surfaces it. Without a listener the host sees an
-- alarming message and has no way to find out what caused it.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "Tests"
local H = dofile(here .. "/Harness.lua")

H.installStubs()
H.snapshotGlobals()
H.wipeSavedVariables()

local REH = H.login()
local DB = REH.Database
local Diagnostics = REH.Diagnostics

--------------------------------------------------------------------------------
H.section("Blocked actions are reported")
--------------------------------------------------------------------------------

Diagnostics:Clear()
H.clearOutput()

H.fire("ADDON_ACTION_BLOCKED", "RoleplayEventHelper", "SendChatMessage()")
H.check("a block by this addon is reported to the host",
	H.outputText():find("SendChatMessage", 1, true) ~= nil, H.outputText())
H.check("and the host is told which message that was",
	H.outputText():find("/reh blocked", 1, true) ~= nil, H.outputText())
H.checkEqual("and it is recorded", #Diagnostics:GetBlocked(), 1)

H.clearOutput()
H.fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "UseAction()")
H.checkEqual("another addon's block is not blamed on the host", H.outputText(), "")
H.checkEqual("but is still recorded for context", #Diagnostics:GetBlocked(), 2)

H.fire("ADDON_ACTION_FORBIDDEN", "RoleplayEventHelper", "CastSpellByName()")
H.checkEqual("forbidden actions are recorded too", #Diagnostics:GetBlocked(), 3)

local out = H.runSlash("blocked")
H.check("/reh blocked lists them", out:find("SendChatMessage", 1, true) ~= nil, out)
H.check("and names the other addon too", out:find("SomeOtherAddon", 1, true) ~= nil, out)
H.check("with the client build", out:find("interface", 1, true) ~= nil, out)
H.check("and the roll format string, for locale problems",
	out:find("rolls", 1, true) ~= nil, out)

Diagnostics:Clear()
out = H.runSlash("blocked")
H.check("with nothing recorded it says so",
	out:find("No blocked actions", 1, true) ~= nil, out)

--------------------------------------------------------------------------------
H.section("A block is attributed to a specific message")
--------------------------------------------------------------------------------

-- The context is what turns "an addon did something" into "message 6 of 10 to
-- SAY", which is the difference between a guess and a diagnosis.
Diagnostics:Clear()
Diagnostics:SetContext("sending message 6 of 10 to SAY")
H.clearOutput()
H.fire("ADDON_ACTION_BLOCKED", "RoleplayEventHelper", "SendChatMessage()")
H.check("the report names the message",
	H.outputText():find("message 6 of 10", 1, true) ~= nil, H.outputText())
Diagnostics:ClearContext()

Diagnostics:Clear()
H.clearOutput()
H.fire("ADDON_ACTION_BLOCKED", "RoleplayEventHelper", "SendChatMessage()")
H.check("and says nothing misleading when there is no context",
	H.outputText():find("while", 1, true) == nil, H.outputText())

--------------------------------------------------------------------------------
H.section("A block during an announcement stops it, once")
--------------------------------------------------------------------------------

-- The client refuses an addon send to /say without a hardware event behind it,
-- so a paced announcement has its first message land and every one after it
-- blocked. Nine identical error lines bury the one piece of advice that helps.
local preset = DB:GetActivePreset()
preset.custom = { "Rule one.", "Rule two.", "Rule three." }
DB:ValidatePreset(preset)
REH.Announcer:SetChannel(preset, "party")
H.group.inGroup = true
DB:GetSettings().sendMode = "paced"

Diagnostics:Clear()
H.clearSent()
H.clearTimers()
H.clearOutput()

REH.Announcer:Announce(preset, "Test")
H.check("the announcement started", REH.Announcer:IsSending())

H.clearOutput()
H.fire("ADDON_ACTION_BLOCKED", "RoleplayEventHelper", "UNKNOWN()")
H.check("a block stops the queue", REH.Announcer:IsSending() == false)
H.check("and names the message it died on",
	H.outputText():find("message 1 of", 1, true) ~= nil, H.outputText())

local firstReport = H.outputText()
H.fire("ADDON_ACTION_BLOCKED", "RoleplayEventHelper", "UNKNOWN()")
H.fire("ADDON_ACTION_BLOCKED", "RoleplayEventHelper", "UNKNOWN()")
H.check("further blocks do not repeat the report",
	H.outputText() == firstReport, H.outputText())

local sentBefore = #H.sent
H.advance(600)
H.checkEqual("and nothing more is sent", #H.sent, sentBefore)

-- On a restricted channel the report has to say what to do about it.
REH.Announcer:SetChannel(preset, "say")
DB:GetSettings().sendMode = "paced"
H.clearSent(); H.clearTimers(); H.clearOutput()
REH.Announcer:Announce(preset, "Test")
H.clearOutput()
H.fire("ADDON_ACTION_BLOCKED", "RoleplayEventHelper", "UNKNOWN()")
H.check("a restricted channel is explained",
	H.outputText():find("restricts addons", 1, true) ~= nil, H.outputText())
H.check("with a channel that works instead",
	H.outputText():find("party", 1, true) ~= nil, H.outputText())
H.advance(600)

--------------------------------------------------------------------------------
H.section("Send modes")
--------------------------------------------------------------------------------

-- Auto is the default, and picks per channel so a host never has to know that
-- /say needs different handling from party chat.
H.checkEqual("auto is the default", REH.DEFAULT_SETTINGS.sendMode, "auto")
H.checkEqual("/say bursts under auto",
	REH.Announcer:ResolveSendMode("SAY", "auto"), "burst")
H.checkEqual("so does /yell", REH.Announcer:ResolveSendMode("YELL", "auto"), "burst")
H.checkEqual("and a custom channel",
	REH.Announcer:ResolveSendMode("CHANNEL", "auto"), "burst")
H.checkEqual("and a whisper", REH.Announcer:ResolveSendMode("WHISPER", "auto"), "burst")
H.checkEqual("party stays paced", REH.Announcer:ResolveSendMode("PARTY", "auto"), "paced")
H.checkEqual("so does raid", REH.Announcer:ResolveSendMode("RAID", "auto"), "paced")
H.checkEqual("and guild", REH.Announcer:ResolveSendMode("GUILD", "auto"), "paced")
H.checkEqual("an explicit setting still wins",
	REH.Announcer:ResolveSendMode("PARTY", "burst"), "burst")
H.checkEqual("in both directions",
	REH.Announcer:ResolveSendMode("SAY", "paced"), "paced")

-- The behaviour that matters: announcing to /say under auto sends everything
-- in one call stack, so nothing depends on a timer the client will refuse.
DB:GetSettings().sendMode = "auto"
REH.Announcer:SetChannel(preset, "say")
H.clearSent(); H.clearTimers()
local expectedSay = #REH.Formatter:BuildMessages(preset)
REH.Announcer:Announce(preset, "Test")
H.checkEqual("announcing to /say sends every message immediately",
	#H.sent, expectedSay)
H.checkEqual("with no timer left to be refused", H.pendingTimers(), 0)

REH.Announcer:SetChannel(preset, "party")

local expected = #REH.Formatter:BuildMessages(preset)
H.check("there is more than one message to send", expected > 1)

-- Paced: one message now, the rest on timers.
DB:GetSettings().sendMode = "paced"
H.clearSent()
H.clearTimers()
REH.Announcer:Announce(preset, "Test")
H.checkEqual("paced sends one message immediately", #H.sent, 1)
H.check("and queues the rest", REH.Announcer:IsSending())
H.advance(600)
H.checkEqual("finishing the queue sends them all", #H.sent, expected)

-- Burst: every message in the call stack of the click that started it.
DB:GetSettings().sendMode = "burst"
H.clearSent()
H.clearTimers()
REH.Announcer:Announce(preset, "Test")
H.checkEqual("burst sends everything before returning", #H.sent, expected)
H.check("leaving nothing queued", REH.Announcer:IsSending() == false)
H.checkEqual("and no timers pending", H.pendingTimers(), 0)

local sameOrder = true
local pacedAgain = REH.Formatter:BuildMessages(preset)
for index, entry in ipairs(H.sent) do
	if entry.message ~= pacedAgain[index] then
		sameOrder = false
	end
end
H.check("burst sends the same messages in the same order", sameOrder)

H.clearOutput()
out = H.runSlash("sendmode")
H.check("/reh sendmode reports the mode", out:find("burst", 1, true) ~= nil, out)

out = H.runSlash("sendmode paced")
H.checkEqual("/reh sendmode paced switches back", DB:GetSettings().sendMode, "paced")

out = H.runSlash("sendmode sideways")
H.check("an unknown mode is refused", out:find("must be auto", 1, true) ~= nil, out)
H.checkEqual("leaving the mode alone", DB:GetSettings().sendMode, "paced")

DB:GetSettings().sendMode = "burst"
REH = H.reload()
DB = REH.Database
H.checkEqual("the mode survives a reload", DB:GetSettings().sendMode, "burst")
DB:GetSettings().sendMode = "paced"

RoleplayEventHelperDB.settings.sendMode = "nonsense"
REH = H.reload()
DB = REH.Database
H.checkEqual("a corrupt mode falls back to auto", DB:GetSettings().sendMode, "auto")

H.checkNoLeakedGlobals(H.ALLOWED_GLOBALS)

H.finish()
