local ADDON_NAME, REH = ...

local L = REH.L
local RollWatcher = {}
REH.RollWatcher = RollWatcher

-- Watches /roll results in the room and calls each one a success or a failure
-- against the active preset.
--
-- Three deliberate positions:
--
--   It adjudicates the ordinary /roll everyone already uses, rather than
--   replacing it with a custom dice system. Attendees need nothing installed.
--
--   It starts disarmed, every time. The watcher is never running because it was
--   running last week; the host arms it when the event starts.
--
--   When it ignores a roll, it says so. Silently dropping a participant's roll
--   is worse than adjudicating a stranger's, so out-of-group rolls are counted
--   and surfaced rather than discarded quietly.

local MODES = { off = true, ["local"] = true, announce = true }

-- Announced verdicts are capped. A twenty-person free-for-all can produce a
-- burst of rolls, and flooding the channel with verdicts is worse than the host
-- reading a few out.
local MAX_VERDICTS_PER_MINUTE = 20
local VERDICT_SEND_DELAY = 0.5
local IGNORED_HINT_AFTER = 5

RollWatcher.mode = "off"

local roster = {}
local rosterCount = 0
local muted = {}
local log = { entries = {}, tallies = {} }
local ignoredOutsideGroup = 0
local hintShown = false
local verdictTimes = {}
local verdictQueue = {}
local verdictSending = false
local capWarned = false
local eventFrame

--------------------------------------------------------------------------------
-- Parsing roll results
--------------------------------------------------------------------------------

-- Roll results arrive as system messages formatted from RANDOM_ROLL_RESULT.
-- The pattern is built from the client's own string rather than from English
-- text, so the watcher works for a German or French host without a translation.
-- Locales may also reorder the arguments with positional specifiers ("%1$s"),
-- which is why the argument order is tracked rather than assumed.

local rollPattern, rollArgumentOrder

local function EscapeLiteral(text)
	return (text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

function RollWatcher:BuildRollPattern(template)
	template = template or (RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)")

	local parts, order = {}, {}
	local search = 1

	while true do
		local first, last, digits, kind = template:find("%%(%d*)%$?([sd])", search)
		if not first then
			break
		end

		parts[#parts + 1] = EscapeLiteral(template:sub(search, first - 1))
		parts[#parts + 1] = (kind == "s") and "(.+)" or "(%d+)"
		order[#order + 1] = tonumber(digits) or (#order + 1)

		search = last + 1
	end

	parts[#parts + 1] = EscapeLiteral(template:sub(search))

	return "^" .. table.concat(parts) .. "$", order
end

function RollWatcher:EnsurePattern()
	if not rollPattern then
		rollPattern, rollArgumentOrder = self:BuildRollPattern()
	end
	return rollPattern, rollArgumentOrder
end

--- Pull name, roll, min and max out of a system message.
--- Returns nil when the message is not a roll result.
function RollWatcher:ParseRoll(message)
	local pattern, order = self:EnsurePattern()
	if not message then
		return nil
	end

	local captures = { message:match(pattern) }
	if #captures ~= #order then
		return nil
	end

	-- Map each capture onto the argument it represents, honouring positional
	-- specifiers where the locale uses them.
	local values = {}
	for index, capture in ipairs(captures) do
		values[order[index] or index] = capture
	end

	local name = values[1]
	local roll, minRoll, maxRoll = tonumber(values[2]), tonumber(values[3]), tonumber(values[4])

	if not name or not roll or not minRoll or not maxRoll then
		return nil
	end

	return REH.Trim(name), roll, minRoll, maxRoll
end

--------------------------------------------------------------------------------
-- Names
--------------------------------------------------------------------------------

-- System messages render cross-realm players as "Name-Realm" and same-realm
-- players as bare "Name", while the roster returns the two halves separately.
-- Comparing those directly silently drops every cross-realm participant, and at
-- a large open-world event those are the majority. Everything is normalised to
-- a canonical "Name-Realm" before comparison.

function RollWatcher:HomeRealm()
	local realm = GetNormalizedRealmName and GetNormalizedRealmName()
	if realm and realm ~= "" then
		return (realm:gsub("%s+", ""))
	end
	return "?"
end

function RollWatcher:NormalizeName(name, realm)
	if not name or name == "" then
		return nil
	end

	name = REH.Trim(name)

	local base, suffix = name:match("^(.-)%-(.+)$")
	if base and base ~= "" then
		return base .. "-" .. (suffix:gsub("%s+", ""))
	end

	if realm and realm ~= "" then
		return name .. "-" .. (realm:gsub("%s+", ""))
	end

	return name .. "-" .. self:HomeRealm()
end

--- The player-facing form: bare name for same-realm, Name-Realm otherwise.
function RollWatcher:DisplayName(fullName)
	local base, realm = tostring(fullName):match("^(.-)%-(.+)$")
	if base and realm == self:HomeRealm() then
		return base
	end
	return fullName
end

--------------------------------------------------------------------------------
-- Roster
--------------------------------------------------------------------------------

--- Rebuild the party or raid roster. Called on GROUP_ROSTER_UPDATE rather than
--- per roll, so a busy event is not re-scanning the group for every dice throw.
function RollWatcher:RebuildRoster()
	roster = {}
	rosterCount = 0

	local function add(name, realm, subgroup)
		local full = self:NormalizeName(name, realm)
		if full and not roster[full] then
			roster[full] = { subgroup = subgroup or 1 }
			rosterCount = rosterCount + 1
		end
	end

	if IsInRaid() then
		for index = 1, GetNumGroupMembers() do
			local rosterName, _, subgroup = GetRaidRosterInfo(index)
			if rosterName then
				-- GetRaidRosterInfo already appends the realm for cross-realm
				-- members, so NormalizeName sees a suffixed name here.
				add(rosterName, nil, subgroup)
			else
				local name, realm = UnitName("raid" .. index)
				add(name, realm, subgroup)
			end
		end

	elseif IsInGroup() then
		-- Party unit tokens exclude the player, so add yourself explicitly.
		add(UnitName("player"))
		for index = 1, GetNumGroupMembers() - 1 do
			local name, realm = UnitName("party" .. index)
			add(name, realm)
		end

	else
		add(UnitName("player"))
	end

	return rosterCount
end

function RollWatcher:GetRoster()
	return roster, rosterCount
end

--------------------------------------------------------------------------------
-- Filtering
--------------------------------------------------------------------------------

--- Should this roll be adjudicated? Returns true, or false plus a short reason
--- code ("range", "muted", "group", "subgroup", "roster").
function RollWatcher:ShouldAdjudicate(preset, fullName, minRoll, maxRoll)
	local filter = preset.rollFilter

	if muted[fullName] then
		return false, "muted"
	end

	-- Someone rolling /roll 20 for loot is not part of your duel.
	if filter.matchRangeOnly then
		if minRoll ~= 1 or maxRoll ~= preset.rolls.dieMax then
			return false, "range"
		end
	end

	local mode = filter.mode

	if mode == "everyone" then
		return true
	end

	if mode == "roster" then
		for _, name in ipairs(filter.roster) do
			if self:NormalizeName(name) == fullName then
				return true
			end
		end
		return false, "roster"
	end

	local entry = roster[fullName]
	if not entry then
		return false, "group"
	end

	if mode == "subgroup" then
		-- An empty subgroup selection means "the whole raid" rather than
		-- "nobody", which is the reading that cannot silently exclude someone.
		if #filter.subgroups == 0 then
			return true
		end

		for _, subgroup in ipairs(filter.subgroups) do
			if entry.subgroup == subgroup then
				return true
			end
		end

		return false, "subgroup"
	end

	return true
end

--------------------------------------------------------------------------------
-- Adjudication
--------------------------------------------------------------------------------

--- "critsuccess", "success", "fail" or "critfail".
function RollWatcher:Judge(preset, roll)
	local rolls = preset.rolls

	if rolls.useCritical then
		if roll >= rolls.critSuccessAt then
			return "critsuccess"
		end
		if roll <= rolls.critFailAt then
			return "critfail"
		end
	end

	if roll >= rolls.successThreshold then
		return "success"
	end

	return "fail"
end

function RollWatcher:VerdictText(preset, verdict)
	local rolls = preset.rolls

	if verdict == "critsuccess" then
		return rolls.successText .. " (critical)"
	elseif verdict == "critfail" then
		return rolls.failText .. " (critical)"
	elseif verdict == "success" then
		return rolls.successText
	end

	return rolls.failText
end

local VERDICT_COLORS = {
	critsuccess = "|cff40ff40",
	success = "|cff80ff80",
	fail = "|cffff8080",
	critfail = "|cffff4040",
}

function RollWatcher:FormatVerdict(preset, name, roll, verdict, colored)
	local text = ("%s rolled %d -> %s"):format(
		self:DisplayName(name), roll, self:VerdictText(preset, verdict))

	if colored then
		return (VERDICT_COLORS[verdict] or "|cffffffff") .. text .. "|r"
	end

	return text
end

--------------------------------------------------------------------------------
-- Announcing verdicts
--------------------------------------------------------------------------------

local function PruneVerdictTimes(now)
	local kept = {}
	for _, time in ipairs(verdictTimes) do
		if now - time < 60 then
			kept[#kept + 1] = time
		end
	end
	verdictTimes = kept
end

local function PumpVerdictQueue()
	local message = table.remove(verdictQueue, 1)
	if not message then
		verdictSending = false
		return
	end

	verdictSending = true
	pcall(SendChatMessage, REH.StripChatEscapes(message.text),
		message.chatType, nil, message.target)

	C_Timer.After(VERDICT_SEND_DELAY, PumpVerdictQueue)
end

--- Queue a verdict for the channel, unless the rate cap says otherwise.
--- Returns true if it was queued.
function RollWatcher:QueueVerdict(preset, text)
	local channel = preset.channel

	if channel.type == "PREVIEW" then
		return false
	end

	if not REH.Announcer:CheckAvailability(channel) then
		return false
	end

	local now = (GetTime and GetTime()) or 0
	PruneVerdictTimes(now)

	if #verdictTimes >= MAX_VERDICTS_PER_MINUTE then
		if not capWarned then
			capWarned = true
			REH:PrintWarning(L["Too many rolls to announce (%d a minute). Verdicts are showing here only."]
				:format(MAX_VERDICTS_PER_MINUTE))
		end
		return false
	end

	verdictTimes[#verdictTimes + 1] = now

	local target = channel.target
	if channel.type == "CHANNEL" then
		target = GetChannelName(channel.target)
	end

	verdictQueue[#verdictQueue + 1] = {
		text = text, chatType = channel.type, target = target,
	}

	if not verdictSending then
		PumpVerdictQueue()
	end

	return true
end

--------------------------------------------------------------------------------
-- The log
--------------------------------------------------------------------------------

function RollWatcher:Record(name, roll, verdict)
	local entry = {
		name = name,
		roll = roll,
		verdict = verdict,
		time = (date and date("%H:%M:%S")) or "",
	}

	log.entries[#log.entries + 1] = entry

	local tally = log.tallies[name]
	if not tally then
		tally = { total = 0, successes = 0, failures = 0, criticals = 0 }
		log.tallies[name] = tally
	end

	tally.total = tally.total + 1
	if verdict == "success" or verdict == "critsuccess" then
		tally.successes = tally.successes + 1
	else
		tally.failures = tally.failures + 1
	end
	if verdict == "critsuccess" or verdict == "critfail" then
		tally.criticals = tally.criticals + 1
	end

	return entry
end

function RollWatcher:GetLog()
	return log.entries, log.tallies
end

function RollWatcher:ClearLog()
	log.entries = {}
	log.tallies = {}
	ignoredOutsideGroup = 0
	hintShown = false
	capWarned = false
end

function RollWatcher:Mute(name)
	local full = self:NormalizeName(name)
	if not full then
		return false
	end
	muted[full] = true
	return true, full
end

function RollWatcher:Unmute(name)
	local full = self:NormalizeName(name)
	if not full then
		return false
	end
	muted[full] = nil
	return true, full
end

function RollWatcher:IsMuted(name)
	return muted[self:NormalizeName(name) or ""] == true
end

--------------------------------------------------------------------------------
-- Handling a roll
--------------------------------------------------------------------------------

--- Process one system message. Returns the entry when it was adjudicated.
function RollWatcher:HandleSystemMessage(message)
	if self.mode == "off" then
		return nil
	end

	local name, roll, minRoll, maxRoll = self:ParseRoll(message)
	if not name then
		return nil
	end

	local preset = REH.Database:GetActivePreset()
	local fullName = self:NormalizeName(name)

	local allowed, reason = self:ShouldAdjudicate(preset, fullName, minRoll, maxRoll)
	if not allowed then
		if reason == "group" or reason == "roster" or reason == "subgroup" then
			ignoredOutsideGroup = ignoredOutsideGroup + 1

			-- Never silent: a participant whose roll is being dropped needs to
			-- become visible to the host, once, with the fix to hand.
			if ignoredOutsideGroup >= IGNORED_HINT_AFTER and not hintShown then
				hintShown = true
				REH:PrintWarning(L["%d rolls ignored from outside your group. Use /reh filter everyone to include them."]
					:format(ignoredOutsideGroup))
			end
		end
		return nil
	end

	local verdict = self:Judge(preset, roll)
	local entry = self:Record(fullName, roll, verdict)

	REH:Print(self:FormatVerdict(preset, fullName, roll, verdict, true))

	if self.mode == "announce" then
		self:QueueVerdict(preset, self:FormatVerdict(preset, fullName, roll, verdict, false))
	end

	return entry
end

--------------------------------------------------------------------------------
-- Arming
--------------------------------------------------------------------------------

function RollWatcher:GetMode()
	return self.mode
end

function RollWatcher:SetMode(mode)
	if not MODES[mode] then
		return false, L["Watcher mode must be off, local or announce."]
	end

	self.mode = mode

	if mode ~= "off" then
		self:RebuildRoster()
	end

	return true
end

function RollWatcher:IsWatching()
	return self.mode ~= "off"
end

function RollWatcher:GetIgnoredCount()
	return ignoredOutsideGroup
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function RollWatcher:Initialize()
	if eventFrame then
		return eventFrame
	end

	eventFrame = CreateFrame("Frame")
	eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
	eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

	eventFrame:SetScript("OnEvent", function(_, event, ...)
		if event == "CHAT_MSG_SYSTEM" then
			RollWatcher:HandleSystemMessage(...)
		elseif event == "GROUP_ROSTER_UPDATE" then
			if RollWatcher:IsWatching() then
				RollWatcher:RebuildRoster()
			end
		end
	end)

	-- Deliberately not restored from saved variables. The watcher starts off on
	-- every login and reload, so the addon never wakes up talking.
	self.mode = "off"

	return eventFrame
end
