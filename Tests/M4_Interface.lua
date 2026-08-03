-- M4: the editor schema and the main window.
--
-- The window itself is built against a widget mock that only allows methods
-- that actually exist on the client, so building it at all proves the layout
-- code calls nothing imaginary. Everything above the widgets -- reading and
-- writing rules, refreshing the preview, enabling the announce button -- is
-- tested directly.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "Tests"
local H = dofile(here .. "/Harness.lua")

H.installStubs()
H.snapshotGlobals()
H.wipeSavedVariables()

local REH = H.login()
local DB = REH.Database
local Fields = REH.Fields
local MainFrame = REH.UI.MainFrame

--------------------------------------------------------------------------------
H.section("The schema is complete")
--------------------------------------------------------------------------------

local preset = DB:GetActivePreset()
local fieldCount = 0
local allReadable, allWritable = true, true
local unreadable, unwritable = nil, nil

-- Tabs may edit the active preset or the account settings, so each one is
-- checked against whatever it actually writes to.
for _, tab in ipairs(Fields:GetTabs()) do
	local target = Fields:GetTarget(tab)

	for _, field in ipairs(tab.fields) do
		fieldCount = fieldCount + 1

		-- An action row is a button through to another window; it edits no
		-- value, so it has nothing to read or write.
		if field.type == "action" then
			if type(field.onClick) ~= "function" then
				allReadable = false
				unreadable = tab.module .. "." .. field.key .. " (no onClick)"
			end

		elseif type(field.get) ~= "function" or field.get(target) == nil then
			allReadable = false
			unreadable = tab.module .. "." .. field.key
		end

		if field.type ~= "action" and type(field.set) ~= "function" then
			allWritable = false
			unwritable = tab.module .. "." .. field.key
		end
	end
end

H.check("there are fields to edit", fieldCount > 15, fieldCount)
H.check("every field reads a value from a default preset", allReadable, unreadable)
H.check("every field can be written", allWritable, unwritable)

local everyModuleHasATab = true
for _, moduleKey in ipairs(REH.MODULE_KEYS) do
	if not Fields:FindTab(moduleKey) then
		everyModuleHasATab = false
	end
end
H.check("every announceable module has an editor tab", everyModuleHasATab)

local selectsAreValid = true
for _, tab in ipairs(Fields:GetTabs()) do
	local target = Fields:GetTarget(tab)
	for _, field in ipairs(tab.fields) do
		if field.type == "select" then
			local current = field.get(target)
			local found = false
			for _, option in ipairs(field.options()) do
				if option.value == current then
					found = true
				end
			end
			if not found then
				selectsAreValid = false
			end
		end
	end
end
H.check("every choice field's current value is among its options", selectsAreValid)

--------------------------------------------------------------------------------
H.section("List fields round-trip")
--------------------------------------------------------------------------------

local rows = Fields.ParseValueLines("Cloth 10\nLeather 11\nMail 12\nPlate 13", "hp")
H.checkEqual("four health rows parsed", #rows, 4)
H.checkEqual("label kept", rows[1].label, "Cloth")
H.checkEqual("value kept", rows[4].hp, 13)

H.checkEqual("and serialize back unchanged",
	Fields.SerializeValueLines(rows, "hp", false),
	"Cloth 10\nLeather 11\nMail 12\nPlate 13")

local equals = Fields.ParseValueLines("Cloth = 10", "hp")
H.checkEqual("an equals sign is accepted", equals[1].hp, 10)

local spaced = Fields.ParseValueLines("Heavy Plate Armor 15", "hp")
H.checkEqual("multi-word labels keep their spaces", spaced[1].label, "Heavy Plate Armor")
H.checkEqual("and their value", spaced[1].hp, 15)

local signed = Fields.ParseValueLines("Shield equipped +1\nTwo-handed -1", "bonus")
H.checkEqual("a positive modifier parses", signed[1].bonus, 1)
H.checkEqual("a negative modifier parses", signed[2].bonus, -1)
H.checkEqual("and serializes with its sign",
	Fields.SerializeValueLines(signed, "bonus", true), "Shield equipped +1\nTwo-handed -1")

-- A half-typed line must not silently vanish while the host is still editing.
local noNumber = Fields.ParseValueLines("Cloth 10\nLeather", "hp")
H.checkEqual("a line with no number is kept", #noNumber, 2)
H.checkEqual("with a value of zero", noNumber[2].hp, 0)

local ruleLines = Fields.ParseStringLines("  No mounts.  \n\n\nNo consumables.\n   \n")
H.checkEqual("blank lines are dropped", #ruleLines, 2)
H.checkEqual("and the rest trimmed", ruleLines[1], "No mounts.")

--------------------------------------------------------------------------------
H.section("Writing through the schema")
--------------------------------------------------------------------------------

local scratch = REH.CreateDefaultPreset("Scratch")
DB:ValidatePreset(scratch)

local nameField = Fields:FindField("header", "eventName")
H.check("a field can be found by module and key", nameField ~= nil)
Fields:Set(scratch, nameField, "  Gurubashi Arena  ")
H.checkEqual("text is trimmed on write", scratch.header.eventName, "Gurubashi Arena")

local thresholdField = Fields:FindField("rolls", "successThreshold")
Fields:Set(scratch, thresholdField, "25")
H.checkEqual("a numeric string is stored as a number", scratch.rolls.successThreshold, 25)

Fields:Set(scratch, thresholdField, "12.6")
H.checkEqual("a fractional entry is rounded", scratch.rolls.successThreshold, 13)

local ok, reason = Fields:Set(scratch, thresholdField, "ten")
H.check("a non-numeric entry is rejected", ok == false)
H.check("with a reason naming the field",
	(reason or ""):find("Success at or above", 1, true) ~= nil, reason)
H.checkEqual("and the old value is untouched", scratch.rolls.successThreshold, 13)

-- Cross-field rules must hold the moment a field changes, not at the next
-- reload: an impossible threshold left on screen is a rule the host will read
-- out loud and be wrong about.
Fields:Set(scratch, thresholdField, "90")
Fields:Set(scratch, Fields:FindField("rolls", "dieMax"), "20")
H.checkEqual("lowering the die max pulls the threshold down with it",
	scratch.rolls.successThreshold, 20)

local toggleField = Fields:FindField("rolls", "useCritical")
Fields:Set(scratch, toggleField, false)
H.checkEqual("a toggle stores false", scratch.rolls.useCritical, false)
Fields:Set(scratch, toggleField, true)
H.checkEqual("and true", scratch.rolls.useCritical, true)

local tieField = Fields:FindField("rolls", "tieBreak")
H.check("a valid choice is accepted", Fields:Set(scratch, tieField, "attacker"))
H.checkEqual("and stored", scratch.rolls.tieBreak, "attacker")
H.check("an invalid choice is refused", Fields:Set(scratch, tieField, "coinflip") == false)
H.checkEqual("leaving the previous choice", scratch.rolls.tieBreak, "attacker")

local rowsField = Fields:FindField("health", "rows")
Fields:Set(scratch, rowsField, "Cloth 20\nPlate 40")
H.checkEqual("a list field is replaced wholesale", #scratch.health.rows, 2)
H.checkEqual("with the typed values", scratch.health.rows[2].hp, 40)

Fields:Set(scratch, rowsField, "")
H.checkEqual("clearing a list empties it", #scratch.health.rows, 0)

local prefixField = Fields:FindField("etiquette", "linePrefix")
Fields:Set(scratch, prefixField, "|cffff0000[Evil]")
H.check("a colour escape typed into the prefix is stripped",
	scratch.formatting.linePrefix:find("|", 1, true) == nil,
	scratch.formatting.linePrefix)

--------------------------------------------------------------------------------
H.section("The window builds")
--------------------------------------------------------------------------------

-- The widget mock raises on any method outside its allowlist, so reaching the
-- end of this without an error means the layout code only called API that
-- exists on the client.
MainFrame:Show()
H.check("the window builds and shows", MainFrame:IsShown())
H.check("it is registered for Escape to close", (function()
	for _, name in ipairs(UISpecialFrames) do
		if name == "RoleplayEventHelperFrame" then
			return true
		end
	end
	return false
end)())

local frame = MainFrame:GetFrame()
H.check("a preset list was built", frame.presetList ~= nil)
H.check("an editor area was built", frame.editors ~= nil)
H.check("a preview pane was built", frame.preview ~= nil)
H.check("an announce button was built", frame.announceButton ~= nil)
H.checkEqual("one tab button per schema tab", #frame.tabButtons, #Fields:GetTabs())
H.checkEqual("one editor page per schema tab", #frame.editors.pages, #Fields:GetTabs())

MainFrame:Hide()
H.check("and it hides again", MainFrame:IsShown() == false)
MainFrame:Show()

--------------------------------------------------------------------------------
H.section("Tabs")
--------------------------------------------------------------------------------

MainFrame:SelectTab(2)
H.check("the selected page is shown", frame.editors.pages[2].frame:IsShown())
H.check("and the others are hidden", frame.editors.pages[1].frame:IsShown() == false)

frame.tabButtons[3]:Click()
H.checkEqual("clicking a tab button switches page", frame.editors.activeIndex, 3)
H.check("the active tab's button is disabled so it reads as selected",
	frame.tabButtons[3]:IsEnabled() == false)
H.check("and the others stay clickable", frame.tabButtons[1]:IsEnabled())

--------------------------------------------------------------------------------
H.section("Editing through the widgets")
--------------------------------------------------------------------------------

local function findRow(moduleKey, fieldKey)
	for _, page in ipairs(frame.editors.pages) do
		if page.tab.module == moduleKey then
			for _, row in ipairs(page.rows) do
				if row.field.key == fieldKey then
					return row
				end
			end
		end
	end
	return nil
end

-- Tabs are found by module rather than by position. A new editor tab moves
-- every index after it, and a hardcoded number then silently tests the wrong
-- page instead of failing outright.
local function tabIndex(moduleKey)
	for index, page in ipairs(frame.editors.pages) do
		if page.tab.module == moduleKey then
			return index
		end
	end
	return nil
end

local active = DB:GetActivePreset()

MainFrame:SelectTab(1)
local nameRow = findRow("header", "eventName")
H.check("the event name row exists", nameRow ~= nil)
H.checkEqual("and shows the current value",
	nameRow.control:GetText(), active.header.eventName)

nameRow.control:SetText("Tavern Brawl Night")
H.fireScript(nameRow.control, "OnEditFocusLost")
H.checkEqual("typing into it updates the preset",
	active.header.eventName, "Tavern Brawl Night")

local rollsPage = tabIndex("rolls")
MainFrame:SelectTab(rollsPage)
local dieRow = findRow("rolls", "dieMax")
dieRow.control:SetText("20")
H.fireScript(dieRow.control, "OnEnterPressed")
H.checkEqual("a number field writes through", active.rolls.dieMax, 20)

local critRow = findRow("rolls", "useCritical")
critRow.control:SetChecked(false)
critRow.control:Click()
H.checkEqual("a checkbox writes through", active.rolls.useCritical, false)

local tieRow = findRow("rolls", "tieBreak")
local beforeTie = active.rolls.tieBreak
tieRow.control:Click()
H.check("a choice button advances to the next option",
	active.rolls.tieBreak ~= beforeTie, active.rolls.tieBreak)
H.check("and the stored value is a legal one",
	REH.IsValidEnum(REH.TIE_BREAKS, active.rolls.tieBreak))

MainFrame:SelectTab(tabIndex("health"))
local rowsRow = findRow("health", "rows")
rowsRow.control.editBox:SetText("Cloth 5\nPlate 9")
H.fireScript(rowsRow.control.editBox, "OnEditFocusLost")
H.checkEqual("a list field writes through", #active.health.rows, 2)
H.checkEqual("with the typed value", active.health.rows[2].hp, 9)

-- A rejected edit must not leave the bad text sitting in the box.
MainFrame:SelectTab(rollsPage)
local thresholdRow = findRow("rolls", "successThreshold")
local goodValue = active.rolls.successThreshold
thresholdRow.control:SetText("nonsense")
H.fireScript(thresholdRow.control, "OnEditFocusLost")
H.checkEqual("a rejected edit leaves the preset alone",
	active.rolls.successThreshold, goodValue)
H.checkEqual("and the box is put back to the real value",
	thresholdRow.control:GetText(), tostring(goodValue))

--------------------------------------------------------------------------------
H.section("Multi-line boxes can actually be typed into")
--------------------------------------------------------------------------------

-- A frame with no height has no area to click, so it never takes focus and
-- nothing typed reaches it. The box looks present and refuses input, which is
-- invisible to any test that only checks the text round-trips.
local multiLineRows = 0
for _, page in ipairs(frame.editors.pages) do
	for _, row in ipairs(page.rows) do
		if row.field.type == "lines" then
			multiLineRows = multiLineRows + 1
			local editBox = row.control.editBox

			H.check(row.field.key .. " has a clickable height",
				editBox:GetHeight() > 0, editBox:GetHeight())
			H.check(row.field.key .. " has a width", editBox:GetWidth() > 0)
		end
	end
end
H.check("there are multi-line fields to check", multiLineRows >= 4, multiLineRows)

-- Nesting a scroll frame inside the editor's own scroll frame is what stopped
-- these boxes receiving clicks at all, so there must not be one.
local nested = false
for _, page in ipairs(frame.editors.pages) do
	for _, row in ipairs(page.rows) do
		if row.field.type == "lines" and row.control.scrollFrame then
			nested = true
		end
	end
end
H.check("no multi-line box nests a scroll frame inside the page's own", nested == false)

MainFrame:SelectTab(tabIndex("custom"))
local rulesRow = findRow("custom", "custom")
H.check("the custom rules row exists", rulesRow ~= nil)

-- Clicking the panel around the text should put the cursor in it, rather than
-- requiring a hit on the text itself.
H.fireScript(rulesRow.control, "OnMouseDown")
H.check("clicking the box focuses it", rulesRow.control.editBox:HasFocus())

rulesRow.control.editBox:SetText("No mounts inside the ring.\nNo consumables.")
H.fireScript(rulesRow.control.editBox, "OnEditFocusLost")
H.checkEqual("and what is typed is kept", #DB:GetActivePreset().custom, 2)

-- The child has to grow with the text or a long list runs off the bottom.
local shortHeight = rulesRow.control.editBox:GetHeight()
local manyLines = {}
for index = 1, 30 do
	manyLines[index] = "Rule number " .. index .. "."
end
rulesRow.control.editBox:SetText(table.concat(manyLines, "\n"))
H.check("the box grows with a long list",
	rulesRow.control.editBox:GetHeight() > shortHeight,
	("%s -> %s"):format(shortHeight, rulesRow.control.editBox:GetHeight()))

-- Growing must push the rows below it down and make the page taller, or the
-- extra lines would sit under the next field and be unreachable.
local rulesPage
for _, page in ipairs(frame.editors.pages) do
	if page.tab.module == "custom" then
		rulesPage = page
	end
end

-- Back to a short list first: the height is measured before the growth, not
-- after an earlier check already grew it.
rulesRow.control.editBox:SetText("One rule.")
local pageHeightBefore = rulesPage.height

rulesRow.control.editBox:SetText(table.concat(manyLines, "\n"))
H.check("a grown field makes its page taller",
	rulesPage.height > pageHeightBefore,
	("%s -> %s"):format(pageHeightBefore, rulesPage.height))

local scrollChild = frame.editorScroll.content
H.check("and the scroll child follows, so the bottom stays reachable",
	scrollChild:GetHeight() >= rulesPage.height)

rulesRow.control.editBox:SetText("")
H.fireScript(rulesRow.control.editBox, "OnEditFocusLost")
H.check("and shrinking puts the page back",
	rulesPage.height <= pageHeightBefore + 1,
	("%s vs %s"):format(rulesPage.height, pageHeightBefore))

--------------------------------------------------------------------------------
H.section("The preview pane")
--------------------------------------------------------------------------------

local Preview = REH.UI.Preview
local text, count, seconds = Preview:BuildText(active)
local expected = REH.Formatter:BuildMessages(active)

H.checkEqual("the preview counts the real messages", count, #expected)
H.check("and shows the first one", text:find(expected[1], 1, true) ~= nil)
H.check("the estimate grows with the message count", seconds >= 0)

-- Byte counts are noise until they are close to the limit, and the preview is
-- the pane a host reads the most.
H.check("a comfortable message carries no byte count",
	text:find("(" .. #expected[1] .. ")", 1, true) == nil, text:sub(1, 120))

local wordy = REH.CreateDefaultPreset("Wordy")
wordy.custom = { ("A rule that goes on. "):rep(11) }
DB:ValidatePreset(wordy)
local wordyText = Preview:BuildText(wordy)
H.check("but a message near the limit says how big it is",
	wordyText:find("(1", 1, true) ~= nil or wordyText:find("(2", 1, true) ~= nil,
	wordyText)

-- A rule too long for one chat message arrives as two, and the preview marks
-- it. Validation caps a rule at 200 characters against a 255-byte message, so
-- the split path is reached here by shrinking the budget rather than by writing
-- an impossibly long rule.
local huge = REH.CreateDefaultPreset("Huge")
huge.custom = { "A rule long enough to need two messages once the budget is small." }
DB:ValidatePreset(huge)

local _, _, _, hugeMeta = REH.Formatter:BuildMessages(huge, { maxBytes = 40 })
local sawSplit = false
for _, entry in ipairs(hugeMeta) do
	if entry.split then
		sawSplit = true
	end
end
H.check("a message that had to be split is tagged as split", sawSplit)

H.checkEqual("one message reads in the singular", Preview:BuildSummary(1, 0), "1 message")
H.check("several read in the plural",
	Preview:BuildSummary(8, 5.6):find("8 messages", 1, true) ~= nil)

-- Separators are the one part of the count a host can delete without losing a
-- rule, so the summary names them.
local separated = REH.CreateDefaultPreset("Separated")
DB:ValidatePreset(separated)
DB:GetSettings().useSeparators = true
local _, sepCount, sepSeconds, separators = Preview:BuildText(separated)
H.check("separators are counted", separators > 1, separators)
H.check("and called out in the summary",
	Preview:BuildSummary(sepCount, sepSeconds, separators):find("separators", 1, true) ~= nil,
	Preview:BuildSummary(sepCount, sepSeconds, separators))
H.check("with the total still counting them", sepCount > separators)

DB:GetSettings().useSeparators = false
H.check("and no separator note when there are none",
	Preview:BuildSummary(8, 5.6, 0):find("separator", 1, true) == nil)

local emptyPreset = REH.CreateDefaultPreset("Empty")
for _, key in ipairs(REH.MODULE_KEYS) do
	emptyPreset.moduleEnabled[key] = false
end
DB:ValidatePreset(emptyPreset)
local emptyText, emptyCount = Preview:BuildText(emptyPreset)
H.checkEqual("a preset with everything disabled has no messages", emptyCount, 0)
H.check("and says so rather than showing a blank pane",
	emptyText:find("Nothing to announce", 1, true) ~= nil, emptyText)

MainFrame:RefreshPreview()
H.check("the pane shows the current preset's rules",
	frame.preview.bodyText:GetText():find("/roll", 1, true) ~= nil)

nameRow = findRow("header", "eventName")
MainFrame:SelectTab(1)
nameRow.control:SetText("Renamed For Preview")
H.fireScript(nameRow.control, "OnEditFocusLost")
H.check("editing a rule updates the preview immediately",
	frame.preview.bodyText:GetText():find("Renamed For Preview", 1, true) ~= nil,
	frame.preview.bodyText:GetText())

--------------------------------------------------------------------------------
H.section("The announce controls")
--------------------------------------------------------------------------------

H.resetGroup()
H.clearSent()

REH.Announcer:SetChannel(active, "preview")
MainFrame:RefreshPreview()
H.check("preview is always available, so the button is enabled",
	frame.announceButton:IsEnabled())
H.check("the channel button names the target",
	frame.channelButton:GetText():find("preview", 1, true) ~= nil,
	frame.channelButton:GetText())

REH.Announcer:SetChannel(active, "party")
MainFrame:RefreshPreview()
H.check("an unavailable channel disables the announce button",
	frame.announceButton:IsEnabled() == false)
H.check("and the status line says why",
	frame.statusText:GetText():find("not in a party", 1, true) ~= nil,
	frame.statusText:GetText())

H.group.inGroup = true
MainFrame:RefreshPreview()
H.check("joining a party enables it again", frame.announceButton:IsEnabled())
H.checkEqual("and clears the status line", frame.statusText:GetText(), "")

frame.announceButton:Click()
H.check("clicking announce sends", #H.sent > 0)
H.check("the cancel button is enabled while sending", frame.cancelButton:IsEnabled())
H.check("and announce is disabled so it cannot be double-sent",
	frame.announceButton:IsEnabled() == false)
H.check("the status line reports progress",
	frame.statusText:GetText():find("Sending", 1, true) ~= nil, frame.statusText:GetText())

frame.cancelButton:Click()
H.check("cancel stops it", REH.Announcer:IsSending() == false)
H.advance(600)

H.clearSent()
frame.channelButton:Click()
H.check("the channel popup opens", frame.channelPopup:IsShown())
frame.channelPopup.rows[2]:Click()
H.check("choosing from it closes the popup", frame.channelPopup:IsShown() == false)
H.check("and changes the target", active.channel.type ~= "PARTY", active.channel.type)

--------------------------------------------------------------------------------
H.section("The preset list")
--------------------------------------------------------------------------------

DB:CreatePreset("Second Preset")
MainFrame:RefreshAll()

local visibleRows = 0
for _, row in ipairs(frame.presetList.rows) do
	if row:IsShown() then
		visibleRows = visibleRows + 1
	end
end
H.checkEqual("the list shows every preset", visibleRows, DB:CountPresets())

local targetRow
for _, row in ipairs(frame.presetList.rows) do
	if row:IsShown() and row.presetName == "Second Preset" then
		targetRow = row
	end
end
H.check("the new preset appears in the list", targetRow ~= nil)

targetRow:Click()
local _, nowActive = DB:GetActivePreset()
H.checkEqual("clicking a row makes it active", nowActive, "Second Preset")
H.check("and the editor follows it",
	findRow("header", "eventName").control:GetText()
		== DB:GetActivePreset().header.eventName)

H.popups = {}
frame.presetList.deleteButton:Click()
H.check("delete asks for confirmation rather than acting immediately",
	#H.popups > 0)
H.check("and the preset is still there until confirmed",
	DB:GetPreset("Second Preset") ~= nil)

--------------------------------------------------------------------------------
H.section("Position is remembered")
--------------------------------------------------------------------------------

frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 120, -80)
H.fireScript(frame, "OnDragStop")
local saved = DB:GetSettings().framePoint
H.checkEqual("the dragged position is saved", saved.point, "TOPLEFT")
H.checkEqual("with its offset", saved.x, 120)

--------------------------------------------------------------------------------
H.section("A rejected edit complains on the field")
--------------------------------------------------------------------------------

-- The chat frame is the one the host is running the evening from. A typo in a
-- number box used to put a red line in it, next to the rolls and the room's
-- roleplay, where it either scrolled past unread or pushed something that
-- mattered off the top.
local rollsIndex
for index, tab in ipairs(Fields:GetTabs()) do
	if tab.module == "rolls" then
		rollsIndex = index
	end
end

MainFrame:SelectTab(rollsIndex)

local thresholdRow
for _, row in ipairs(MainFrame.frame.editors.pages[rollsIndex].rows) do
	if row.field.key == "successThreshold" then
		thresholdRow = row
	end
end
H.check("the threshold row is on the page", thresholdRow ~= nil)

local activePreset = DB:GetActivePreset()
local goodValue = activePreset.rolls.successThreshold

H.clearOutput()
thresholdRow.control:SetText("ten")
H.fireScript(thresholdRow.control, "OnEnterPressed")

H.check("a bad number is not reported in the chat frame",
	H.outputText():find("Success at or above", 1, true) == nil, H.outputText())
H.check("it is reported on the box instead",
	(thresholdRow.control.errorMessage or ""):find("Success at or above", 1, true) ~= nil,
	thresholdRow.control.errorMessage)
H.checkEqual("and the value is left alone",
	activePreset.rolls.successThreshold, goodValue)

-- The complaint clears itself; a box left red is a box that looks broken.
H.advance(6)
H.check("the complaint goes away on its own",
	thresholdRow.control.errorMessage == nil)

H.clearOutput()
thresholdRow.control:SetText("15")
H.fireScript(thresholdRow.control, "OnEnterPressed")
H.checkEqual("a good number is written", activePreset.rolls.successThreshold, 15)
H.check("with nothing complained about",
	thresholdRow.control.errorMessage == nil)
H.checkEqual("and nothing said in chat", H.outputText(), "")

--------------------------------------------------------------------------------
H.section("Every field explains itself")
--------------------------------------------------------------------------------

-- A tooltip is the only place a field can say what it means. Enforced rather
-- than encouraged, so a field added later cannot arrive undocumented.
local untipped = {}
for _, tab in ipairs(Fields:GetTabs()) do
	for _, field in ipairs(tab.fields) do
		if not field.tooltip or field.tooltip == "" then
			untipped[#untipped + 1] = tab.module .. "." .. field.key
		end
	end
end
H.check("every field has a tooltip", #untipped == 0, table.concat(untipped, ", "))

local terse = {}
for _, tab in ipairs(Fields:GetTabs()) do
	for _, field in ipairs(tab.fields) do
		if field.tooltip and #field.tooltip < 25 then
			terse[#terse + 1] = tab.module .. "." .. field.key
		end
	end
end
H.check("and says something more than the label already did",
	#terse == 0, table.concat(terse, ", "))

--------------------------------------------------------------------------------
H.section("The window says what it is about to do")
--------------------------------------------------------------------------------

local announcePreset = DB:GetActivePreset()

REH.Announcer:SetChannel(announcePreset, "preview")
H.checkEqual("a preview preset says so on the button",
	MainFrame:DescribeAnnounceAction(announcePreset.channel), "Preview only")

REH.Announcer:SetChannel(announcePreset, "party")
H.checkEqual("and a real channel is named on it",
	MainFrame:DescribeAnnounceAction(announcePreset.channel), "Announce to party chat")

MainFrame:RefreshPreview()
H.checkEqual("which is what the button actually shows",
	frame.announceButton:GetText(), "Announce to party chat")

REH.Announcer:SetChannel(announcePreset, "rw")
MainFrame:RefreshPreview()
H.checkEqual("and it follows the channel", frame.announceButton:GetText(),
	"Announce to raid warning")

-- A section can be switched out of the announcement while keeping its rules,
-- which from the tab strip looks exactly like one that is still in it.
local damageTab, damageIndex
for index, tab in ipairs(Fields:GetTabs()) do
	if tab.module == "damage" then
		damageTab, damageIndex = tab, index
	end
end
H.check("the damage tab exists", damageTab ~= nil)

local damageButton = frame.tabButtons[damageIndex]
H.check("and carries a marker for being left out", damageButton.offDot ~= nil)

announcePreset.moduleEnabled.damage = true
MainFrame:RefreshPreview()
H.check("hidden while the section is announced", damageButton.offDot:IsShown() == false)

announcePreset.moduleEnabled.damage = false
MainFrame:RefreshPreview()
H.check("and shown once it is not", damageButton.offDot:IsShown())

announcePreset.moduleEnabled.damage = true
MainFrame:RefreshPreview()
H.check("and hidden again when it comes back",
	damageButton.offDot:IsShown() == false)

-- The Watcher and Options tabs edit no announceable section, so they have
-- nothing to mark.
local optionsIndex
for index, tab in ipairs(Fields:GetTabs()) do
	if tab.module == "settings" then
		optionsIndex = index
	end
end
H.check("a tab that is not a section has no marker",
	frame.tabButtons[optionsIndex].offDot == nil)

--------------------------------------------------------------------------------
H.section("The way through to the effects window")
--------------------------------------------------------------------------------

local lootIndex
for index, tab in ipairs(Fields:GetTabs()) do
	if tab.module == "loot" then
		lootIndex = index
	end
end

MainFrame:SelectTab(lootIndex)

local effectsRow
for _, row in ipairs(MainFrame.frame.editors.pages[lootIndex].rows) do
	if row.field.key == "effects" then
		effectsRow = row
	end
end
H.check("the loot tab has a button through to the effects window", effectsRow ~= nil)

-- The button says how many effects are behind it, so a host does not have to
-- open the window to find out whether there are any.
local lootPreset = DB:GetActivePreset()
lootPreset.rollEffects = {}
MainFrame:RefreshAll()
H.checkEqual("with no effects it just names the window",
	effectsRow.control:GetText(), "Roll effects...")

lootPreset.rollEffects = { REH.CreateRollEffect(), REH.CreateRollEffect() }
DB:ValidatePreset(lootPreset)
MainFrame:RefreshAll()
H.checkEqual("and counts them when there are some",
	effectsRow.control:GetText(), "Roll effects... (2)")

lootPreset.rollEffects = {}
MainFrame:RefreshAll()

--------------------------------------------------------------------------------
H.section("The window can be dragged out")
--------------------------------------------------------------------------------

-- The sizing rules are arithmetic, so they are checked directly rather than by
-- reading pixels off a mock.
local base = MainFrame:Measure(820, 600)
H.checkEqual("at the default size the preview is what it always was",
	base.previewHeight, 150)

local tall = MainFrame:Measure(820, 900)
H.check("a taller window gives the preview most of the extra",
	tall.previewHeight > base.previewHeight + 150, tall.previewHeight)
H.check("and the editor the rest", tall.topHeight > base.topHeight, tall.topHeight)
H.checkEqual("300 more pixels of height, 180 of them to the preview",
	tall.previewHeight - base.previewHeight, 180)

-- Left unchecked, the share rule would eventually leave no editor at all.
local veryTall = MainFrame:Measure(820, 1200)
H.check("the preview never grows past the editor above it",
	veryTall.previewHeight <= veryTall.topHeight, veryTall.previewHeight)
H.check("so the editor always has room to work in", veryTall.topHeight > 200)

-- The status line lives between the preview and the bottom bar. Laid out
-- without a strip of its own it ends up under the preview, and the host reads
-- half of "You are not in a party."
for _, height in ipairs({ 460, 600, 900, 1200 }) do
	local size = MainFrame:Measure(820, height)
	local previewBottom = height - (44 + size.topHeight + size.previewHeight)
	H.check(("the status line is clear of the preview at %dpx"):format(height),
		previewBottom >= 52, previewBottom)
end

local wide = MainFrame:Measure(1400, 600)
H.checkEqual("extra width goes to the editor, not the preset list",
	wide.editorWidth, 1400 - 190 - 30)
H.checkEqual("and the preview spans the window", wide.previewWidth, 1400 - 16)

-- The layout pass has to survive being run at any size, since the client fires
-- it on every pixel of a drag. The widget mock raises on anything imaginary,
-- so getting through this is the check.
frame:SetSize(1200, 900)
H.check("the window lays out at a dragged size", frame:GetWidth() == 1200)

local editorPage = MainFrame.frame.editors.pages[1]
H.check("the editor pages widen with it",
	editorPage.frame:GetWidth() > 500, editorPage.frame:GetWidth())

frame:SetSize(820, 600)
H.check("and back down again", frame:GetWidth() == 820)

MainFrame:SaveSize()
local savedSize = DB:GetSettings().frameSize
H.checkEqual("the size is remembered", savedSize.width, 820)
H.checkEqual("in both directions", savedSize.height, 600)

frame:SetSize(1000, 700)
MainFrame:SaveSize()
MainFrame:ResetSize()
H.checkEqual("and can be put back to the default width", frame:GetWidth(), 820)
H.checkEqual("and height", frame:GetHeight(), 600)

-- A hand-edited or future-version size must not produce a window that cannot
-- be read or reached.
local settings = DB:GetSettings()
settings.frameSize = { width = 99999, height = -40 }
DB:ValidateSettings(settings)
H.check("an absurd saved width is clamped", settings.frameSize.width <= 1800,
	settings.frameSize.width)
H.check("and a negative height", settings.frameSize.height >= 460,
	settings.frameSize.height)

settings.frameSize = "not a table"
DB:ValidateSettings(settings)
H.checkEqual("a size that is not a size falls back to the default",
	settings.frameSize.width, 820)

H.checkNoLeakedGlobals(H.ALLOWED_GLOBALS)

H.finish()
