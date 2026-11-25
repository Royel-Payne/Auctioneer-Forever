if not Auctioneer then return end

-- Create a new Auctioneer module.
local Module = Auctioneer:Module("Util:DealFinder")
local Const = Auctioneer.Const()

local resultsFrame

-- Hook our methods
function Module:Boot(hook)
	hook(Const.ScannerItemsCompleted, Module.ScannerItemsCompleted)
	hook(Const.DisplayModeChanged, Module.DisplayModeChanged)
	hook(Const.ItemKeyInfoFound, Module.ItemKeyInfoFound)

	Module:CreateResults()
end

-- Rows can be shown before their item key info arrives; redraw when it does.
-- Info arrives in bursts (one event per item), so one redraw covers a burst.
local REDRAW_DELAY = 0.1
function Module:ItemKeyInfoFound()
	if self.redrawPending then
		return
	end
	self.redrawPending = true
	C_Timer.After(REDRAW_DELAY, function()
		self.redrawPending = false
		if self.deals and resultsFrame:IsShown() then
			self:Display()
		end
	end)
end

if not AuctioneerUtilDealFinderData then
	AuctioneerUtilDealFinderData = {}
end

function Module:DisplayModeChanged(displayMode)
	if displayMode ~= AuctionHouseFrameDisplayMode.Buy and
	displayMode ~= AuctionHouseFrameDisplayMode.ItemBuy and
	displayMode ~= AuctionHouseFrameDisplayMode.CommoditiesBuy then
		resultsFrame:Hide()
	end
end

-- What counts as a deal. A listing is a deal when it is well below what a vendor
-- pays, or well below what the item usually sells for, and buying it makes real money:
--   vendor deal: profit = vendor price - listing price
--   market deal: profit = usual price, less your undercut, after the 5% auction cut
--                - listing price
-- "Usual price" is the median of past scans (not this one), and needs enough of them.
-- The minimum discount and profit are settings (dealsMinDiscount, dealsMinProfitCopper),
-- applied when the list is shown, so changing them needs no new scan. So is the undercut
-- (undercutCopper): reselling, you would post that much under the usual price.
local AUCTION_CUT = 0.05
local MIN_PROFIT = 100        -- default for Evaluate: 1 silver
local MIN_DATA_POINTS = 6     -- scans of an item before its usual price is trusted

-- Usual price of an item: the median of the statistic with the most data points.
local function usualPrice(stats, options)
	local price, points
	for _, stat in ipairs(stats) do
		local n = stat:Number()
		local median = stat:Percentile(50, options)
		if median and n and n >= MIN_DATA_POINTS and (not points or n > points) then
			price, points = median, n
		end
	end
	return price, points
end

-- The deal a listing offers, or nil. Returns kind, profit, discount (0-1), points.
-- minProfit in copper, default 1 silver. undercut: copper below `usual` you would resell at.
function Module.Evaluate(itemPrice, vendorPrice, usual, points, minProfit, undercut)
	minProfit = math.max(1, minProfit or MIN_PROFIT)
	local best
	if vendorPrice and vendorPrice > 0 then
		local profit = vendorPrice - itemPrice
		if profit >= minProfit then
			best = {"vendor", profit, profit / vendorPrice, 0}
		end
	end
	if usual and usual > 0 then
		local resale = math.max(0, usual - math.max(0, undercut or 0))
		local profit = math.floor(resale * (1 - AUCTION_CUT)) - itemPrice
		if profit >= minProfit and (not best or profit > best[2]) then
			best = {"arbitrage", profit, (usual - itemPrice) / usual, points}
		end
	end
	if best then
		return unpack(best)
	end
end

-- This is where we spring into action to find some deals
-- After a scan the player started, show the deals. After the auto-scan on
-- opening, only update them: the panel stays shut unless it is already open.
function Module:ScannerItemsCompleted(items, auto)
	local deals = {}
	local options = {
		weighted = true,
		before = Auctioneer.Timeslice() - 1,
	}
	for _, item in ipairs(items) do
		local usual, points = usualPrice(Auctioneer:Statistics(item.id), options)
		local itemPrice = item.itemData.minPrice
		-- Keep every profitable listing; Display applies the minimum profit setting.
		local kind, profit, discount, dataPoints = Module.Evaluate(itemPrice, item:VendorPrice(), usual, points, 1)
		if kind then
			-- item, price, kind, profit, data points, discount; vendor and usual price for
			-- evaluating again with the undercut when shown
			tinsert(deals, {item, itemPrice, kind, profit, dataPoints, discount, item:VendorPrice(), usual, points})
		end
	end
	table.sort(deals, function(a, b) return a[4] > b[4] end)
	self.deals = deals

	if (auto or not Auctioneer:Setting("dealsOpenAfterScan")) and not resultsFrame:IsShown() then
		return
	end
	resultsFrame.offset = 0
	self:Display()
end

function Module:Display()
	if not self.deals or #self.deals < 1 then
		resultsFrame:Hide()
		return
	end

	-- The slider sets the minimum discount below the vendor or usual price.
	local percent = (Auctioneer:Setting("dealsMinDiscount") or 25) / 100

	local minProfit = Auctioneer:Setting("dealsMinProfitCopper") or 100
	local undercut = Auctioneer:Setting("undercutCopper") or 0
	local list = {}
	for _, deal in ipairs(self.deals) do
		local item, itemPrice = deal[1], deal[2]
		local kind, profit, discount, points = deal[3], deal[4], deal[6], deal[5]
		if undercut > 0 then
			kind, profit, discount, points = Module.Evaluate(itemPrice, deal[7], deal[8], deal[9], 1, undercut)
		end
		if kind and discount >= percent and profit >= minProfit then
			tinsert(list, {item, itemPrice, kind, profit, points, discount})
		end
	end
	if undercut > 0 then
		table.sort(list, function(a, b) return a[4] > b[4] end)
	end

	-- As many rows as fit show at once; the first shown is resultsFrame.offset (0 = top).
	resultsFrame:Show()
	local rows = resultsFrame:RowsThatFit()
	local offset = math.max(0, math.min(resultsFrame.offset or 0, #list - rows))
	resultsFrame.offset = offset
	resultsFrame.scroll:Set(#list, rows, offset)

	for i, line in ipairs(resultsFrame.lines) do
		local deal = i <= rows and list[i + offset]
		if deal then
			line:SetDeal(deal)
		else
			line:Reset()
		end
	end
	resultsFrame:Show()
end

function Module:CreateResults()
	resultsFrame = Auctioneer.GUI:Panel("AuctioneerDealFinderFrame", "Deal finder", "browse", 34)
	resultsFrame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", -2, 0)
	resultsFrame:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT", -2, 0)
	resultsFrame:SetWidth(430)

	local inset = resultsFrame.Inset

	local function redisplay()
		self:Display()
	end

	-- The auction house lists' own scroll bar, and the mouse wheel anywhere on the list.
	resultsFrame.offset = 0
	local scroll = Auctioneer.GUI:ScrollBar(inset, function(offset)
		resultsFrame.offset = offset
		redisplay()
	end)
	scroll.frame:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -5, -6)
	scroll.frame:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -5, 6)
	resultsFrame.scroll = scroll

	inset:EnableMouse(true)
	inset:SetScript("OnMouseWheel", function(_, delta)
		resultsFrame.offset = math.max(0, (resultsFrame.offset or 0) - delta)
		redisplay()
	end)

	-- Minimum discount: Blizzard's stepper slider, as on the settings page.
	local percentLabel = resultsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	percentLabel:SetPoint("TOPLEFT", inset, "BOTTOMLEFT", 8, -8)
	percentLabel:SetText("Minimum discount")

	local percent = CreateFrame("Frame", nil, resultsFrame, "MinimalSliderWithSteppersTemplate")
	percent:SetSize(220, 20)
	percent:SetPoint("LEFT", percentLabel, "RIGHT", 12, 0)
	percent:Init(Auctioneer:Setting("dealsMinDiscount"), 5, 90, (90 - 5) / 5,
		{[MinimalSliderWithSteppersMixin.Label.Right] = function(value)
			return format("%d%%", floor(value + 0.5))
		end})
	percent:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		value = floor(value + 0.5)
		if value ~= Auctioneer:Setting("dealsMinDiscount") then
			Auctioneer:SetSetting("dealsMinDiscount", value)
			resultsFrame.offset = 0
			redisplay()
		end
	end, resultsFrame)
	resultsFrame.percent = percent
	-- The settings page changes the same value: pick it up whenever the panel shows.
	resultsFrame:HookScript("OnShow", function()
		percent:SetValue(Auctioneer:Setting("dealsMinDiscount"))
	end)
	local function percentTooltip(owner)
		GameTooltip:SetOwner(owner, "ANCHOR_TOP")
		GameTooltip:SetText("Minimum discount")
		GameTooltip:AddLine(format("Show listings at least %d%% below what a vendor pays, or below the item's usual auction price.",
			Auctioneer:Setting("dealsMinDiscount")), 1, 1, 1, true)
		GameTooltip:Show()
	end
	if percent.Slider then
		percent.Slider:HookScript("OnEnter", percentTooltip)
		percent.Slider:HookScript("OnLeave", GameTooltip_Hide)
	end

	-- The list, laid out like the auction house's Browse list: a header row, then rows
	-- with the item's icon and name, what kind of deal it is, and the profit.
	local ROW_HEIGHT, HEADER_HEIGHT = 20, 20
	local PROFIT_WIDTH, KIND_WIDTH = 120, 56
	local LEFT, RIGHT = 6, -22 -- room on the right for the scroll bar

	local header = CreateFrame("Frame", nil, inset)
	header:SetPoint("TOPLEFT", inset, "TOPLEFT", LEFT - 2, -4)
	header:SetPoint("RIGHT", inset, "RIGHT", RIGHT + 2, 0)
	header:SetHeight(HEADER_HEIGHT)
	local headerBg = header:CreateTexture(nil, "BACKGROUND")
	headerBg:SetColorTexture(0, 0, 0, 0.45)
	headerBg:SetAllPoints(header)
	local headerRule = header:CreateTexture(nil, "ARTWORK")
	headerRule:SetColorTexture(1, 0.82, 0, 0.35)
	headerRule:SetHeight(1)
	headerRule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
	headerRule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
	local function headerText(text, justify)
		local label = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetJustifyH(justify)
		label:SetText(text)
		return label
	end
	local nameHeader = headerText("Name", "LEFT")
	nameHeader:SetPoint("LEFT", header, "LEFT", 6, 0)
	local profitHeader = headerText("Profit", "RIGHT")
	profitHeader:SetPoint("RIGHT", header, "RIGHT", -4, 0)
	local kindHeader = headerText("Deal", "LEFT")
	kindHeader:SetPoint("RIGHT", header, "RIGHT", -PROFIT_WIDTH - KIND_WIDTH + 30, 0)
	kindHeader:SetWidth(KIND_WIDTH)
	resultsFrame.header = header

	local function lineReset(line)
		line.item, line.deal = nil, nil
		line.icon:Hide()
		line.name:SetText("")
		line.kind:SetText("")
		line.money:Set()
		line:Hide()
	end

	local KIND = {vendor = "Vendor", arbitrage = "Resell"}
	local function lineDeal(line, deal)
		local item, _, kind, profit = unpack(deal)
		local info = item:Info()
		line.item, line.deal = item, deal
		line.icon:SetTexture(info.icon)
		line.icon:SetShown(info.icon ~= nil)
		line.name:SetText("|c"..info.color..info.name.."|r")
		line.kind:SetText(KIND[kind] or "")
		line.money:Set(profit)
		line:Show()
	end

	local function lineClick(self)
		local item = self.item
		if not item then
			return
		end

		self.clickItemData = item.itemData
		AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
		C_AuctionHouse.GetItemKeyInfo(item.itemKey)
		C_Timer.After(0.1, function()
			if self.clickItemData ~= item.itemData then
				return
			end
			AuctionHouseFrame.BrowseResultsFrame.ItemList:SetSelectedEntry(self.clickItemData)
			self.clickItemData = nil
		end)
	end

	-- Hovering a row shows the item and the deal: what it costs and why it is one.
	local function lineEnter(line)
		local deal = line.deal
		if not deal then return end
		local item, price, kind, profit, points, discount = unpack(deal)
		local info = item:Info()
		GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
		if info.link then
			GameTooltip:SetHyperlink(info.link)
		else
			GameTooltip:SetItemByID(item:ID())
		end
		GameTooltip:AddLine(" ")
		local money = function(copper) return GetMoneyString(copper, true) end
		GameTooltip:AddDoubleLine("Listed at", money(price), 1, 0.82, 0, 1, 1, 1)
		if kind == "vendor" then
			GameTooltip:AddDoubleLine("Sell to a vendor for", money(price + profit), 1, 0.82, 0, 1, 1, 1)
		else
			GameTooltip:AddDoubleLine(format("Usual price (%d scans)", points or 0),
				money(math.floor(price / math.max(0.01, 1 - discount) + 0.5)), 1, 0.82, 0, 1, 1, 1)
		end
		GameTooltip:AddDoubleLine("Profit", money(profit), 1, 0.82, 0, 0.25, 1, 0.25)
		GameTooltip:AddLine("Click to find it on the Buy tab.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end

	local lines = {}
	local function makeLine(i)
		local line = CreateFrame("Button", nil, inset)
		line:SetHeight(ROW_HEIGHT)
		line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 2, -(i - 1) * ROW_HEIGHT - 2)
		line:SetPoint("RIGHT", header, "RIGHT", -2, 0)
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("auctionhouse-ui-row-highlight") then
			line:SetHighlightAtlas("auctionhouse-ui-row-highlight", "ADD")
		else
			line:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		end

		line.Reset = lineReset
		line.SetDeal = lineDeal
		line:SetScript("OnClick", lineClick)
		line:SetScript("OnEnter", lineEnter)
		line:SetScript("OnLeave", GameTooltip_Hide)

		local icon = line:CreateTexture(nil, "ARTWORK")
		icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
		icon:SetPoint("LEFT", line, "LEFT", 4, 0)
		line.icon = icon

		local money = Auctioneer.GUI:MoneyView(line)
		local moneyFrame = money:Frame()
		moneyFrame:SetPoint("RIGHT", line, "RIGHT", -2, 0)
		line.money = money

		local kind = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		kind:SetPoint("RIGHT", line, "RIGHT", -PROFIT_WIDTH - KIND_WIDTH + 28, 0)
		kind:SetWidth(KIND_WIDTH)
		kind:SetJustifyH("LEFT")
		kind:SetTextColor(0.7, 0.7, 0.7)
		line.kind = kind

		local name = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
		name:SetPoint("RIGHT", kind, "LEFT", -6, 0)
		name:SetJustifyH("LEFT")
		name:SetWordWrap(false)
		line.name = name

		line:Reset()
		lines[i] = line
		return line
	end

	-- How many rows fit in the inset below the header; rows are made as needed.
	function resultsFrame:RowsThatFit()
		local height = (inset:GetHeight() or 0) - HEADER_HEIGHT - 10
		local count = math.max(1, math.floor(height / ROW_HEIGHT))
		for i = #lines + 1, count do
			makeLine(i)
		end
		return count
	end
	resultsFrame.lines = lines

	scroll.frame:ClearAllPoints()
	scroll.frame:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -5, -HEADER_HEIGHT - 8)
	scroll.frame:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -5, 6)

	resultsFrame:Hide()
end
