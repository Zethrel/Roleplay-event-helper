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
L["Type /reh help for commands."] = "Type /reh help for commands."
L["Commands:"] = "Commands:"
L["show this command list"] = "show this command list"
L["show addon and client version details"] = "show addon and client version details"
L["Unknown command '%s'. Type /reh help for the command list."] = "Unknown command '%s'. Type /reh help for the command list."
