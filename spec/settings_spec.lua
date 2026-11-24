local addon = require("support.addon")

describe("Settings", function()
	local env, A, scanner

	before_each(function()
		env, A = addon.start({files = {"Auctioneer_Util_DealFinder/Main.lua"}})
		scanner = A.module("Scanner")
		_G.AuctioneerData = _G.AuctioneerData or {}
	end)

	it("gives the defaults until the player changes something", function()
		assert.is_true(A.Auctioneer:Setting("autoScan"))
		assert.are.equal(1, A.Auctioneer:Setting("autoScanHours"))
		assert.are.equal(25, A.Auctioneer:Setting("dealsMinDiscount"))
		A.Auctioneer:SetSetting("autoScan", false)
		assert.is_false(A.Auctioneer:Setting("autoScan"))
	end)

	describe("auto-scan", function()
		it("does nothing when switched off", function()
			A.Auctioneer:SetSetting("autoScan", false)
			AuctioneerData.lastFullScan = nil
			env.ah.queries = {}
			scanner:AutoScan(1)
			assert.are.equal(0, #env.ah.queries)
		end)

		it("waits the number of hours the player chose", function()
			A.Auctioneer:SetSetting("autoScanHours", 3)
			AuctioneerData.lastFullScan = GetServerTime() - 2 * 3600
			env.ah.queries = {}
			scanner:AutoScan(1)
			assert.are.equal(0, #env.ah.queries)
			AuctioneerData.lastFullScan = GetServerTime() - 4 * 3600
			scanner:AutoScan(1)
			assert.are.equal(1, #env.ah.queries)
		end)

		it("can scan without a chat line", function()
			A.Auctioneer:SetSetting("announceScan", false)
			AuctioneerData.lastFullScan = nil
			local before = #env.printed
			scanner:AutoScan(1)
			assert.are.equal(before, #env.printed)
		end)
	end)

	describe("deal finder minimum profit", function()
		it("is a parameter of the deal rules", function()
			local finder = A.module("Util:DealFinder")
			assert.is_nil(finder.Evaluate(1000, 1400, nil, nil, 500))
			assert.are.equal("vendor", (finder.Evaluate(1000, 1400, nil, nil, 300)))
		end)

		it("keeps every profitable listing from a scan for the display to filter", function()
			local finder = A.module("Util:DealFinder")
			env.items[1] = {vendorPrice = 150, cached = true}
			A.scan({{itemID = 1, minPrice = 100, totalQuantity = 1}})
			assert.are.equal(1, #finder.deals)
			assert.are.equal(50, finder.deals[1][4])
		end)
	end)
end)
