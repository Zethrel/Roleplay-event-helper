local ADDON_NAME, REH = ...

local Templates = {}
REH.Templates = Templates

-- Starter presets: four real events, written out in full.
--
-- The default preset is a worked example of the numbers and nothing else, which
-- leaves a new host to reverse-engineer what an event is meant to look like --
-- and leaves the loot table and roll effects undiscovered entirely, since
-- neither appears until someone switches them on. These are the same features
-- shown doing their job.
--
-- Three rules they all follow:
--
--   They announce to preview only, like every new preset. A template is not a
--   licence to surprise a channel.
--
--   They are internally consistent, so creating one never triggers a repair
--   from validation. A template that gets clamped on the way in is a template
--   with a bug, and M12 checks every one of them against that.
--
--   They switch off the sections they do not use. A fishing night with an
--   empty combat section in its announcement teaches the wrong thing.

local function Disable(preset, ...)
	for _, key in ipairs({ ... }) do
		preset.moduleEnabled[key] = false
	end
end

--------------------------------------------------------------------------------
-- The templates
--------------------------------------------------------------------------------

Templates.LIST = {
	{
		key = "duel",
		name = "Duel Ring",
		summary = "One-on-one duels: initiative, armor-based health, first to zero loses.",
		build = function(preset)
			preset.header.eventName = "Duel Ring"
			preset.header.description = "One-on-one duels. First to zero health loses the bout."

			preset.rolls.dieMax = 100
			preset.rolls.successThreshold = 50
			preset.rolls.useCritical = true
			preset.rolls.critSuccessAt = 95
			preset.rolls.critFailAt = 5
			preset.rolls.tieBreak = "reroll"

			preset.damage.perHit = 1
			preset.damage.onCrit = 2
			preset.damage.deathRule = "out"

			preset.turns.mode = "initiative"
			preset.turns.turnTimeSeconds = 60

			preset.custom = {
				"Two fighters in the ring, everyone else outside it.",
				"Say your armor class before your first roll.",
				"A duel ends at zero health, or when a fighter yields.",
				"The host's call on a contested roll is final.",
			}

			preset.etiquette = {
				"Keep emotes to two sentences so the bout keeps moving.",
				"Describe the attempt, not the outcome. The roll decides that.",
				"Losing well is better roleplay than winning.",
			}

			Disable(preset, "loot")
		end,
	},

	{
		key = "fishing",
		name = "Fishing Night",
		summary = "A results table read off the roll, with several fish per band picked at random.",
		build = function(preset)
			preset.header.eventName = "Fishing Night"
			preset.header.description = "Cast with /roll 20 and see what comes up."

			preset.rolls.dieMax = 20
			preset.rolls.successThreshold = 8
			preset.rolls.useCritical = true
			preset.rolls.critSuccessAt = 20
			preset.rolls.critFailAt = 1

			-- Nothing here succeeds or fails. A 7 is a fat carp, and calling it
			-- a FAILURE in the same breath contradicts the catch.
			preset.rolls.useVerdicts = false

			-- The table is the point of this one. Bands written twice or three
			-- times are alternatives, one chosen at random, which is what makes
			-- an evening of the same roll stay interesting.
			preset.loot.enabled = true
			preset.loot.announce = true
			preset.loot.delaySeconds = 3
			preset.loot.message = "{name} reels in {item}."
			preset.loot.nothingText = "a handful of weeds"
			preset.loot.entries = {
				{ min = 1,  max = 1,  text = "a snapped line and nothing on the end of it" },
				{ min = 2,  max = 3,  text = "an old boot" },
				{ min = 2,  max = 3,  text = "a rusted tin" },
				{ min = 4,  max = 7,  text = "a small salmon" },
				{ min = 4,  max = 7,  text = "a speckled trout" },
				{ min = 4,  max = 7,  text = "a fat carp" },
				{ min = 8,  max = 13, text = "a good-sized bream" },
				{ min = 8,  max = 13, text = "a silver perch" },
				{ min = 14, max = 17, text = "a pike, all teeth" },
				{ min = 18, max = 19, text = "a sturgeon that takes both arms" },
				{ min = 20, max = 20, text = "the one the old-timers talk about" },
			}

			-- Effects on top of the table: the room reacting, rather than what
			-- was caught. Two of them share a trigger and are marked as
			-- alternatives, so a big catch does not get the same line twice in
			-- an evening.
			preset.rollEffects = {
				{
					enabled = true, trigger = "band", min = 1, max = 1,
					verdict = "critfail", chance = 100, delaySeconds = 5, random = false,
					target = "channel",
					message = "{name} stares at the empty line for a moment.",
				},
				{
					enabled = true, trigger = "band", min = 18, max = 20,
					verdict = "critsuccess", chance = 100, delaySeconds = 5, random = true,
					target = "channel",
					message = "The dock creaks as {name} hauls it in.",
				},
				{
					enabled = true, trigger = "band", min = 18, max = 20,
					verdict = "critsuccess", chance = 100, delaySeconds = 5, random = true,
					target = "channel",
					message = "Somebody drops their tankard watching {name} land it.",
				},
			}

			preset.turns.mode = "roundrobin"
			preset.turns.turnTimeSeconds = 0

			preset.custom = {
				"Cast by rolling /roll 20. What you catch is read off the roll.",
				"One cast each, then let the next person fish.",
				"Nobody is competing. Big fish and boots are both good stories.",
			}

			preset.etiquette = {
				"React to other people's catches; that is most of the evening.",
			}

			-- No combat at a fishing night, and an empty combat section in the
			-- announcement teaches the wrong thing about the addon.
			Disable(preset, "health", "damage")
		end,
	},

	{
		key = "tavern",
		name = "Tavern Night",
		summary = "No combat: house rules, etiquette, and a drinks table you read out yourself.",
		build = function(preset)
			preset.header.eventName = "Tavern Night"
			preset.header.description = "Drinks, talk, and no dice unless you want them."

			preset.rolls.dieMax = 20
			preset.rolls.successThreshold = 10
			preset.rolls.useCritical = false
			preset.rolls.critSuccessAt = 20
			preset.rolls.critFailAt = 1

			-- You do not fail at being handed a drink.
			preset.rolls.useVerdicts = false

			preset.turns.mode = "freeform"
			preset.turns.turnTimeSeconds = 0

			-- A tavern night is usually run in /say, and the client will not let
			-- an addon send to /say a few seconds after a roll. So the drinks
			-- come to the host, who reads them out in character -- which is
			-- better theatre anyway.
			preset.loot.enabled = true
			preset.loot.announce = false
			preset.loot.delaySeconds = 2
			preset.loot.message = "{name} is served {item}."
			preset.loot.nothingText = "whatever was left in the jug"
			preset.loot.entries = {
				{ min = 1,  max = 1,  text = "a cracked mug of something cloudy" },
				{ min = 2,  max = 5,  text = "a thin ale, mostly foam" },
				{ min = 6,  max = 12, text = "a decent house ale" },
				{ min = 6,  max = 12, text = "a cup of spiced cider" },
				{ min = 13, max = 17, text = "a dwarven stout worth the coin" },
				{ min = 18, max = 19, text = "a glass of Dalaran red" },
				{ min = 20, max = 20, text = "the barrel's last and best pour" },
			}

			preset.custom = {
				"Roll /roll 20 at the bar and the barkeep will tell you what you got.",
				"No combat inside. Take arguments outside and settle them there.",
				"Walk-ins welcome. Pull up a chair and join whatever is happening.",
			}

			preset.etiquette = {
				"Keep the room's conversations readable: one thread per table.",
				"Give quieter characters a way into the scene.",
				"Out-of-character chat goes in party, not in the room.",
			}

			Disable(preset, "health", "damage", "turns")
		end,
	},

	{
		key = "arena",
		name = "Arena Brawl",
		summary = "A raid-sized free-for-all, with only the fighting subgroups adjudicated.",
		build = function(preset)
			preset.header.eventName = "Arena Brawl"
			preset.header.description = "Everyone in the sand at once. Last one standing takes the purse."

			preset.rolls.dieMax = 100
			preset.rolls.successThreshold = 40
			preset.rolls.useCritical = true
			preset.rolls.critSuccessAt = 95
			preset.rolls.critFailAt = 5
			preset.rolls.tieBreak = "attacker"

			-- More health and harder hits than a duel: a brawl with duel
			-- numbers is over before the crowd has arrived.
			preset.health.rows = {
				{ label = "Cloth",   hp = 12 },
				{ label = "Leather", hp = 14 },
				{ label = "Mail",    hp = 16 },
				{ label = "Plate",   hp = 18 },
			}
			preset.health.modifiers = {
				{ label = "Shield equipped", bonus = 2 },
			}

			preset.damage.perHit = 2
			preset.damage.onCrit = 4
			preset.damage.deathRule = "out"

			preset.turns.mode = "host"
			preset.turns.turnTimeSeconds = 45

			-- The reason this template exists: at a raid-sized event the crowd
			-- rolls too, and adjudicating spectators is how a log becomes
			-- unreadable. Fighters are groups 1 and 2; everyone else watches.
			preset.rollFilter.mode = "subgroup"
			preset.rollFilter.subgroups = { 1, 2 }

			preset.rounds.announce = true

			preset.custom = {
				"Fighters are in raid groups 1 and 2. Everyone else is the crowd.",
				"Rolls from outside those groups are not counted, so cheer freely.",
				"Ring-outs are eliminations. Stay in the sand.",
				"At zero health you are out. Play it, then move to the stands.",
			}

			preset.etiquette = {
				"One emote per turn. Twenty people are waiting on yours.",
				"Wait for the host to call your name before rolling.",
				"The crowd is part of the show: react, do not narrate the fight.",
			}

			Disable(preset, "loot")
		end,
	},
}

--------------------------------------------------------------------------------
-- Lookup and creation
--------------------------------------------------------------------------------

function Templates:Find(key)
	if type(key) ~= "string" then
		return nil
	end

	key = key:lower()

	for _, template in ipairs(self.LIST) do
		if template.key == key then
			return template
		end
	end

	-- Matching on the shown name too, so "/reh template fishing night" does what
	-- it obviously means.
	for _, template in ipairs(self.LIST) do
		if template.name:lower() == key then
			return template
		end
	end

	return nil
end

function Templates:Keys()
	local keys = {}
	for index, template in ipairs(self.LIST) do
		keys[index] = template.key
	end
	return keys
end

--- Build a preset from a template. Returns the preset and the template, or nil
--- and a reason. Nothing is saved here; the database decides that.
function Templates:Build(key, presetName)
	local template = self:Find(key)
	if not template then
		return nil, ("No starter preset called '%s'. Try /reh templates."):format(tostring(key))
	end

	local preset = REH.CreateDefaultPreset(presetName or template.name)
	template.build(preset)

	-- The event name follows the preset's name when the host chose one, since
	-- having a preset called "Friday Duels" announce itself as "Duel Ring" is a
	-- surprise waiting at the worst moment.
	if presetName and presetName ~= "" then
		preset.header.eventName = presetName
	end

	return preset, template
end
