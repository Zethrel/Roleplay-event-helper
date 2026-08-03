local ADDON_NAME, REH = ...

local UI = REH.UI
local Preview = {}
UI.Preview = Preview

-- The live preview pane: exactly what will be sent, message by message, with an
-- estimate of how long the announcement will take.
--
-- This is the centrepiece of the window. A host should never have to press
-- Announce to find out what their rules look like in chat.
--
-- It is deliberately quiet about byte counts. Every message used to carry one,
-- which meant half the ink in the pane went on a number that only matters when
-- it is close to the limit. Now a count appears when it is worth knowing about
-- and nowhere else, so the pane reads like the chat it is predicting.

-- Where a message stops being comfortable. The hard limit is 255; anything past
-- this is close enough that a host adding one more clause should be told.
local WARN_BYTES = 200

--- Build the preview text for a preset. Pure, so it can be tested directly.
--- Returns the body text, the message count, the estimated seconds and how many
--- of those messages are separators.
function Preview:BuildText(preset)
	local messages, _, _, meta = REH.Formatter:BuildMessages(preset)
	local settings = REH.Database:GetSettings()
	local seconds = math.max(0, (#messages - 1)) * settings.sendDelay

	local lines, separators = {}, 0

	for index, message in ipairs(messages) do
		local info = meta and meta[index] or {}

		if info.module == "separator" then
			-- A separator carries no rule, so it is dimmed to the point of
			-- being scenery: it is still counted, still costs a message, and
			-- the eye can skip it while reading the rules.
			separators = separators + 1
			lines[#lines + 1] = ("|cff505050%2d. %s|r"):format(index, message)

		else
			local tail = ""

			if info.split then
				-- A rule too long for one message arrives as two, which is
				-- worth knowing before an event rather than after.
				tail = (" |cffff8080(%d, split)|r"):format(#message)
			elseif #message > WARN_BYTES then
				tail = (" |cffffd100(%d)|r"):format(#message)
			end

			lines[#lines + 1] = ("|cff808080%2d.|r %s%s"):format(index, message, tail)
		end
	end

	if #messages == 0 then
		lines[1] = "|cffff6060Nothing to announce -- every module is disabled or empty.|r"
	end

	return table.concat(lines, "\n"), #messages, seconds, separators
end

function Preview:BuildSummary(messageCount, seconds, separators)
	if messageCount == 0 then
		return "no messages"
	end

	if messageCount == 1 then
		return "1 message"
	end

	-- Separators are called out because they are the one part of the count a
	-- host can delete without losing a rule: five of them is five messages and
	-- three and a half seconds of held channel spent on dashes.
	local dashes = ""
	if separators and separators > 1 then
		dashes = (" (%d separators)"):format(separators)
	end

	return ("%d messages%s, about %.0f seconds"):format(messageCount, dashes, seconds)
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

	--- Grow or shrink with the window. The whole point of a resizable window is
	--- that this pane gets bigger, so it is the piece that has to follow.
	function frame:Resize(newWidth, newHeight)
		self:SetSize(newWidth, newHeight)
		UI.ResizeScrollArea(self.scrollFrame, newWidth - 34, newHeight - 30)
		self.bodyText:SetWidth(newWidth - 40)

		-- Rewrapping the text changes how tall it is, so the scroll child has to
		-- be measured again or the last lines become unreachable.
		if self.content and self.bodyText.GetStringHeight then
			self.content:SetHeight(math.max(self.bodyText:GetStringHeight() or 0, 1))
		end
	end

	function frame:Refresh(preset)
		if not preset then
			return
		end

		local text, count, seconds, separators = Preview:BuildText(preset)
		self.bodyText:SetText(text)
		self.summaryText:SetText(Preview:BuildSummary(count, seconds, separators))

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
