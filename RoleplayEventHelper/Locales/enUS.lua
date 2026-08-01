local ADDON_NAME, REH = ...

-- Localization works on the "English string is the key" model: any string that
-- has no translation falls through the metatable and returns itself, so a
-- missing entry degrades to readable English rather than a nil error.
--
-- To add a locale, create Locales\<code>.lua, load it after this file in the
-- TOC, and assign only the keys that locale translates.

local L = setmetatable({}, {
	__index = function(self, key)
		rawset(self, key, key)
		return key
	end,
})

REH.L = L

-- enUS needs no assignments; the fallback returns the key verbatim. Entries are
-- listed here anyway so translators have a single file showing every string.

L["Roleplay Event Helper"] = "Roleplay Event Helper"
L["Commands:"] = "Commands:"
L["Presets (%d):"] = "Presets (%d):"
L["Usage: %s"] = "Usage: %s"
L["Unknown command '%s'. Type /reh help for the command list."] = "Unknown command '%s'. Type /reh help for the command list."

-- Preset management
L["A preset name cannot be empty."] = "A preset name cannot be empty."
L["A preset name cannot contain the | character."] = "A preset name cannot contain the | character."
L["A preset named '%s' already exists."] = "A preset named '%s' already exists."
L["No preset named '%s'."] = "No preset named '%s'."
L["You already have the maximum of %d presets."] = "You already have the maximum of %d presets."
L["Active preset is now '%s'."] = "Active preset is now '%s'."
L["Created preset '%s' and made it active."] = "Created preset '%s' and made it active."
L["Copied '%s' to '%s' and made it active."] = "Copied '%s' to '%s' and made it active."
L["Renamed '%s' to '%s'."] = "Renamed '%s' to '%s'."
L["Deleted preset '%s'."] = "Deleted preset '%s'."
L["Reset preset '%s' to defaults."] = "Reset preset '%s' to defaults."

-- Confirmation of destructive actions
L["%s Type /reh confirm within %d seconds to proceed."] = "%s Type /reh confirm within %d seconds to proceed."
L["This will delete the preset '%s'."] = "This will delete the preset '%s'."
L["This will reset '%s' to the default rules."] = "This will reset '%s' to the default rules."
L["Nothing is waiting for confirmation."] = "Nothing is waiting for confirmation."
L["That confirmation expired. Run the command again."] = "That confirmation expired. Run the command again."

-- Announcing
L["Announcing '%s' to %s: %d messages, about %d seconds. /reh cancel to stop."] = "Announcing '%s' to %s: %d messages, about %d seconds. /reh cancel to stop."
L["Announced '%s': %d messages sent."] = "Announced '%s': %d messages sent."
L["Announcement cancelled after %d of %d messages."] = "Announcement cancelled after %d of %d messages."
L["Nothing is being announced."] = "Nothing is being announced."
L["Already announcing. Use /reh cancel first."] = "Already announcing. Use /reh cancel first."
L["This preset is set to preview only. Use /reh channel <type> to choose where to announce."] = "This preset is set to preview only. Use /reh channel <type> to choose where to announce."
L["'%s' has no enabled rules to announce."] = "'%s' has no enabled rules to announce."
L["The client blocked message %d of %d, so the announcement stopped."] = "The client blocked message %d of %d, so the announcement stopped."
L["Reason: %s"] = "Reason: %s"

-- Channel selection and availability
L["'%s' announces to: %s"] = "'%s' announces to: %s"
L["'%s' will announce to: %s"] = "'%s' will announce to: %s"
L["Not available right now: %s"] = "Not available right now: %s"
L["You are not in a party."] = "You are not in a party."
L["You are not in a raid."] = "You are not in a raid."
L["You are not in a guild."] = "You are not in a guild."
L["You are not in an instance group."] = "You are not in an instance group."
L["Raid warnings need raid lead or assist."] = "Raid warnings need raid lead or assist."
L["You have not joined the channel '%s'."] = "You have not joined the channel '%s'."
L["No channel name set. Use /reh channel channel <name>."] = "No channel name set. Use /reh channel channel <name>."
L["No whisper target set. Use /reh channel whisper <name>."] = "No whisper target set. Use /reh channel whisper <name>."
L["Which channel? Use /reh channel channel <name>."] = "Which channel? Use /reh channel channel <name>."
L["Whisper whom? Use /reh channel whisper <name>."] = "Whisper whom? Use /reh channel whisper <name>."

-- Roll watcher
L["Roll watcher is %s."] = "Roll watcher is %s."
L["Watcher mode must be off, local or announce."] = "Watcher mode must be off, local or announce."
L["Tracking %s."] = "Tracking %s."
L["Tracking %s (%d in your group)."] = "Tracking %s (%d in your group)."
L["Filter must be group, subgroup, roster or everyone."] = "Filter must be group, subgroup, roster or everyone."
L["%d rolls ignored from outside your group. Use /reh filter everyone to include them."] = "%d rolls ignored from outside your group. Use /reh filter everyone to include them."
L["Too many rolls to announce (%d a minute). Verdicts are showing here only."] = "Too many rolls to announce (%d a minute). Verdicts are showing here only."
L["This preset announces to preview only, so verdicts will show here rather than in chat."] = "This preset announces to preview only, so verdicts will show here rather than in chat."
L["No subgroups chosen yet, so the whole raid counts. Set them with /reh subgroups 1 2."] = "No subgroups chosen yet, so the whole raid counts. Set them with /reh subgroups 1 2."
L["No subgroups chosen; the whole raid counts."] = "No subgroups chosen; the whole raid counts."
L["Combatant subgroups: %s"] = "Combatant subgroups: %s"
L["No valid subgroups in that. Subgroups are 1 to 8."] = "No valid subgroups in that. Subgroups are 1 to 8."
L["Muted %s for this session."] = "Muted %s for this session."
L["Unmuted %s."] = "Unmuted %s."

-- Roster and log
L["The saved roster is empty."] = "The saved roster is empty."
L["Saved roster (%d):"] = "Saved roster (%d):"
L["Imported %d names from your group into the roster."] = "Imported %d names from your group into the roster."
L["Added %s to the roster."] = "Added %s to the roster."
L["Removed %s from the roster."] = "Removed %s from the roster."
L["%s is not on the roster."] = "%s is not on the roster."
L["Roster cleared."] = "Roster cleared."
L["Roll log (%d):"] = "Roll log (%d):"
L["Roll log cleared."] = "Roll log cleared."
L["No rolls recorded yet."] = "No rolls recorded yet."
L["Totals:"] = "Totals:"

-- Saved data
L["Your saved data is from a newer version (format %d, this build reads %d). It has been left untouched. Update the addon to use it."] = "Your saved data is from a newer version (format %d, this build reads %d). It has been left untouched. Update the addon to use it."
