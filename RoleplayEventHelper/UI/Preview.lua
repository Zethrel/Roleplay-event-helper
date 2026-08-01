local ADDON_NAME, REH = ...

local UI = REH.UI
local Preview = {}
UI.Preview = Preview

-- The live preview pane: exactly what will be sent, message by message, with
-- the byte count and an estimate of how long the announcement will take.
--
-- This is the centrepiece of the window. A host should never have to press
-- Announce to find out what their rules look like in chat.

--- Build the preview text for a preset. Pure, so it can be tested directly.
--- Returns the body text, the message count, and the estimated seconds.
function Preview:BuildText(preset)
	local messages = REH.Formatter:BuildMessages(preset)
	local settings = REH.Database:GetSettings()
	local seconds = math.max(0, (#messages - 1)) * settings.sendDelay

	local lines = {}
	for index, message in ipairs(messages) do
		lines[#lines + 1] = ("|cff808080%2d.|r %s |cff606060(%d)|r"):format(
			index, message, #message)
	end

	if #messages == 0 then
		lines[1] = "|cffff6060Nothing to announce -- every module is disabled or empty.|r"
	end

	return table.concat(lines, "\n"), #messages, seconds
end

function Preview:BuildSummary(messageCount, seconds)
	if messageCount == 0 then
		return "no messages"
	end

	if messageCount == 1 then
		return "1 message"
	end

	return ("%d messages, about %.0f seconds"):format(messageCount, seconds)
end

function Preview:Create(parent, width, height)
	local frame = UI.CreatePanel(parent)
	frame:SetSize(width, height)

	local heading = UI.CreateLabel(frame, "Preview", "GameFontNormalSmall")
	heading:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6)

	local summary = UI.CreateLabel(frame, "", "GameFontDisableSmall")
	summary:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -6)
	summary:SetJustifyH("RIGHT")

	local scroll, content = UI.CreateScrollArea(frame, width - 34, height - 30)
	scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -24)

	local body = UI.CreateLabel(content, "", "ChatFontNormal")
	body:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
	body:SetWidth(width - 40)
	body:SetJustifyH("LEFT")
	body:SetJustifyV("TOP")

	frame.summaryText = summary
	frame.bodyText = body
	frame.content = content
	frame.scrollFrame = scroll

	function frame:Refresh(preset)
		if not preset then
			return
		end

		local text, count, seconds = Preview:BuildText(preset)
		self.bodyText:SetText(text)
		self.summaryText:SetText(Preview:BuildSummary(count, seconds))

		-- Same reason as the roll log: without this the scroll child stays at
		-- its original height and a long preview cannot be scrolled.
		if self.content and self.bodyText.GetStringHeight then
			self.content:SetHeight(math.max(self.bodyText:GetStringHeight() or 0, 1))
		end
		if self.scrollFrame and self.scrollFrame.UpdateScrollChildRect then
			self.scrollFrame:UpdateScrollChildRect()
		end
	end

	return frame
end
