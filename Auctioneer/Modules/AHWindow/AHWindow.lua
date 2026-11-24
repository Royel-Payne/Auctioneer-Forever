if not Auctioneer then return end

-- Create a new Auctioneer module.
local Module = Auctioneer:Module("AHWindow")
local Const = Auctioneer:Const()

-- Hook our methods.
function Module:Boot(hook)
	hook(Const.AuctionHouseOpened, Module.AuctionHouseOpened)
end

local function OnMouseDown(frame)
	frame:StartMoving()
end

local function OnMouseUp(frame)
	frame:StopMovingOrSizing()
end

-- Dropping an item on the sell slot while it already holds one makes Blizzard's
-- SwitchItemWithCursor pick the old item up onto the cursor. Put it back in the bag
-- instead: the new item is in the slot and the old one simply stays where it is.
-- A post-hook (hooksecurefunc) only clears the cursor afterwards, so Blizzard's
-- own code runs untouched and nothing it later reads is tainted.
local function KeepOldItemInBag(itemDisplay)
	if not Auctioneer:Setting("sellSlotSwap") then
		return
	end
	local cursorItem = C_Cursor.GetCursorItem()
	local slotItem = itemDisplay:GetItemLocation()
	if cursorItem and slotItem and not cursorItem:IsEqualTo(slotItem) then
		ClearCursor()
	end
end

local function HookSellSlot(sellFrame)
	local itemDisplay = sellFrame and sellFrame.ItemDisplay
	if itemDisplay and itemDisplay.SwitchItemWithCursor and not itemDisplay.AuctioneerSwapHooked then
		itemDisplay.AuctioneerSwapHooked = true
		hooksecurefunc(itemDisplay, "SwitchItemWithCursor", KeepOldItemInBag)
	end
end

function Module:AuctionHouseOpened()
	if AuctionHouseFrame then
		HookSellSlot(AuctionHouseFrame.ItemSellFrame)
		HookSellSlot(AuctionHouseFrame.CommoditiesSellFrame)
	end
	if AuctionHouseFrame and not AuctionHouseFrame.Auctioneered then
		AuctionHouseFrame.Auctioneered = true
		AuctionHouseFrame:SetMovable(true)
		AuctionHouseFrame:SetClampedToScreen(true)
		AuctionHouseFrame:SetScript("OnMouseDown", OnMouseDown)
		AuctionHouseFrame:SetScript("OnMouseUp", OnMouseUp)
	end
end
