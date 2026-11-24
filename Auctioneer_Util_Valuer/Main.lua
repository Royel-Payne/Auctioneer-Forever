if not Auctioneer then return end

-- Create a new Auctioneer module.
local Module = Auctioneer:Module("Util:Valuer")
local Const = Auctioneer.Const()

local valuerFrame
local gui = Auctioneer.GUI

-- Hook our methods
function Module:Boot(hook)
	hook(Const.DisplayModeChanged, Module.DisplayModeChanged)
	hook(Const.SellItemLoaded, Module.SellItemLoaded)
	hook(Const.ItemKeyInfoFound, Module.ItemKeyInfoFound)
	Module:CreateFrame()
	Module:HookSellFrames()
end

-- The sell item can be shown before its item key info arrives; show it again when it does.
function Module:ItemKeyInfoFound(itemID)
	local waiting = self.waitingInfo
	if waiting and waiting.itemID == itemID then
		self.waitingInfo = nil
		self:SellItemLoaded(waiting.itemType, waiting.itemLocation)
	end
end

if not AuctioneerUtilValuerData then
	AuctioneerUtilValuerData = {}
end

function Module:DisplayModeChanged(displayMode)
	if displayMode ~= AuctionHouseFrameDisplayMode.ItemSell and
	displayMode ~= AuctionHouseFrameDisplayMode.CommoditiesSell then
		self:Hide()
	end
end

function Module:SellItemLoaded(itemType, itemLocation)
	if not itemType or not itemLocation then
		self:Hide()
		return
	end

	local itemKey = C_AuctionHouse.GetItemKeyFromItem(itemLocation)
	if not itemKey then
		self:Hide()
		return
	end

	local item = Auctioneer:Item{
		itemKey = itemKey,
		itemLocation = itemLocation
	}

	local info = item:Info()
	self.waitingInfo = nil
	if not item.itemInfo then
		self.waitingInfo = {itemID = itemKey.itemID, itemType = itemType, itemLocation = itemLocation}
	end

	self.current = {item = item, info = info}
	self:Render(self:ActiveSellFrame())
end

-- Fonts, as in Blizzard's own sell frame: labels and headings in Friz Quadrata,
-- money in the GUI's money view (Arial Narrow, like Blizzard's number font).
local LABEL_FONT, LABEL_SIZE = "FRIZQT__", 11

-- Money lines show copper: most of what gets posted is worth less than a silver.
local function addMoney(lines, label, amount)
	local line = lines:AddMoneyLine(LABEL_SIZE, LABEL_FONT, nil, true)
	line:Set(label, amount)
end

-- A label with a number on the right; the number uses the money column's font.
local function addCount(lines, label, value)
	local line = lines:AddDoubleLine(LABEL_SIZE, LABEL_FONT)
	if line.right then
		line.right:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
	end
	line:Set(label, value)
end

-- When an item was last seen at auction: hours since its newest data point.
-- Older than the staleHours setting and the price history is shown as stale (orange).
function Module.HoursSinceSeen(stat, now)
	local newest
	for _, point in ipairs(stat.points or {}) do
		if point.timeslice and (not newest or point.timeslice > newest) then
			newest = point.timeslice
		end
	end
	return newest and math.max(0, now - newest)
end

-- Section title in Blizzard's gold heading colour.
local function addHeader(lines, text)
	lines:AddSingleLine(LABEL_SIZE, "LEFT", LABEL_FONT):Set("|cffffd100"..text.."|r")
end

-- A thin gold rule between sections, with a little space either side.
local function addDivider(lines)
	local line = lines:AddSingleLine(6)
	local frame = line:Frame()
	local rule = lines:Texture("Interface\\Buttons\\WHITE8X8")
	rule:SetParent(frame)
	rule:SetPoint("LEFT", frame, "LEFT", 0, 0)
	rule:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
	rule:SetHeight(1)
	rule:SetVertexColor(1, 0.82, 0, 0.35)
	frame:Add(rule)
end

-- Draw the panel: item, price statistics, then the vendor check for the sell frame.
function Module:Render(sellFrame)
	local current = self.current
	if not current then return end
	local item, info = current.item, current.info

	local detail = valuerFrame.detail
	self:ShowFrame(detail)

	-- Remove all current lines back into the frame pool.
	local lines = detail.lines
	lines:Free()

	-- Add lines.
	local line = lines:AddSingleLine(13, "CENTER", LABEL_FONT)
	line:Set("|c"..info.color..info.name.."|r")

	local id = item:ID()
	addCount(lines, "|cff808080Auctioneer StatID|r", "|cff808080"..id.."|r")

	local stats = Auctioneer:Statistics(id)
	for _, stat in ipairs(stats) do
		addDivider(lines)
		addHeader(lines, format("%s statistics", stat.name))

		local best, number, method = stat:Best()
		addMoney(lines, format(" - %s", method), best)

		local min, exact = stat:Minimum()
		if exact and min == exact and method ~= "minimum" then
			addMoney(lines, " - minimum", min)
		end

		local max, exact = stat:Maximum()
		if exact and max == exact and method ~= "maximum" then
			addMoney(lines, " - maximum", max)
		end

		local pct = stat:Percentile(10)
		if pct then
			addMoney(lines, " - 10th percentile", pct)
		end

		addCount(lines, " - data points", "x"..number)

		local hours = Module.HoursSinceSeen(stat, Auctioneer:Timeslice())
		if hours then
			local text = hours < 1 and "this hour" or Auctioneer:Ago(hours * 3600)
			if hours >= Auctioneer:Setting("staleHours") then
				text = "|cffff9933"..text.."|r"
			end
			addCount(lines, " - last seen", text)
		end
	end

	self:AddVendorCheck(lines, sellFrame)
end

-- Vendor check: does posting at the asking price beat selling to a vendor?
-- The auction house keeps a 5% cut of a sale (no API gives the rate).
local AUCTION_CUT = 0.05

local function money(copper)
	copper = math.floor(copper + 0.5)
	if GetMoneyString then
		return GetMoneyString(copper, true)
	end
	return format("%dg %ds %dc", copper / 10000, (copper / 100) % 100, copper % 100)
end

-- Vendor and auction proceeds for posting `quantity` at `unitPrice`, and the lowest
-- price per item at which the auction beats the vendor after the cut.
function Module.VendorNumbers(vendorPrice, unitPrice, quantity)
	return {
		vendor = vendorPrice * quantity,
		auction = unitPrice * quantity * (1 - AUCTION_CUT),
		breakEven = math.floor(vendorPrice / (1 - AUCTION_CUT)) + 1,
	}
end

function Module:ActiveSellFrame()
	if not AuctionHouseFrame then return end
	for _, frame in ipairs({AuctionHouseFrame.CommoditiesSellFrame, AuctionHouseFrame.ItemSellFrame}) do
		if frame and frame:IsShown() then
			return frame
		end
	end
end

-- Post-hook the sell frames' UpdatePostState, which Blizzard calls whenever the
-- item, quantity, price or duration changes. A post-hook only reads the frame.
function Module:HookSellFrames()
	if not AuctionHouseFrame then return end
	for _, frame in ipairs({AuctionHouseFrame.CommoditiesSellFrame, AuctionHouseFrame.ItemSellFrame}) do
		if frame and frame.UpdatePostState and not frame.AuctioneerVendorHooked then
			frame.AuctioneerVendorHooked = true
			hooksecurefunc(frame, "UpdatePostState", function(sellFrame)
				if valuerFrame:IsShown() and sellFrame:IsShown() then
					Module:Render(sellFrame)
				end
			end)
		end
	end
end

-- Asking price per item: the commodity unit price, or an item's buyout (bid if no buyout).
local function askingPrice(sellFrame)
	if sellFrame.GetUnitPrice then
		return sellFrame:GetUnitPrice() or 0
	end
	local bid, buyout = sellFrame:GetPrice()
	return buyout or bid or 0
end

function Module:AddVendorCheck(lines, sellFrame)
	if not Auctioneer:Setting("vendorCheck") then
		return
	end
	local itemLocation = sellFrame and sellFrame:GetItem()
	if not itemLocation or not itemLocation:IsValid() then
		return
	end

	local link = C_Item.GetItemLink(itemLocation)
	local vendorPrice = link and select(11, C_Item.GetItemInfo(link))
	if not vendorPrice then
		return
	end

	addDivider(lines)
	if vendorPrice == 0 then
		addHeader(lines, "Vendor check")
		lines:AddSingleLine(LABEL_SIZE, "LEFT", LABEL_FONT):Set(" - vendors won't buy this item")
		return
	end

	local quantity = math.max(sellFrame:GetQuantity() or 1, 1)
	local price = askingPrice(sellFrame)
	local n = Module.VendorNumbers(vendorPrice, price, quantity)

	addHeader(lines, quantity > 1 and format("Vendor check (x%d)", quantity) or "Vendor check")
	addMoney(lines, " - vendor pays", n.vendor)
	addMoney(lines, " - auction pays, after 5% cut", n.auction)
	addMoney(lines, " - deposit, lost if unsold", sellFrame:GetDepositAmount() or 0)
	addMoney(lines, " - beats vendor at, per item", n.breakEven)

	if price > 0 then
		lines:AddSingleLine(4)
		local verdict = lines:AddSingleLine(LABEL_SIZE + 1, "CENTER", LABEL_FONT)
		if n.auction > n.vendor then
			verdict:Set(GREEN_FONT_COLOR:WrapTextInColorCode(
				"Post it: auction pays "..money(n.auction - n.vendor).." more"))
		else
			verdict:Set(RED_FONT_COLOR:WrapTextInColorCode(
				"Vendor it: vendor pays "..money(n.vendor - n.auction).." more"))
		end
	end
end

function Module:CreateFrame()
	valuerFrame = CreateFrame("Frame", "AuctioneerValuerFrame", AuctionHouseFrame, "SimplePanelTemplate")
	valuerFrame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", -2, -20)
	valuerFrame:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT", -2, 5)
	valuerFrame:SetWidth(320)
	valuerFrame.frames = {}

	local inset = valuerFrame.Inset

	local close = CreateFrame("Button", nil, valuerFrame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", valuerFrame, "TOPRIGHT")
	close:SetWidth(32)
	close:SetHeight(32)
	valuerFrame.close = close

	local title = valuerFrame:CreateFontString(nil, "OVERLAY")
	title:SetPoint("BOTTOM", inset, "TOP", 0, 3)
	title:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	title:SetJustifyH("LEFT")
	title:SetTextColor(1, 0.8, 0)
	title:SetText("Valuer")

	local bg = inset.Bg
	bg:SetVertTile(false)
	bg:SetHorizTile(false)
	bg:SetAtlas("auctionhouse-background-buy-commodities-market", true)

	local detail = CreateFrame("Frame", nil, inset)
	detail:SetPoint("TOPLEFT", inset, "TOPLEFT", 5, -5)
	detail:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -5, 5)
	valuerFrame.detail = detail
	tinsert(valuerFrame.frames, detail)

	-- GUI:Lines() is like a tooltip, you add lines to it. Then when done, :Free()
	local lines = Auctioneer.GUI:Lines(detail)
	detail.lines = lines


	valuerFrame:Hide()
end

function Module:Reset()
end

function Module:ShowFrame(show)
	valuerFrame:Show()
	for _, frame in ipairs(valuerFrame.frames) do
		if frame == show then
			frame:Show()
		else
			frame:Hide()
		end
	end
end

function Module:Hide()
	self.waitingInfo = nil
	self.current = nil
	valuerFrame:Hide()
end
