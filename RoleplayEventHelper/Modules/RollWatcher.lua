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
-- Rolls are grouped into rounds. A duel or a brawl runs in rounds, and a host
-- reviewing "who hit what in round three" should not have to read one long
-- undivided list. Rounds are session state, like the log itself: they are not
-- saved, because a new evening is a new event.
local rounds = { { entries = {}, tallies = {} } }
local currentRound = 1
local ignoredOutsideGroup = 0
local ignoredForRange = 0
local hintShown = false
local rangeHintShown = false
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

	-- A wounded character rolling a reduced die is the usual reason to roll on
	-- something smaller than the event's, so "atMost" accepts those while still
	-- ignoring a roll on a bigger die than the rules use.
	local rangeMode = filter.rangeMode

	if rangeMode == "exact" then
		if minRoll ~= 1 or maxRoll ~= preset.rolls.dieMax then
			return false, "range"
		end
	elseif rangeMode ~= "any" then
		if minRoll ~= 1 or maxRoll > preset.rolls.dieMax then
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

--- The numbers a roll is judged against, for the die it was actually rolled on.
---
--- With scaling off these are simply the preset's own numbers, so a wounded
--- character on a smaller die still needs the event's threshold and their
--- reduced die is the penalty. With it on the threshold moves in proportion,
--- keeping their odds the same and making the smaller die a matter of flavour.
--- Both are defensible ways to run an event, which is why it is a choice.
function RollWatcher:ThresholdsFor(preset, maxRoll)
	local rolls = preset.rolls

	if not rolls.scaleToDie or not maxRoll or maxRoll == rolls.dieMax then
		return rolls.successThreshold, rolls.critSuccessAt, rolls.critFailAt
	end

	local scale = maxRoll / rolls.dieMax

	local function up(value)
		return math.min(maxRoll, math.max(1, math.ceil(value * scale)))
	end

	-- The critical-failure band rounds down and the success bands round up, so
	-- scaling never widens what counts as a critical failure.
	local critFail = math.min(maxRoll, math.max(1, math.floor(rolls.critFailAt * scale)))

	return up(rolls.successThreshold), up(rolls.critSuccessAt), critFail
end

--- "critsuccess", "success", "fail" or "critfail".
function RollWatcher:Judge(preset, roll, maxRoll)
	local success, critSuccess, critFail = self:ThresholdsFor(preset, maxRoll)

	if preset.rolls.useCritical then
		if roll >= critSuccess then
			return "critsuccess"
		end
		if roll <= critFail then
			return "critfail"
		end
	end

	if roll >= success then
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

function RollWatcher:FormatVerdict(preset, name, roll, verdict, colored, maxRoll)
	-- When somebody rolls on a smaller die than the event's, the die matters:
	-- "rolled 12" reads as a near miss until you know it was out of 15.
	local die = ""
	if maxRoll and maxRoll ~= preset.rolls.dieMax then
		if preset.rolls.scaleToDie then
			-- With scaling on the number they needed is not the one in the
			-- rules, so it is worth showing.
			die = (" (1-%d, %d+)"):format(maxRoll, (self:ThresholdsFor(preset, maxRoll)))
		else
			die = (" (1-%d)"):format(maxRoll)
		end
	end

	local text = ("%s rolled %d%s -> %s"):format(
		self:DisplayName(name), roll, die, self:VerdictText(preset, verdict))

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

--- Queue one line for the channel, unless the rate cap says otherwise.
--- Returns true if it was queued.
---
--- Verdicts and loot results share the queue and the cap deliberately: they go
--- to the same channel through the same send delay, and what a busy room needs
--- capping is the total the addon says, not each kind separately.
function RollWatcher:QueueLine(preset, text)
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

function RollWatcher:QueueVerdict(preset, text)
	return self:QueueLine(preset, text)
end

--------------------------------------------------------------------------------
-- Loot
--------------------------------------------------------------------------------

-- A result table keyed off the roll: at a fishing night, rolling a 3 catches an
-- anchovy. The bands are the host's, the roll is the ordinary /roll everyone
-- already uses, and the line arrives a few seconds later so it reads as the
-- outcome of the roll rather than as part of it.

--- The band a roll falls into, or nil. First match wins, so a host can put a
--- narrow band above a wide one and have it take precedence.
function RollWatcher:LootFor(preset, roll)
	local loot = preset.loot

	if not loot or not loot.enabled then
		return nil
	end

	for _, entry in ipairs(loot.entries) do
		if roll >= entry.min and roll <= entry.max then
			return entry
		end
	end

	return nil
end

--- The line for a roll, or nil when the table says nothing about it.
function RollWatcher:FormatLoot(preset, name, roll)
	local loot = preset.loot
	local entry = self:LootFor(preset, roll)

	local text = entry and entry.text or loot.nothingText
	if not text or text == "" then
		return nil
	end

	local line = loot.message
	if not line or line == "" then
		return nil
	end

	-- gsub rather than format: every one of these strings is host-editable, and
	-- a stray % in a format string errors instead of printing.
	line = line:gsub("{name}", self:DisplayName(name))
	line = line:gsub("{item}", text)
	line = line:gsub("{roll}", tostring(roll))

	return REH.StripChatEscapes(line), entry
end

--- Show the loot for a roll, after the preset's delay.
---
--- The delay is what makes this readable at an event, and it is also what makes
--- the channel matter: a message sent from a timer has no click behind it, and
--- the client only lets an addon reach /say, /yell, /emote, whispers and custom
--- channels on the back of one. Party, raid, guild, officer and instance chat
--- have no such rule, so those are the ones a loot table can be announced in
--- reliably. The host is told once rather than left wondering.
function RollWatcher:ScheduleLoot(preset, name, roll)
	local line = self:FormatLoot(preset, name, roll)
	if not line then
		return false
	end

	local announce = preset.loot.announce and preset.channel.type ~= "PREVIEW"

	if announce and REH.Announcer.NEEDS_HARDWARE_EVENT[preset.channel.type] then
		if not self.lootChannelWarned then
			self.lootChannelWarned = true
			REH:PrintWarning(L["Loot results are sent a few seconds after the roll, and your client only lets an addon send to %s right after you click something. Party, raid, guild, officer and instance chat are delivered every time."]
				:format(REH.DISPLAY.channel[preset.channel.type] or preset.channel.type))
		end
	end

	local function deliver()
		REH:Print("|cffffd100%s|r", line)

		if announce then
			self:QueueLine(preset, line)
		end
	end

	local delay = preset.loot.delaySeconds or 0
	if delay <= 0 then
		deliver()
	else
		C_Timer.After(delay, deliver)
	end

	return true
end

--------------------------------------------------------------------------------
-- The log
--------------------------------------------------------------------------------

local function CurrentRound()
	return rounds[currentRound]
end

--- Start a new round. Returns the round number, and whether a new one was
--- actually created -- pressing it twice on an empty round is a no-op rather
--- than a way to accumulate empty rounds.
function RollWatcher:NewRound()
	if #CurrentRound().entries == 0 then
		return currentRound, false
	end

	rounds[#rounds + 1] = { entries = {}, tallies = {} }
	currentRound = #rounds

	if REH.UI and REH.UI.RollLog then
		REH.UI.RollLog:OnRoundChanged(currentRound)
	end

	return currentRound, true
end

--- Start a round and tell the room about it.
---
--- The marker is announced whether or not a new round object was created: the
--- first round of an event still needs announcing, and the host pressing the
--- button means "we are starting now" regardless of the bookkeeping.
function RollWatcher:BeginRound()
	local number, created = self:NewRound()
	local preset = REH.Database:GetActivePreset()

	REH.Announcer:AnnounceRound(preset, number)

	-- Starting rounds without tracking rolls is a reasonable thing to want, so
	-- this is a note rather than an assumption that the watcher should be on.
	if not self:IsWatching() then
		REH:Print(L["The roll watcher is off, so rolls in this round are not being tracked."])
	end

	return number, created
end

function RollWatcher:GetRoundCount()
	return #rounds
end

function RollWatcher:GetCurrentRound()
	return currentRound
end

--- Entries and tallies for one round. Round 0 is every round together, so a
--- host can see the event's totals as well as the current exchange.
function RollWatcher:GetRound(index)
	if index and index > 0 then
		local round = rounds[index]
		if not round then
			return {}, {}
		end
		return round.entries, round.tallies
	end

	local entries, tallies = {}, {}

	for _, round in ipairs(rounds) do
		for _, entry in ipairs(round.entries) do
			entries[#entries + 1] = entry
		end

		for name, tally in pairs(round.tallies) do
			local combined = tallies[name]
			if not combined then
				combined = { total = 0, successes = 0, failures = 0, criticals = 0 }
				tallies[name] = combined
			end
			combined.total = combined.total + tally.total
			combined.successes = combined.successes + tally.successes
			combined.failures = combined.failures + tally.failures
			combined.criticals = combined.criticals + tally.criticals
		end
	end

	return entries, tallies
end

function RollWatcher:Record(name, roll, verdict, maxRoll)
	local log = CurrentRound()

	local entry = {
		name = name,
		roll = roll,
		verdict = verdict,
		maxRoll = maxRoll,
		round = currentRound,
		time = (date and date("%H:%M:%S")) or "",
	}

	log.entries[#log.entries + 1] = entry

	local tally = log.tallies[name]
	if not tally then
		tally = { total = 0, successes = 0, failures = 0, criticals = 0 }
		log.tallies[name] = tally
	end

	-- The log window is not polling, so it has to be told. Refresh is a no-op
	-- until the window has been built, so this costs nothing when it is closed.
	if REH.UI and REH.UI.RollLog then
		REH.UI.RollLog:Refresh()
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

--- The current round, which is what most callers mean by "the log".
function RollWatcher:GetLog()
	return CurrentRound().entries, CurrentRound().tallies
end

function RollWatcher:ClearLog()
	rounds = { { entries = {}, tallies = {} } }
	currentRound = 1
	ignoredOutsideGroup = 0
	ignoredForRange = 0
	hintShown = false
	rangeHintShown = false
	capWarned = false
	self.lootChannelWarned = false

	if REH.UI and REH.UI.RollLog then
		REH.UI.RollLog:OnRoundChanged()
	end
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
		-- Being told which die was ignored, and how to accept it, beats
		-- wondering why a roll vanished.
		if reason == "range" then
			ignoredForRange = ignoredForRange + 1

			if not rangeHintShown then
				rangeHintShown = true
				REH:PrintWarning(L["Ignored a /roll %d: these rules use /roll %d. Change what counts on the Watcher tab, or with /reh range any."]
					:format(maxRoll, preset.rolls.dieMax))
			end
		end

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

	local verdict = self:Judge(preset, roll, maxRoll)
	local entry = self:Record(fullName, roll, verdict, maxRoll)

	REH:Print(self:FormatVerdict(preset, fullName, roll, verdict, true, maxRoll))

	if self.mode == "announce" then
		self:QueueLine(preset,
			self:FormatVerdict(preset, fullName, roll, verdict, false, maxRoll))
	end

	-- Loot follows its own switch rather than the watcher's mode: a fishing
	-- night wants the catch in the room without the success/failure verdicts
	-- going with it.
	self:ScheduleLoot(preset, fullName, roll)

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
