local addon = require("support.addon")

describe("Valuer", function()
	local env, A, valuer, shown

	before_each(function()
		env, A = addon.start({files = {"Auctioneer_Util_Valuer/Main.lua"}})
		valuer = A.module("Util:Valuer")
		C_AuctionHouse.GetItemKeyFromItem = function() return C_AuctionHouse.MakeItemKey(2589, 0, 0, 0) end
		shown = 0
		local show = valuer.SellItemLoaded
		valuer.SellItemLoaded = function(...) shown = shown + 1; return show(...) end
	end)

	it("names its panel apart from the Deal finder's", function()
		assert.is_truthy(_G.AuctioneerValuerFrame)
	end)

	it("shows the sell item again once its item key info arrives", function()
		valuer:SellItemLoaded("SellItems", {})
		env.clock:runUntilIdle(10)
		assert.are.equal(2, shown)
	end)

	it("does not show it again when the item key info was already there", function()
		env.ah.infoCache[2589] = {itemName = "Linen Cloth", quality = 1, iconFileID = 1}
		valuer:SellItemLoaded("SellItems", {})
		env.clock:runUntilIdle(10)
		assert.are.equal(1, shown)
	end)

	describe("vendor check", function()
		it("prefers the auction when it pays more after the 5% cut", function()
			-- Linen Cloth: vendor 13c, posting 20 at 25c each.
			local n = valuer.VendorNumbers(13, 25, 20)
			assert.are.equal(260, n.vendor)
			assert.are.equal(475, n.auction)
			assert.is_true(n.auction > n.vendor)
		end)

		it("prefers the vendor when the cut eats the margin", function()
			local n = valuer.VendorNumbers(100, 100, 1)
			assert.are.equal(95, n.auction)
			assert.is_true(n.auction < n.vendor)
		end)

		it("breaks even just above vendor price plus the cut", function()
			local n = valuer.VendorNumbers(100, 0, 1)
			assert.are.equal(106, n.breakEven)
			assert.is_true(n.breakEven * 0.95 > 100)
			assert.is_true((n.breakEven - 1) * 0.95 <= 100)
		end)

		it("does not fail on an item without a link", function()
			assert.has_no.errors(function() valuer:Render(nil) end)
			valuer:SellItemLoaded("SellItems", {})
		end)
	end)
end)
