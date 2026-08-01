local ADDON_NAME, REH = ...

local L = REH.L
local Announcer = {}
REH.Announcer = Announcer

-- Sends a preset's rules to a chat channel, paced so the client does not drop
-- messages and the channel is not flooded in one burst.
--
-- This is the first part of the addon that speaks to other players, so it is
-- deliberately conservative: it refuses rather than guesses when the target is
-- unavailable, it can always be cancelled, and a send that the client blocks
-- stops the queue and says so instead of silently dropping the rest of the
-- rules mid-announcement.

local MIN_SEND_DELAY = 0.3
local MAX_SEND_DELAY = 5.0

local queue = {
	active = false,
	messages = nil,
	index = 0,
	chatType = nil,
	target = nil,
	presetName = nil,
	delay = 0.7,
}

--------------------------------------------------------------------------------
-- Target description and availability
--------------------------------------------------------------------------------

local function DescribeChannel(channel)
	if channel.type == "CHANNEL" then
		return ("channel '%s'"):format(channel.target)
	end
	if channel.type == "WHISPER" then
		return ("a whisper to %s"):format(channel.target)
	end
	return REH.DISPLAY.channel[channel.type] or channel.type
end

--- Method form for callers that use colon syntax.
function Announcer:DescribeChannel(channel)
	return DescribeChannel(channel)
end

--- Can this preset announce right now? Returns true, or false plus a reason
--- written for the host rather than for a log.
function Announcer:CheckAvailability(channel)
	local kind = channel.type

	if kind == "PREVIEW" or kind == "SAY" or kind == "YELL" or kind == "EMOTE" then
		return true
	end

	if kind == "PARTY" then
		if not IsInGroup() then
			return false, L["You are not in a party."]
		end
		return true
	end

	if kind == "RAID" or kind == "RAID_WARNING" then
		if not IsInRaid() then
			return false, L["You are not in a raid."]
		end
		if kind == "RAID_WARNING"
			and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
			return false, L["Raid warnings need raid lead or assist."]
		end
		return true
	end

	if kind == "INSTANCE_CHAT" then
		if not IsInInstance() then
			return false, L["You are not in an instance group."]
		end
		return true
	end

	if kind == "GUILD" or kind == "OFFICER" then
		if not IsInGuild() then
			return false, L["You are not in a guild."]
		end
		return true
	end

	if kind == "CHANNEL" then
		if channel.target == "" then
			return false, L["No channel name set. Use /reh channel channel <name>."]
		end
		if (GetChannelName(channel.target) or 0) == 0 then
			return false, L["You have not joined the channel '%s'."]:format(channel.target)
		end
		return true
	end

	if kind == "WHISPER" then
		if channel.target == "" then
			return false, L["No whisper target set. Use /reh channel whisper <name>."]
		end
		return true
	end

	return false, L["'%s' is not a channel this addon can send to."]:format(tostring(kind))
end

--------------------------------------------------------------------------------
-- Queue
--------------------------------------------------------------------------------

function Announcer:IsSending()
	return queue.active
end

function Announcer:Progress()
	if not queue.active then
		return 0, 0
	end
	return queue.index, #queue.messages
end

local function ResetQueue()
	queue.active = false
	queue.messages = nil
	queue.index = 0
	queue.chatType = nil
	queue.target = nil
	queue.presetName = nil
end

function Announcer:Cancel()
	if not queue.active then
		return false
	end

	local sent, total = queue.index, #queue.messages
	ResetQueue()
	REH:PrintWarning(L["Announcement cancelled by you after %d of %d messages."]
		:format(sent, total))
	return true
end

--- Stop because the client refused a send. The host is told which message
--- failed, because a half-announced rule set is worse than an obvious error.
local function Abort(failureIndex, total, err)
	ResetQueue()
	REH:PrintError(L["The client blocked message %d of %d, so the announcement stopped."]
		:format(failureIndex, total))
	REH:PrintError(L["Reason: %s"]:format(tostring(err)))
end

function Announcer:SendNext()
	if not queue.active then
		return
	end

	queue.index = queue.index + 1
	local message = queue.messages[queue.index]

	if not message then
		local total = queue.index - 1
		local presetName = queue.presetName
		ResetQueue()
		REH:Print(L["Announced '%s': %d messages sent."]:format(presetName, total))
		return
	end

	-- SendChatMessage can raise rather than return a failure -- a channel left
	-- mid-announcement, a restriction on the client. Catch it so the addon
	-- reports a clear stop instead of throwing a Lua error at the host.
	-- Belt and braces: the formatter already strips these, but a message that
	-- reaches the client with a colour escape in it is dropped silently, which
	-- is the hardest kind of failure for a host to diagnose mid-event.
	message = REH.StripChatEscapes(message)

	-- So that a blocked action can be attributed to a specific message rather
	-- than to "something, at some point during the evening".
	REH.Diagnostics:SetContext(("sending message %d of %d to %s")
		:format(queue.index, #queue.messages, tostring(queue.chatType)))

	local ok, err = pcall(SendChatMessage, message, queue.chatType, nil, queue.target)

	REH.Diagnostics:ClearContext()

	if not ok then
		Abort(queue.index, #queue.messages, err)
		return
	end

	if queue.index >= #queue.messages then
		local total = queue.index
		local presetName = queue.presetName
		ResetQueue()
		REH:Print(L["Announced '%s': %d messages sent."]:format(presetName, total))
		return
	end

	-- In burst mode the next message goes out in this same call stack, keeping
	-- whatever hardware event started the announcement behind every send. In
	-- paced mode a timer carries it, which is gentler on the client but has no
	-- hardware event behind it.
	if queue.mode == "burst" then
		Announcer:SendNext()
	else
		C_Timer.After(queue.delay, function()
			Announcer:SendNext()
		end)
	end
end

--------------------------------------------------------------------------------
-- Announcing
--------------------------------------------------------------------------------

function Announcer:Announce(preset, presetName, overrides)
	if queue.active then
		REH:PrintError(L["Already announcing. Use /reh cancel first."])
		return false
	end

	local channel = preset.channel

	-- A preset set to preview prints locally and sends nothing. This is the
	-- default on a fresh preset, so the first press of Announce can never
	-- surprise a channel.
	if channel.type == "PREVIEW" then
		REH.Formatter:Preview(preset, presetName, overrides)
		REH:Print(L["This preset is set to preview only. Use /reh channel <type> to choose where to announce."])
		return true
	end

	local available, reason = self:CheckAvailability(channel)
	if not available then
		REH:PrintError(reason)
		return false
	end

	local messages = REH.Formatter:BuildMessages(preset, overrides)
	if #messages == 0 then
		REH:PrintError(L["'%s' has no enabled rules to announce."]:format(presetName))
		return false
	end

	-- SendChatMessage takes the channel's index, not its name.
	local target = channel.target
	if channel.type == "CHANNEL" then
		target = GetChannelName(channel.target)
	end

	local settings = REH.Database:GetSettings()

	queue.active = true
	queue.messages = messages
	queue.index = 0
	queue.chatType = channel.type
	queue.target = target
	queue.presetName = presetName
	queue.delay = settings.sendDelay
	queue.mode = settings.sendMode

	if queue.mode == "burst" then
		REH:Print(L["Announcing '%s' to %s: %d messages, all at once."]
			:format(presetName, DescribeChannel(channel), #messages))
	else
		REH:Print(L["Announcing '%s' to %s: %d messages, about %d seconds. /reh cancel to stop."]
			:format(presetName, DescribeChannel(channel), #messages,
				math.ceil(#messages * queue.delay)))
	end

	self:SendNext()
	return true
end

--------------------------------------------------------------------------------
-- Channel selection
--------------------------------------------------------------------------------

-- What a host might reasonably type, mapped to the stored value.
local CHANNEL_ALIASES = {
	preview = "PREVIEW", none = "PREVIEW", off = "PREVIEW",
	say = "SAY", s = "SAY",
	yell = "YELL", y = "YELL",
	emote = "EMOTE", e = "EMOTE", me = "EMOTE",
	party = "PARTY", p = "PARTY",
	raid = "RAID", r = "RAID",
	warning = "RAID_WARNING", raidwarning = "RAID_WARNING", rw = "RAID_WARNING",
	instance = "INSTANCE_CHAT", instancechat = "INSTANCE_CHAT",
	guild = "GUILD", g = "GUILD",
	officer = "OFFICER", o = "OFFICER",
	channel = "CHANNEL", chan = "CHANNEL", c = "CHANNEL",
	whisper = "WHISPER", w = "WHISPER", tell = "WHISPER",
}

Announcer.CHANNEL_ALIASES = CHANNEL_ALIASES

--- Set a preset's announce target. Returns true, or false plus a reason.
---
--- An unavailable target is still accepted, with a warning: a host may well set
--- up "raid warning" before forming the raid. Availability is enforced at the
--- moment of announcing, not here.
function Announcer:SetChannel(preset, word, target)
	-- Accept both what a host types ("rw") and the stored value the UI passes
	-- back ("RAID_WARNING").
	local kind = CHANNEL_ALIASES[tostring(word):lower()]
	if not kind and REH.IsValidEnum(REH.CHANNEL_TYPES, tostring(word):upper()) then
		kind = tostring(word):upper()
	end

	if not kind then
		return false, L["'%s' is not a channel. Try: preview, say, yell, emote, party, raid, warning, instance, guild, officer, channel <name>, whisper <name>."]
			:format(tostring(word))
	end

	target = REH.CleanString(target, 64)

	if kind == "CHANNEL" and target == "" then
		return false, L["Which channel? Use /reh channel channel <name>."]
	end
	if kind == "WHISPER" and target == "" then
		return false, L["Whisper whom? Use /reh channel whisper <name>."]
	end
	if kind ~= "CHANNEL" and kind ~= "WHISPER" then
		target = ""
	end

	preset.channel.type = kind
	preset.channel.target = target

	local available, reason = self:CheckAvailability(preset.channel)
	return true, nil, (not available) and reason or nil
end
