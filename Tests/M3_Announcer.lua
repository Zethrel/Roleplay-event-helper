-- M3: the first milestone where the addon speaks to other players.
--
-- The things that matter here are all about restraint: it must not send when
-- the target is unavailable, must not send anything the host did not trigger,
-- must stop cleanly when cancelled, and must not leave a half-announced rule
-- set behind if the client refuses a message.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "Tests"
local H = dofile(here .. "/Harness.lua")

H.installStubs()
H.snapshotGlobals()
H.wipeSavedVariables()

local REH = H.login()
local DB = REH.Database
local Announcer = REH.Announcer

-- Reloading builds a fresh namespace, so anything held from the previous load
-- would talk to a module the slash commands no longer route to.
local function relogin()
	REH = H.login()
	DB = REH.Database
	Announcer = REH.Announcer
end

local function reset()
	H.clearSent()
	H.clearOutput()
	H.clearTimers()
	H.sendError = nil
	H.resetGroup()
	Announcer:Cancel()
	H.clearOutput()
end

--- Announce and let the whole paced queue drain.
local function announceFully(preset, name)
	Announcer:Announce(preset, name or "Test")
	H.advance(600)
end

--------------------------------------------------------------------------------
H.section("Nothing is sent without being asked")
--------------------------------------------------------------------------------

reset()
relogin()
H.advance(600)
H.checkEqual("logging in broadcasts nothing", #H.sent, 0)

reset()
H.runSlash("preview")
H.advance(600)
H.checkEqual("preview broadcasts nothing", #H.sent, 0)

reset()
H.runSlash("show")
H.runSlash("list")
H.advance(600)
H.checkEqual("browsing presets broadcasts nothing", #H.sent, 0)

--------------------------------------------------------------------------------
H.section("A fresh preset previews rather than sends")
--------------------------------------------------------------------------------

reset()
local fresh = REH.CreateDefaultPreset("Fresh")
DB:ValidatePreset(fresh)
H.checkEqual("a fresh preset targets PREVIEW", fresh.channel.type, "PREVIEW")

announceFully(fresh, "Fresh")
H.checkEqual("announcing it sends nothing", #H.sent, 0)
H.check("and explains how to pick a channel",
	H.outputText():find("preview only", 1, true) ~= nil, H.outputText())

--------------------------------------------------------------------------------
H.section("Availability is enforced before sending")
--------------------------------------------------------------------------------

local function availabilityOf(kind, target)
	return Announcer:CheckAvailability({ type = kind, target = target or "" })
end

reset()
H.check("say is always available", availabilityOf("SAY"))
H.check("yell is always available", availabilityOf("YELL"))
H.check("emote is always available", availabilityOf("EMOTE"))

H.check("party is refused when not grouped", availabilityOf("PARTY") == false)
H.group.inGroup = true
H.check("party is allowed once grouped", availabilityOf("PARTY"))

H.check("raid is refused when not in a raid", availabilityOf("RAID") == false)
H.group.inRaid = true
H.check("raid is allowed in a raid", availabilityOf("RAID"))

H.check("raid warning is refused without lead or assist",
	availabilityOf("RAID_WARNING") == false)
H.group.isAssistant = true
H.check("raid warning is allowed with assist", availabilityOf("RAID_WARNING"))
H.group.isAssistant = false
H.group.isLeader = true
H.check("raid warning is allowed with lead", availabilityOf("RAID_WARNING"))

H.check("guild is refused when guildless", availabilityOf("GUILD") == false)
H.check("officer is refused when guildless", availabilityOf("OFFICER") == false)
H.group.inGuild = true
H.check("guild is allowed once in a guild", availabilityOf("GUILD"))

H.check("instance chat is refused outside an instance group",
	availabilityOf("INSTANCE_CHAT") == false)
H.group.inInstance = true
H.check("instance chat is allowed inside one", availabilityOf("INSTANCE_CHAT"))

H.check("a custom channel with no name is refused", availabilityOf("CHANNEL") == false)
H.check("a channel you have not joined is refused",
	availabilityOf("CHANNEL", "MoonGuardRP") == false)
H.group.channels["MoonGuardRP"] = 5
H.check("a joined channel is allowed", availabilityOf("CHANNEL", "MoonGuardRP"))

H.check("a whisper with no target is refused", availabilityOf("WHISPER") == false)
H.check("a whisper with a target is allowed", availabilityOf("WHISPER", "Bob"))

H.resetGroup()
local _, reason = availabilityOf("RAID")
H.check("refusals explain themselves in plain words",
	type(reason) == "string" and #reason > 0, tostring(reason))

--------------------------------------------------------------------------------
H.section("Refusing to send")
--------------------------------------------------------------------------------

reset()
local partyPreset = REH.CreateDefaultPreset("Party Rules")
partyPreset.channel.type = "PARTY"
DB:ValidatePreset(partyPreset)

announceFully(partyPreset, "Party Rules")
H.checkEqual("an unavailable target sends nothing", #H.sent, 0)
H.check("and says why", H.outputText():find("not in a party", 1, true) ~= nil, H.outputText())

--------------------------------------------------------------------------------
H.section("A full announcement")
--------------------------------------------------------------------------------

reset()
H.group.inGroup = true
announceFully(partyPreset, "Party Rules")

local expected = REH.Formatter:BuildMessages(partyPreset)
H.checkEqual("every message was sent", #H.sent, #expected)
H.check("more than one message", #H.sent > 1)

local matches = true
for index, entry in ipairs(H.sent) do
	if entry.message ~= expected[index] then
		matches = false
	end
	if entry.chatType ~= "PARTY" then
		matches = false
	end
end
H.check("the messages match the preview exactly, in order and channel", matches)
H.check("the rules reached chat",
	table.concat(H.sentMessages(), "\n"):find("/roll 100", 1, true) ~= nil)
H.check("the host is told what is happening",
	H.outputText():find("Announcing", 1, true) ~= nil, H.outputText())
H.check("and told when it finished",
	H.outputText():find("messages sent", 1, true) ~= nil, H.outputText())

--------------------------------------------------------------------------------
H.section("Pacing")
--------------------------------------------------------------------------------

reset()
H.group.inGroup = true
DB:GetSettings().sendDelay = 0.7

Announcer:Announce(partyPreset, "Party Rules")
H.checkEqual("the first message goes out immediately", #H.sent, 1)
H.check("and the rest are queued, not burst", Announcer:IsSending())

H.advance(0.5)
H.checkEqual("nothing more before the delay elapses", #H.sent, 1)

H.advance(0.3)
H.checkEqual("the next goes after the delay", #H.sent, 2)

H.advance(600)
H.check("the queue finishes", Announcer:IsSending() == false)
H.checkEqual("no timers are left running", H.pendingTimers(), 0)

reset()
H.group.inGroup = true
DB:GetSettings().sendDelay = 2.0
Announcer:Announce(partyPreset, "Party Rules")
H.advance(1.5)
H.checkEqual("a longer delay is honoured", #H.sent, 1)
H.advance(1.0)
H.checkEqual("and then sends", #H.sent, 2)
H.advance(600)
DB:GetSettings().sendDelay = 0.7

--------------------------------------------------------------------------------
H.section("Cancelling")
--------------------------------------------------------------------------------

reset()
H.group.inGroup = true
Announcer:Announce(partyPreset, "Party Rules")
H.advance(1.5)
local sentSoFar = #H.sent
H.check("a few messages have gone out", sentSoFar >= 2)

H.clearOutput()
H.runSlash("cancel")
H.check("cancelling stops the queue", Announcer:IsSending() == false)
H.check("and reports how far it got",
	H.outputText():find("cancelled after", 1, true) ~= nil
		or H.outputText():find("Announcement cancelled", 1, true) ~= nil, H.outputText())

H.advance(600)
H.checkEqual("no further messages are sent after cancelling", #H.sent, sentSoFar)
H.checkEqual("and no timers keep firing", H.pendingTimers(), 0)

reset()
H.clearOutput()
H.runSlash("cancel")
H.check("cancelling when idle is harmless",
	H.outputText():find("Nothing is being announced", 1, true) ~= nil, H.outputText())

--------------------------------------------------------------------------------
H.section("Overlapping announcements")
--------------------------------------------------------------------------------

reset()
H.group.inGroup = true
Announcer:Announce(partyPreset, "Party Rules")
H.advance(1.0)
local before = #H.sent

H.clearOutput()
Announcer:Announce(partyPreset, "Party Rules")
H.check("a second announcement is refused while one runs",
	H.outputText():find("Already announcing", 1, true) ~= nil, H.outputText())

H.advance(600)
H.checkEqual("only one announcement's worth was sent", #H.sent, #expected)
H.check("the first one still completed", before < #H.sent)

--------------------------------------------------------------------------------
H.section("A blocked send stops cleanly")
--------------------------------------------------------------------------------

-- Blizzard periodically tightens what addons may send and when. If the client
-- refuses, the host must be told which message failed rather than left with
-- half a rule set in the channel and a Lua error on screen.
reset()
H.group.inGroup = true
Announcer:Announce(partyPreset, "Party Rules")
H.advance(1.0)
local deliveredBeforeBlock = #H.sent

H.sendError = "You can't do that right now."
H.clearOutput()
H.advance(600)

H.check("the queue stopped", Announcer:IsSending() == false)
H.checkEqual("no messages were sent after the block", #H.sent, deliveredBeforeBlock)
H.check("the host is told which message failed",
	H.outputText():find("blocked message", 1, true) ~= nil, H.outputText())
H.check("and given the client's reason",
	H.outputText():find("can't do that right now", 1, true) ~= nil, H.outputText())
H.checkEqual("no timers are left behind", H.pendingTimers(), 0)

--------------------------------------------------------------------------------
H.section("Custom channels and whispers")
--------------------------------------------------------------------------------

reset()
H.group.channels["MoonGuardRP"] = 7
local channelPreset = REH.CreateDefaultPreset("Channel Rules")
channelPreset.channel.type = "CHANNEL"
channelPreset.channel.target = "MoonGuardRP"
DB:ValidatePreset(channelPreset)

announceFully(channelPreset, "Channel Rules")
H.check("a custom channel receives the rules", #H.sent > 0)
H.checkEqual("sent as CHANNEL", H.sent[1].chatType, "CHANNEL")
H.checkEqual("addressed by channel index, not name", H.sent[1].target, 7)

reset()
local whisperPreset = REH.CreateDefaultPreset("Whisper Rules")
whisperPreset.channel.type = "WHISPER"
whisperPreset.channel.target = "Bob"
DB:ValidatePreset(whisperPreset)

announceFully(whisperPreset, "Whisper Rules")
H.check("a whisper is delivered", #H.sent > 0)
H.checkEqual("sent as WHISPER", H.sent[1].chatType, "WHISPER")
H.checkEqual("addressed to the named player", H.sent[1].target, "Bob")

--------------------------------------------------------------------------------
H.section("Choosing a channel")
--------------------------------------------------------------------------------

reset()
local active, activeName = DB:GetActivePreset()

local out = H.runSlash("channel say")
H.checkEqual("/reh channel say sets say", active.channel.type, "SAY")
H.check("and confirms it", out:find("/say", 1, true) ~= nil, out)

H.runSlash("channel rw")
H.checkEqual("short aliases work", active.channel.type, "RAID_WARNING")

out = H.runSlash("channel channel MoonGuardRP")
H.checkEqual("a custom channel is stored", active.channel.type, "CHANNEL")
H.checkEqual("with its name", active.channel.target, "MoonGuardRP")

out = H.runSlash("channel channel")
H.check("a custom channel with no name is refused",
	out:find("Which channel", 1, true) ~= nil, out)
H.checkEqual("and the old setting is untouched", active.channel.target, "MoonGuardRP")

out = H.runSlash("channel whisper")
H.check("a whisper with no name is refused", out:find("Whisper whom", 1, true) ~= nil, out)

out = H.runSlash("channel nonsense")
H.check("an unknown channel is refused", out:find("is not a channel", 1, true) ~= nil, out)

-- Hosts set up "raid warning" before the raid exists, so this is allowed with
-- a warning rather than blocked.
reset()
out = H.runSlash("channel warning")
H.checkEqual("an unavailable channel can still be selected",
	active.channel.type, "RAID_WARNING")
H.check("but the host is warned now rather than surprised later",
	out:find("Not available right now", 1, true) ~= nil, out)

out = H.runSlash("channel")
H.check("/reh channel with no argument reports the current target",
	out:find("announces to", 1, true) ~= nil, out)

H.runSlash("channel preview")
H.checkEqual("preview can be selected again", active.channel.type, "PREVIEW")

--------------------------------------------------------------------------------
H.section("Settings")
--------------------------------------------------------------------------------

reset()
DB:GetSettings().sendDelay = 0.001
DB:ValidateSettings(DB:GetSettings())
H.check("an absurdly short send delay is clamped up", DB:GetSettings().sendDelay >= 0.3)

DB:GetSettings().sendDelay = 500
DB:ValidateSettings(DB:GetSettings())
H.check("an absurdly long one is clamped down", DB:GetSettings().sendDelay <= 5.0)

DB:GetSettings().sendDelay = "not a number"
DB:ValidateSettings(DB:GetSettings())
H.checkEqual("a non-numeric delay falls back to the default",
	DB:GetSettings().sendDelay, 0.7)

H.checkNoLeakedGlobals(H.ALLOWED_GLOBALS)

H.finish()
