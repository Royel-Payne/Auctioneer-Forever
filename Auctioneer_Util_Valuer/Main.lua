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

	local detail = valuerFrame.detail
	self:ShowFrame(detail)

	-- Remove all current lines back into the frame pool.
	local lines = detail.lines
	lines:Free()

	-- Add lines.
	local line = lines:AddSingleLine(14, "CENTER")
	line:Set("|c"..info.color..info.name.."|r")

	local id = item:ID()
	line = lines:AddDoubleLine()
	line:Set("Auctioneer StatID", id)

	local stats = Auctioneer:Statistics(id)
	for _, stat in ipairs(stats) do
		line = lines:AddSingleLine()
		line:Set(format("%s statistics:", stat.name))

		line = lines:AddMoneyLine()
		local best, number, method = stat:Best()
		line:Set(format(" - %s", method), best)

		local min, exact = stat:Minimum()
		if exact and min == exact and method ~= "minimum" then
			line = lines:AddMoneyLine()
			line:Set(" - minimum", min)
		end

		local max, exact = stat:Maximum()
		if exact and max == exact and method ~= "maximum" then
			line = lines:AddMoneyLine()
			line:Set(" - maximum", max)
		end

		local pct = stat:Percentile(10)
		if pct then
			line = lines:AddMoneyLine()
			line:Set(" - 10th percentile", pct)
		end

		line = lines:AddDoubleLine()
		line:Set(" - data points", "x"..number)
	end

	self:UpdateVendorCheck(self:ActiveSellFrame())
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
					Module:UpdateVendorCheck(sellFrame)
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

function Module:UpdateVendorCheck(sellFrame)
	local box = valuerFrame.vendor
	local itemLocation = sellFrame and sellFrame:GetItem()
	if not itemLocation or not itemLocation:IsValid() then
		box:Hide()
		return
	end

	local link = C_Item.GetItemLink(itemLocation)
	local vendorPrice = link and select(11, C_Item.GetItemInfo(link))
	if not vendorPrice then
		box:Hide()
		return
	end

	local labels, amounts = {}, {}
	local function add(label, amount)
		tinsert(labels, label)
		tinsert(amounts, amount or "")
	end

	if vendorPrice == 0 then
		add("Vendor check:")
		add("  Vendors won't buy this item")
		box.verdict:SetText("")
	else
		local quantity = math.max(sellFrame:GetQuantity() or 1, 1)
		local price = askingPrice(sellFrame)
		local n = Module.VendorNumbers(vendorPrice, price, quantity)
		local vendorTotal, auctionTotal = n.vendor, n.auction

		add(quantity > 1 and format("Vendor check (x%d):", quantity) or "Vendor check:")
		add("  Vendor pays", money(vendorTotal))
		add("  Auction pays after 5% cut", money(auctionTotal))
		add("  Deposit, lost if unsold", money(sellFrame:GetDepositAmount() or 0))
		add("  Beats vendor at", money(n.breakEven).." each")

		if price == 0 then
			box.verdict:SetText("")
		elseif auctionTotal > vendorTotal then
			box.verdict:SetText(GREEN_FONT_COLOR:WrapTextInColorCode(
				"Auction pays "..money(auctionTotal - vendorTotal).." more if it sells"))
		else
			box.verdict:SetText(RED_FONT_COLOR:WrapTextInColorCode(
				"Sell to a vendor: it pays "..money(vendorTotal - auctionTotal).." more"))
		end
	end

	box.labels:SetText(table.concat(labels, "\n"))
	box.amounts:SetText(table.concat(amounts, "\n"))
	box:Show()
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

	-- Vendor check box, along the bottom of the panel.
	local vendor = CreateFrame("Frame", nil, detail)
	vendor:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 0, 0)
	vendor:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", 0, 0)
	vendor:SetHeight(110)
	vendor.verdict = vendor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	vendor.verdict:SetPoint("BOTTOMLEFT", vendor, "BOTTOMLEFT", 0, 2)
	vendor.verdict:SetPoint("BOTTOMRIGHT", vendor, "BOTTOMRIGHT", 0, 2)
	vendor.verdict:SetJustifyH("LEFT")
	vendor.verdict:SetWordWrap(true)
	vendor.labels = vendor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	vendor.labels:SetPoint("BOTTOMLEFT", vendor.verdict, "TOPLEFT", 0, 6)
	vendor.labels:SetJustifyH("LEFT")
	vendor.labels:SetSpacing(3)
	vendor.amounts = vendor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	vendor.amounts:SetPoint("BOTTOMRIGHT", vendor.verdict, "TOPRIGHT", 0, 6)
	vendor.amounts:SetJustifyH("RIGHT")
	vendor.amounts:SetSpacing(3)
	vendor:Hide()
	valuerFrame.vendor = vendor

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
	valuerFrame:Hide()
end
