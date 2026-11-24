local addon = require("support.addon")
local errorLines = addon.errorLines

describe("DealFinder", function()
	local env, A, statsFor

	local function stat(price, n)
		return {
			name = "S",
			Number = function() return n end,
			Percentile = function() return price end,
			Minimum = function() return price end,
		}
	end

	before_each(function()
		statsFor = {}
		env, A = addon.start({
			files = {"Auctioneer_Util_DealFinder/Main.lua"},
			patch = function(A)
				A.module("Util:DealFinder").Display = function() end
				A.Auctioneer.Statistics = function() return statsFor end
			end,
		})
	end)

	it("compares several statistics without a Lua error", function()
		statsFor = {stat(500, 10), stat(400, 10)}
		A.scan({{itemID = 1, minPrice = 100, totalQuantity = 1}})
		assert.are.equal(0, errorLines(env.printed))
		assert.are.equal("arbitrage", A.module("Util:DealFinder").deals[1][3])
	end)

	it("flags an item below its vendor price when the item is cached", function()
		env.items[1] = {vendorPrice = 300, cached = true}
		A.scan({{itemID = 1, minPrice = 100, totalQuantity = 1}})
		assert.are.equal("vendor", A.module("Util:DealFinder").deals[1][3])
	end)

	it("redraws once for a burst of item key info arrivals", function()
		local finder = A.module("Util:DealFinder")
		local draws = 0
		finder.Display = function() draws = draws + 1 end
		finder.deals = {}
		for itemID = 1, 10 do env.dispatch("ITEM_KEY_ITEM_INFO_RECEIVED", itemID) end
		env.clock:advance(0.5)
		assert.are.equal(1, draws)
	end)

	it("skips a statistic that has no price", function()
		statsFor = {stat(400, 10), stat(nil, 10)}
		A.scan({{itemID = 1, minPrice = 100, totalQuantity = 1}})
		assert.are.equal(0, errorLines(env.printed))
	end)

	describe("deal rules", function()
		local finder
		before_each(function() finder = A.module("Util:DealFinder") end)

		it("ignores a listing a few copper under vendor price", function()
			-- Nightsky Trousers style: listed at 31s 64c, vendor pays 31s 65c.
			assert.is_nil(finder.Evaluate(3164, 3165, nil, nil))
		end)

		it("reports the real vendor profit, not the vendor price", function()
			local kind, profit, discount = finder.Evaluate(1000, 3000, nil, nil)
			assert.are.equal("vendor", kind)
			assert.are.equal(2000, profit)
			assert.is_true(math.abs(discount - 2/3) < 1e-9)
		end)

		it("prices a market deal at resale after the 5% cut", function()
			local kind, profit, discount, points = finder.Evaluate(5000, nil, 10000, 8)
			assert.are.equal("arbitrage", kind)
			assert.are.equal(4500, profit)
			assert.are.equal(0.5, discount)
			assert.are.equal(8, points)
		end)

		it("is not a market deal when the cut eats the margin", function()
			assert.is_nil(finder.Evaluate(9900, nil, 10000, 8))
		end)

		it("needs enough scans before trusting the usual price", function()
			statsFor = {stat(10000, 3)}
			A.scan({{itemID = 1, minPrice = 1000, totalQuantity = 1}})
			assert.are.equal(0, #finder.deals)
		end)

		it("lists the best profit first", function()
			env.items[1] = {vendorPrice = 1500, cached = true}
			env.items[2] = {vendorPrice = 9000, cached = true}
			A.scan({
				{itemID = 1, minPrice = 100, totalQuantity = 1},
				{itemID = 2, minPrice = 100, totalQuantity = 1},
			})
			assert.are.equal(2, #finder.deals)
			assert.is_true(finder.deals[1][4] > finder.deals[2][4])
		end)
	end)
end)
