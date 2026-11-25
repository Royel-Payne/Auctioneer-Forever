local wow, addon = require("support.wow"), require("support.addon")

describe("Valuer", function()
	local env, A, valuer, shown

	before_each(function()
		env, A = addon.start({files = {"Auctioneer_Util_Valuer/Main.lua", "Auctioneer_Util_Valuer/Exact.lua"}})
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

	describe("exact matches", function()
		it("lists only the exact item, cheapest per item first, bid-only last", function()
			local rows = valuer.ExactRows({
				{itemLink = wow.link(1, nil, "Cloak of the Monkey"), buyoutAmount = 2500, quantity = 1},
				{itemLink = wow.link(1, nil, "Cloak of Spirit"), buyoutAmount = 600, quantity = 1},
				{itemLink = wow.link(1, nil, "Cloak of the Monkey"), bidAmount = 1000, quantity = 1},
				{itemLink = wow.link(1, nil, "Cloak of the Monkey"), buyoutAmount = 4000, quantity = 2},
			}, "Cloak of the Monkey")
			assert.are.equal(3, #rows)
			assert.are.equal(2000, rows[1].buyout)
			assert.are.equal(2500, rows[2].buyout)
			assert.is_nil(rows[3].buyout)
			assert.are.equal(1000, rows[3].bid)
		end)

		it("prices from the cheapest listing, else history, never over a typed price", function()
			local rows = {{bid = 50}, {buyout = 1999}}
			assert.are.same({1999, "listing"}, {valuer.ExactPrice(rows, 5000, false)})
			assert.are.same({5000, "history"}, {valuer.ExactPrice({}, 4987, false)})
			assert.are.same({nil, "none"}, {valuer.ExactPrice({}, nil, false)})
			assert.are.same({nil, "typed"}, {valuer.ExactPrice(rows, 5000, true)})
		end)

		it("undercuts the cheapest listing, but not your own", function()
			local rows = {{buyout = 2000}, {buyout = 2500}}
			assert.are.same({1900, "listing"}, {valuer.ExactPrice(rows, nil, false, 50)})
			assert.are.same({2000, "listing"}, {valuer.ExactPrice(rows, nil, false, 0)})
			assert.are.same({2000, "mine"}, {valuer.ExactPrice({{buyout = 2000, mine = true}}, nil, false, 50)})
			assert.are.same({5000, "history"}, {valuer.ExactPrice({}, 4987, false, 50)})
		end)

		it("rounds an item's undercut price down to whole silver, commodities to copper", function()
			assert.are.equal(1900, valuer.Undercut(2000, 5, true))
			assert.are.equal(1995, valuer.Undercut(2000, 5, false))
			assert.are.equal(100, valuer.Undercut(150, 500, true))
			assert.are.equal(1, valuer.Undercut(150, 500, false))
			assert.are.equal(2000, valuer.Undercut(2000, 0, true))
		end)

		it("rounds a history price to whole silver, at least one", function()
			assert.are.equal(500, valuer.WholeSilver(451))
			assert.are.equal(100, valuer.WholeSilver(3))
		end)

		it("asks for the exact variant once when a suffix item is placed", function()
			env.variantNames["6576:14310"] = "Fortified Cloak of the Monkey"
			env.ah.infoCache["6576:14310"] = {itemName = "Fortified Cloak of the Monkey", quality = 2, iconFileID = 1}
			A.scan({{itemID = 6576, itemLevel = 22, itemSuffix = 14310, minPrice = 2000, totalQuantity = 1}})
			C_AuctionHouse.GetItemKeyFromItem = function() return C_AuctionHouse.MakeItemKey(6576, 22, 14310, 0) end
			local loc = {link = wow.link(6576, nil, "Fortified Cloak of the Monkey")}
			valuer:SellItemLoaded(AuctionHouseSearchContext.SellItems, loc)
			valuer:SellItemLoaded(AuctionHouseSearchContext.SellItems, loc)
			assert.are.equal(1, #env.ah.itemQueries)
			assert.are.equal(14310, env.ah.itemQueries[1].itemKey.itemSuffix)
		end)

		it("does not search for an item without a suffix, or when turned off", function()
			valuer:SellItemLoaded(AuctionHouseSearchContext.SellItems, {link = wow.link(2589, nil, "Linen Cloth")})
			assert.are.equal(0, #env.ah.itemQueries)
			_G.AuctioneerSettings = {exactMatch = false}
			C_AuctionHouse.GetItemKeyFromItem = function() return C_AuctionHouse.MakeItemKey(6576, 22, 14310, 0) end
			valuer:SellItemLoaded(AuctionHouseSearchContext.SellItems, {link = wow.link(6576, nil, "Fortified Cloak of the Monkey")})
			assert.are.equal(0, #env.ah.itemQueries)
		end)

		it("reads the name out of an item link", function()
			assert.are.equal("Fortified Cloak of the Monkey",
				valuer.LinkName(wow.link(6576, nil, "Fortified Cloak of the Monkey")))
			assert.is_nil(valuer.LinkName(nil))
		end)
	end)
end)
