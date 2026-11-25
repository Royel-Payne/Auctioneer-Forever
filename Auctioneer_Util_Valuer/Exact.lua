if not Auctioneer then return end

-- Exact matches for random-suffix items ("Fortified Cloak of the Monkey").
--
-- Blizzard's sell list asks for an item with its suffix cleared, so it lists every
-- variant together, and picks the cheapest of them all as the price: a Monkey cloak
-- gets priced like the cheapest "of Spirit" one. When such an item is placed, ask the
-- auction house once for that exact variant (the query the Buy tab sends when you
-- click a variant), list those auctions here, and set the price to the cheapest of
-- them, unless you already typed your own. With none listed, use the variant's own
-- price history. Click a row to use its price. Posting is still Blizzard's button.

local _, private = ...
local Module = private and private.Valuer
if not Module then return end

local ROWS, ROW_HEIGHT = 8, 16
local LABEL_FONT = "Fonts\\FRIZQT__.TTF"
local NUMBER_FONT = "Fonts\\ARIALN.TTF"

local TIME_LEFT = {"< 30 min", "30 min - 2 h", "2 - 12 h", "12 - 48 h"}

-- The name in an item link, without brackets.
function Module.LinkName(link)
	return link and link:match("|h%[(.-)%]|h") or nil
end

-- Item keys equal in every field.
local function sameKey(a, b)
	return a and b and a.itemID == b.itemID and a.itemLevel == b.itemLevel and
		a.itemSuffix == b.itemSuffix and (a.battlePetSpeciesID or 0) == (b.battlePetSpeciesID or 0)
end
Module.SameKey = sameKey

-- Auction house buyouts are whole silver: round a price from history to one.
function Module.WholeSilver(copper)
	return math.max(100, math.floor(copper / 100 + 0.5) * 100)
end

-- Search results as list rows for the item named `name`, cheapest buyout per item first
-- (bid-only auctions last). A result without a link is kept: it was asked for by key.
function Module.ExactRows(results, name)
	local rows = {}
	for _, result in ipairs(results) do
		local resultName = Module.LinkName(result.itemLink)
		if not resultName or resultName == name then
			local quantity = math.max(result.quantity or 1, 1)
			tinsert(rows, {
				buyout = result.buyoutAmount and math.floor(result.buyoutAmount / quantity),
				bid = result.bidAmount or result.minBid,
				quantity = quantity,
				timeLeft = result.timeLeft,
				mine = result.containsOwnerItem,
			})
		end
	end
	table.sort(rows, function(a, b)
		if a.buyout and b.buyout then return a.buyout < b.buyout end
		return a.buyout ~= nil and b.buyout == nil
	end)
	return rows
end

-- The price to set, and why, or nil to leave the price alone. `typed` is whether the
-- price in the sell frame is one you entered rather than Blizzard's automatic one.
function Module.ExactPrice(rows, historyPrice, typed)
	if typed then
		return nil, "typed"
	end
	for _, row in ipairs(rows) do
		if row.buyout and row.buyout > 0 then
			return row.buyout, "listing"
		end
	end
	if historyPrice and historyPrice > 0 then
		return Module.WholeSilver(historyPrice), "history"
	end
	return nil, "none"
end

-- The variant's best price from its statistics, for when none is listed.
local function historyPrice(item)
	local best
	for _, stat in ipairs(Auctioneer:Statistics(item:ID())) do
		local price, number = stat:Best()
		if price and number and number > 0 and price > 0 then
			best = best or price
		end
	end
	return best
end

local function itemSellFrame()
	return AuctionHouseFrame and AuctionHouseFrame.ItemSellFrame
end

-- Called when an item is placed in the sell slot.
function Module:ExactItemLoaded(current, itemType, listKey)
	self.exact = nil
	self:ExactHide()
	if not Auctioneer:Setting("exactMatch") then
		return
	end
	if itemType == AuctionHouseSearchContext.SellCommodities or not current.name or not listKey or listKey.itemSuffix == 0 then
		return
	end
	local key = current.item.itemKey
	self.exact = {
		key = key,
		name = current.name,
		item = current.item,
		state = "searching",
		typed = false,
	}
	local sorts = {{sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false}}
	C_AuctionHouse.SendSearchQuery(key, sorts, true)
	self:ExactRender()
end

-- You typed in the price boxes (not Blizzard or Auctioneer setting them).
function Module:ExactTyped()
	if self.exact then
		self.exact.typed = true
	end
end

function Module:ExactSetPrice(price)
	local sellFrame = itemSellFrame()
	if not sellFrame or not price then return end
	sellFrame.PriceInput:SetAmount(price)
	sellFrame:UpdatePostState()
end

function Module:ExactResults(itemKey)
	local exact = self.exact
	if not exact or not sameKey(itemKey, exact.key) then
		return
	end
	local results = {}
	for i = 1, C_AuctionHouse.GetNumItemSearchResults(exact.key) do
		local result = C_AuctionHouse.GetItemSearchResultInfo(exact.key, i)
		if result then tinsert(results, result) end
	end
	exact.rows = Module.ExactRows(results, exact.name)
	exact.full = C_AuctionHouse.HasFullItemSearchResults(exact.key)

	if exact.state == "searching" then
		local sellFrame = itemSellFrame()
		if sellFrame and sellFrame:IsShown() then
			local price, why = Module.ExactPrice(exact.rows, historyPrice(exact.item),
				exact.typed)
			exact.state = why
			if price then
				self:ExactSetPrice(price)
			end
		end
	end
	self:ExactRender()
end

-- UI: a list under the Valuer's details.
function Module:ExactCreate(parent, detail)
	local list = CreateFrame("Frame", nil, parent)
	list:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 8)
	list:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -8, 8)
	list:SetHeight(64 + ROWS * ROW_HEIGHT)
	list:Hide()
	self.exactList = list
	self.exactDetail = detail
	self.exactParent = parent

	local rule = list:CreateTexture(nil, "ARTWORK")
	rule:SetTexture("Interface\\Buttons\\WHITE8X8")
	rule:SetVertexColor(1, 0.82, 0, 0.35)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
	rule:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)

	local title = list:CreateFontString(nil, "OVERLAY")
	title:SetFont(LABEL_FONT, 11, "")
	title:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -6)
	title:SetTextColor(1, 0.82, 0)
	title:SetText("On sale now, this exact item")

	local status = list:CreateFontString(nil, "OVERLAY")
	status:SetFont(LABEL_FONT, 10, "")
	status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	status:SetPoint("RIGHT", list, "RIGHT", 0, 0)
	status:SetJustifyH("LEFT")
	status:SetWordWrap(true)
	status:SetMaxLines(3)
	list.status = status

	list.offset = 0
	list.rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, list)
		row:SetHeight(ROW_HEIGHT)
		-- Rows follow the status text, which may take two lines.
		if i == 1 then
			row:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -4)
		else
			row:SetPoint("TOPLEFT", list.rows[i - 1], "BOTTOMLEFT", 0, 0)
		end
		row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

		row.price = row:CreateFontString(nil, "OVERLAY")
		row.price:SetFont(NUMBER_FONT, 12, "OUTLINE")
		row.price:SetPoint("LEFT", row, "LEFT", 4, 0)

		row.note = row:CreateFontString(nil, "OVERLAY")
		row.note:SetFont(LABEL_FONT, 10, "")
		row.note:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		row.note:SetTextColor(0.7, 0.7, 0.7)

		row:SetScript("OnClick", function(button)
			if button.data and button.data.buyout then
				Module.exact.state = "clicked"
				Module:ExactSetPrice(button.data.buyout)
				Module:ExactRender()
			end
		end)
		row:SetScript("OnEnter", function(button)
			if not button.data then return end
			GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
			GameTooltip:SetText("Use this price")
			GameTooltip:AddLine("Sets your buyout to this auction's price per item.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		list.rows[i] = row
	end

	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		local exact = Module.exact
		local count = exact and exact.rows and #exact.rows or 0
		list.offset = math.max(0, math.min(list.offset - delta, count - ROWS))
		Module:ExactRender()
	end)
end

local function money(copper)
	return GetMoneyString and GetMoneyString(copper, true) or tostring(copper)
end

local STATUS = {
	searching = "Searching the auction house for this exact item...",
	listing = "|cff40ff40Price set to the cheapest of these.|r\n|cff999999Blizzard's list on the left mixes in every variant.|r",
	clicked = "|cff40ff40Price set to the row you clicked.|r",
	history = "|cffff9933None listed: price set from this item's price history.|r",
	typed = "Your own price was kept. Click a row to use its price.",
	none = "|cffff9933None listed and no price history: Blizzard's price is from other variants, check it.|r",
}

function Module:ExactRender()
	local list, exact = self.exactList, self.exact
	if not list then return end
	if not exact then
		self:ExactHide()
		return
	end

	list:Show()
	self.exactDetail:SetPoint("BOTTOMRIGHT", self.exactParent, "BOTTOMRIGHT", -5, list:GetHeight() + 10)

	local rows = exact.rows or {}
	local status = STATUS[exact.state] or ""
	if exact.state ~= "searching" and #rows > 0 then
		status = format("%d listed. %s", #rows, status)
		if exact.full == false then
			status = status.." (first results)"
		end
	end
	list.status:SetText(status)

	list.offset = math.max(0, math.min(list.offset, #rows - ROWS))
	for i, row in ipairs(list.rows) do
		local data = rows[list.offset + i]
		row.data = data
		if data then
			row.price:SetText(data.buyout and money(data.buyout) or ("bid "..money(data.bid or 0)))
			local note = TIME_LEFT[(data.timeLeft or 0) + 1] or ""
			if data.quantity > 1 then note = format("x%d  %s", data.quantity, note) end
			if data.mine then note = "|cff40c0ffyours|r  "..note end
			row.note:SetText(note)
			row:Show()
		else
			row:Hide()
		end
	end
end

function Module:ExactHide()
	if self.exactList then
		self.exactList:Hide()
		self.exactDetail:SetPoint("BOTTOMRIGHT", self.exactParent, "BOTTOMRIGHT", -5, 5)
	end
end

-- Wire up: search results, and typing in the sell frame's price boxes.
function Module:ExactBoot()
	local events = CreateFrame("Frame")
	events:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
	events:RegisterEvent("ITEM_SEARCH_RESULTS_ADDED")
	events:SetScript("OnEvent", function(_, _, itemKey)
		Module:ExactResults(itemKey)
	end)

	local sellFrame = itemSellFrame()
	local moneyInput = sellFrame and sellFrame.PriceInput and sellFrame.PriceInput.MoneyInputFrame
	for _, boxName in ipairs({"GoldBox", "SilverBox", "CopperBox"}) do
		local box = moneyInput and moneyInput[boxName]
		if box and box.HookScript then
			box:HookScript("OnTextChanged", function(_, userInput)
				if userInput then Module:ExactTyped() end
			end)
		end
	end
end
