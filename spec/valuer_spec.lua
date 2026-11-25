local wow, addon = require("support.wow"), require("support.addon")

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
	describe("random-suffix item", function()
		local MONKEY, SHADOW = 14310, 14455
		local MONKEY_LINK = wow.link(6576, nil, "Fortified Cloak of the Monkey")

		before_each(function()
			env.variantNames["6576:" .. MONKEY] = "Fortified Cloak of the Monkey"
			env.variantNames["6576:" .. SHADOW] = "Fortified Cloak of Shadow Protection"
			A.scan({
				{itemID = 6576, itemLevel = 22, itemSuffix = MONKEY, minPrice = 2000, totalQuantity = 1},
				{itemID = 6576, itemLevel = 22, itemSuffix = SHADOW, minPrice = 600, totalQuantity = 1},
			})
			env.clock:runUntilIdle(10)
			-- The client hands out the Shadow Protection key for the Monkey cloak.
			C_AuctionHouse.GetItemKeyFromItem = function() return C_AuctionHouse.MakeItemKey(6576, 22, SHADOW, 0) end
		end)

		it("prices the item by the variant with its name, not the key the client gives", function()
			env.ah.infoCache["6576:" .. MONKEY] = {itemName = "Fortified Cloak of the Monkey", quality = 2, iconFileID = 1}
			env.ah.infoCache["6576:" .. SHADOW] = {itemName = "Fortified Cloak of Shadow Protection", quality = 2, iconFileID = 1}
			valuer:SellItemLoaded("SellItems", {link = MONKEY_LINK})
			assert.are.equal("6576:22:" .. MONKEY, valuer.current.item:ID())
			assert.are.equal("Fortified Cloak of the Monkey", valuer.current.info.name)
			assert.are.equal(SHADOW, valuer.current.listKey.itemSuffix)
		end)

		it("keeps the client's key until variant names arrive, then switches", function()
			env.ah.infoCache = {}
			valuer:SellItemLoaded("SellItems", {link = MONKEY_LINK})
			env.clock:runUntilIdle(10)
			assert.are.equal("6576:22:" .. MONKEY, valuer.current.item:ID())
		end)
	end)

	describe("listing summary", function()
		it("tells this item's listings from other variants'", function()
			local s = valuer.ListingSummary({
				{name = "Cloak of Shadow Protection", unitPrice = 600},
				{name = "Cloak of the Monkey", unitPrice = 2500},
				{name = "Cloak of Shadow Protection", unitPrice = 625},
				{name = "Cloak of the Monkey", unitPrice = 1999},
				{name = "Cloak of the Wolf", unitPrice = 900},
			}, "Cloak of the Monkey")
			assert.are.equal(2, s.exact)
			assert.are.equal(1999, s.lowest)
			assert.are.same({1999, 2500}, s.prices)
			assert.are.same({
				{name = "Cloak of Shadow Protection", count = 2},
				{name = "Cloak of the Wolf", count = 1},
			}, s.others)
		end)

		it("has no lowest price when none is this item", function()
			local s = valuer.ListingSummary({{name = "Other", unitPrice = 5}}, "Mine")
			assert.are.equal(0, s.exact)
			assert.is_nil(s.lowest)
		end)

		it("reads the name out of an item link", function()
			assert.are.equal("Fortified Cloak of the Monkey",
				valuer.LinkName(wow.link(6576, nil, "Fortified Cloak of the Monkey")))
			assert.is_nil(valuer.LinkName(nil))
		end)
	end)
end)
