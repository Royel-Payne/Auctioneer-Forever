local addon = require("support.addon")

describe("Freshness", function()
	local env, A, scanner

	before_each(function()
		env, A = addon.start({files = {"Auctioneer_Util_Valuer/Main.lua"}})
		scanner = A.module("Scanner")
		_G.AuctioneerData = _G.AuctioneerData or {}
	end)

	describe("full scan", function()
		it("is an empty search with Blizzard's default filters", function()
			_G.AUCTION_HOUSE_DEFAULT_FILTERS = {[1] = true, [2] = true, [3] = false}
			assert.is_true(scanner.IsFullQuery({searchString = "", sorts = {}, filters = {2, 1}}))
			assert.is_false(scanner.IsFullQuery({searchString = "linen", sorts = {}, filters = {1, 2}}))
			assert.is_false(scanner.IsFullQuery({searchString = "", sorts = {}, filters = {1}}))
			assert.is_false(scanner.IsFullQuery({searchString = "", sorts = {}, filters = {1, 2}, itemClassFilters = {{classID = 7}}}))
			assert.is_false(scanner.IsFullQuery({searchString = "", sorts = {}, filters = {1, 2}, minLevel = 10}))
			_G.AUCTION_HOUSE_DEFAULT_FILTERS = nil
		end)

		it("records the time when a full scan finishes", function()
			scanner.lastQueryFull = true
			local before = GetServerTime()
			A.scan(addon.rows(5))
			local at = AuctioneerData.lastFullScan
			assert.is_truthy(at)
			assert.is_true(at >= before and at <= GetServerTime())
		end)

		it("does not count a filtered search as a full scan", function()
			AuctioneerData.lastFullScan = nil
			scanner.lastQueryFull = false
			A.scan(addon.rows(5))
			assert.is_nil(AuctioneerData.lastFullScan)
		end)
	end)

	describe("auto-scan on opening", function()
		it("scans when there are no prices yet", function()
			AuctioneerData.lastFullScan = nil
			env.ah.queries = {}
			scanner:AutoScan(1)
			assert.are.equal(1, #env.ah.queries)
			assert.are.equal("", env.ah.queries[1].searchString)
		end)

		it("scans when the last full scan is over an hour old", function()
			AuctioneerData.lastFullScan = GetServerTime() - 2 * 3600
			env.ah.queries = {}
			scanner:AutoScan(1)
			assert.are.equal(1, #env.ah.queries)
		end)

		it("leaves fresh prices alone", function()
			AuctioneerData.lastFullScan = GetServerTime() - 10 * 60
			env.ah.queries = {}
			scanner:AutoScan(1)
			assert.are.equal(0, #env.ah.queries)
		end)
	end)

	describe("deal finder after a scan", function()
		local function completedAuto()
			for i = #A.triggers, 1, -1 do
				local t = A.triggers[i]
				if t.name == "ScannerItemsCompleted" then return t.args[2] end
			end
		end

		it("is told when the scan was the auto-scan on opening", function()
			scanner.lastQueryAuto = true
			A.scan(addon.rows(3))
			assert.is_true(completedAuto())
		end)

		it("is told when the player started the scan", function()
			scanner.lastQueryAuto = false
			A.scan(addon.rows(3))
			assert.is_false(completedAuto())
		end)
	end)

	describe("ages", function()
		it("reads naturally", function()
			assert.are.equal("just now", A.Auctioneer:Ago(30))
			assert.are.equal("12 min ago", A.Auctioneer:Ago(12 * 60))
			assert.are.equal("3 h ago", A.Auctioneer:Ago(3 * 3600 + 100))
			assert.are.equal("4 days ago", A.Auctioneer:Ago(4 * 86400))
		end)

		it("finds when an item was last seen", function()
			local valuer = A.module("Util:Valuer")
			local stat = {points = {{timeslice = 100}, {timeslice = 103}, {timeslice = 101}}}
			assert.are.equal(2, valuer.HoursSinceSeen(stat, 105))
			assert.is_nil(valuer.HoursSinceSeen({}, 105))
		end)
	end)
end)
