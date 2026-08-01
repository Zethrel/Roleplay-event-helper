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

-- Saved data
L["Your saved data is from a newer version (format %d, this build reads %d). It has been left untouched. Update the addon to use it."] = "Your saved data is from a newer version (format %d, this build reads %d). It has been left untouched. Update the addon to use it."
