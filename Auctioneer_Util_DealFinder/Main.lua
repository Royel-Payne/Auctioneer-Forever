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
--   market deal: profit = usual price after the 5% auction cut - listing price
-- "Usual price" is the median of past scans (not this one), and needs enough of them.
local AUCTION_CUT = 0.05
local MIN_PROFIT = 100        -- 1 silver: below this a "deal" is noise
local MIN_DATA_POINTS = 6     -- scans of an item before its usual price is trusted
local DEFAULT_DISCOUNT = 25   -- slider default, percent below vendor or usual price

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
function Module.Evaluate(itemPrice, vendorPrice, usual, points)
	local best
	if vendorPrice and vendorPrice > 0 then
		local profit = vendorPrice - itemPrice
		if profit >= MIN_PROFIT then
			best = {"vendor", profit, profit / vendorPrice, 0}
		end
	end
	if usual and usual > 0 then
		local profit = math.floor(usual * (1 - AUCTION_CUT)) - itemPrice
		if profit >= MIN_PROFIT and (not best or profit > best[2]) then
			best = {"arbitrage", profit, (usual - itemPrice) / usual, points}
		end
	end
	if best then
		return unpack(best)
	end
end

-- This is where we spring into action to find some deals
function Module:ScannerItemsCompleted(items)
	local deals = {}
	local options = {
		weighted = true,
		before = Auctioneer.Timeslice() - 1,
	}
	for _, item in ipairs(items) do
		local usual, points = usualPrice(Auctioneer:Statistics(item.id), options)
		local itemPrice = item.itemData.minPrice
		local kind, profit, discount, dataPoints = Module.Evaluate(itemPrice, item:VendorPrice(), usual, points)
		if kind then
			-- item, price, kind, profit, data points, discount
			tinsert(deals, {item, itemPrice, kind, profit, dataPoints, discount})
		end
	end
	table.sort(deals, function(a, b) return a[4] > b[4] end)
	self.deals = deals

	resultsFrame.scroll:SetValue(1)
	self:Display()
end

function Module:Display()
	if not self.deals or #self.deals < 1 then
		resultsFrame:Hide()
		return
	end

	-- The slider sets the minimum discount below the vendor or usual price.
	local percent = floor(resultsFrame.percent:GetValue() + 0.5) / 100

	local list = {}
	for _, deal in ipairs(self.deals) do
		if deal[6] >= percent then
			tinsert(list, deal)
		end
	end

	local scroll = resultsFrame.scroll
	if #list > 35 then
		local limit = #list - 34
		scroll:SetMinMaxValues(1, limit)
		if scroll:GetValue() > limit then
			scroll:SetValue(limit)
		end
		scroll:Enable()
		scroll:Show()
	else
		scroll:SetValue(1)
		scroll:Disable()
		scroll:Hide()
	end

	local offset = floor(resultsFrame.scroll:GetValue() + 0.5) -1
	resultsFrame.percentText:SetText(floor(percent*100).."% off or more")

	local lines = {}
	for i = 1,35 do
		local line = resultsFrame.lines[i]
		local pos = i + offset
		local deal = list[pos]
		line:Reset()

		if deal then
			local item, itemPrice, dealType, margin = unpack(deal)
			local name, link, color

			local info = item:Info()

			line.item = item
			line.name:SetText("|c"..info.color..info.name.."|r")
			line:SetMoney(margin)
			if dealType == "vendor" then
				line:SetVendor(true)
			end
		end
	end

	resultsFrame:Show()
end

function Module:CreateResults()
	resultsFrame = CreateFrame("Frame", "AuctioneerDealFinderFrame", AuctionHouseFrame, "SimplePanelTemplate")
	resultsFrame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", -2, -20)
	resultsFrame:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT", -2, 5)
	resultsFrame:SetWidth(430)

	local inset = resultsFrame.Inset

	local close = CreateFrame("Button", nil, resultsFrame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", resultsFrame, "TOPRIGHT")
	close:SetWidth(32)
	close:SetHeight(32)
	resultsFrame.close = close

	local title = resultsFrame:CreateFontString(nil, "OVERLAY")
	title:SetPoint("BOTTOM", inset, "TOP", 0, 3)
	title:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	title:SetJustifyH("LEFT")
	title:SetTextColor(1, 0.8, 0)
	title:SetText("Deal finder")

	local bg = inset.Bg
	bg:SetVertTile(false)
	bg:SetHorizTile(false)
	bg:SetAtlas("auctionhouse-background-buy-commodities-market", true)

	local function redisplay()
		self:Display()
	end

	local function wheelValue(slider)
		return function(_, delta)
			if slider:IsEnabled() then
				local value = slider:GetValue() - delta
				local _, max = slider:GetMinMaxValues()
				if value >= -100 and value <= max then
					slider:SetValue(value)
				end
			end
		end
	end

	local scroll = CreateFrame("Slider", "AuctioneerDealFinderScroll", inset, "OptionsSliderTemplate")
	scroll:SetOrientation("VERTICAL")
	scroll:SetPoint("TOPRIGHT", inset, "TOPRIGHT")
	scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT")
	scroll:SetWidth(16)
	scroll:SetMinMaxValues(1, 1000)
	scroll:SetValue(0)
	scroll:SetValueStep(1)
	scroll:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
	scroll:SetScript("OnValueChanged", redisplay)
	scroll:Disable()
	scroll:Hide()

	inset:EnableMouse(true)
	inset:SetScript("OnMouseWheel", wheelValue(scroll))

	local scrollName = scroll:GetName()
	_G[scrollName.."Low"]:SetText("")
	_G[scrollName.."High"]:SetText("")
	_G[scrollName.."Text"]:SetText("")
	resultsFrame.scroll = scroll

	local percent = CreateFrame("Slider", "AuctioneerDealFinderPercent", inset, "OptionsSliderTemplate")
	percent:SetOrientation("HORIZONTAL")
	percent:SetPoint("TOPLEFT", inset, "BOTTOMLEFT", 10, -3)
	percent:SetHeight(20)
	percent:SetWidth(210)
	percent:SetMinMaxValues(5, 90)
	percent:SetValueStep(5)
	percent:SetValue(DEFAULT_DISCOUNT)
	percent:SetScript("OnValueChanged", redisplay)
	percent:SetScript("OnMouseWheel", wheelValue(percent))
	resultsFrame.percent = percent

	scrollName = percent:GetName()
	_G[scrollName.."Low"]:SetText("")
	_G[scrollName.."High"]:SetText("")
	_G[scrollName.."Text"]:SetText("")

	local percentText = resultsFrame:CreateFontString(nil, "OVERLAY")
	percentText:SetPoint("LEFT", percent, "RIGHT", 3, 0)
	percentText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	percentText:SetJustifyH("LEFT")
	percentText:SetText(DEFAULT_DISCOUNT.."% off or more")
	resultsFrame.percentText = percentText

	local function lineReset(self)
		self.item = nil
		self.bg:SetVertexColor(0.1, 0.1, 0.1)
		self.name:SetText("")
		self.money:Set()
	end

	local function lineMoney(self, money)
		self.money:Set(money)
	end

	local function lineVendor(self, set)
		if set then
			self.bg:SetVertexColor(1, 0.8, 0)
		else
			self.bg:SetVertexColor(0.1, 0.1, 0.1)
		end
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

	local ofs = 4
	local lines = {}
	local prev
	for i=0,35 do
		local line = CreateFrame("Button", nil, resultsFrame)
		if i == 0 then
			line:SetPoint("TOPLEFT", inset, "TOPLEFT", 5, 12)
			line:SetPoint("BOTTOMRIGHT", inset, "TOPRIGHT", -20, 0)
		else
			line:SetPoint("TOPLEFT", prev.name, "BOTTOMLEFT", 0, 0 - ofs)
			line:SetPoint("RIGHT", inset, "RIGHT", -20, 0)
			line:SetHeight(13)
			ofs = 0
		end

		line.Reset = lineReset
		line.SetMoney = lineMoney
		line.SetVendor = lineVendor
		line:SetScript("OnClick", lineClick)

		local linebg = line:CreateTexture(nil, "BACKGROUND")
		linebg:SetTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
		linebg:SetAllPoints(true)
		line.bg = linebg

		local name = line:CreateFontString(nil, "OVERLAY")
		name:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
		name:SetJustifyH("LEFT")
		name:SetWordWrap(false)
		name:SetPoint("TOPLEFT", line, "TOPLEFT", 0, 0)
		if i == 0 then
			name:SetText("Item")
			name:SetTextColor(0.6, 0.6, 0.6)
			linebg:Hide()
		end
		line.name = name

		if i == 0 then
			local profit = line:CreateFontString(nil, "OVERLAY")
			profit:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
			profit:SetJustifyH("RIGHT")
			profit:SetWordWrap(false)
			profit:SetPoint("TOPLEFT", name, "TOPRIGHT", 0, 0)
			profit:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT", 0, 0)
			profit:SetText("Profit")
			profit:SetTextColor(0.6, 0.6, 0.6)
			line.profit = profit

			name:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT", -130, 0)
		else
			local money = Auctioneer.GUI:MoneyView(line)
			local moneyFrame = money:Frame()
			moneyFrame:SetPoint("RIGHT", line, "RIGHT", 0, 0)
			line.money = money

			name:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT", -moneyFrame:GetWidth(), 0)

			line:Reset()
		end

		if i == 0 then
			resultsFrame.header = lines
		else
			lines[i] = line
		end

		prev = line
	end
	resultsFrame.lines = lines

	resultsFrame:Hide()
end
