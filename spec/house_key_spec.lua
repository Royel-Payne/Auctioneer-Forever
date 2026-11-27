local addon = require("support.addon")
local wow = require("support.wow")

local STATS = {files = {"Auctioneer_Stats_OverTime/Main.lua"}}

-- Boots with the auction house open at an auctioneer of the given faction
-- (nil: a goblin house). Data already saved goes in before the addon loads.
local function openAt(npcFaction, saved)
	local env = wow.install()
	env.npcFaction = npcFaction
	_G.AuctioneerStatsOverTimeData = saved
	return env, addon.boot(env, STATS)
end

describe("auction key", function()
	it("names the server from the player's GUID and the house's faction", function()
		local _, A = openAt("Horde")
		assert.are.equal("6931-Horde", A.Auctioneer:AuctionKey())
	end)

	it("keeps a goblin auction house apart as Neutral", function()
		local _, A = openAt(nil)
		assert.are.equal("6931-Neutral", A.Auctioneer:AuctionKey())
	end)

	it("uses the other faction's house when its auctioneer is the one open", function()
		local _, A = openAt("Alliance")
		assert.are.equal("6931-Alliance", A.Auctioneer:AuctionKey())
	end)

	it("goes back to the player's own house once the auction house closes", function()
		local env, A = openAt(nil)
		env.dispatch("AUCTION_HOUSE_CLOSED")
		assert.are.equal("6931-Horde", A.Auctioneer:AuctionKey())
	end)

	it("falls back to the player's house when no auctioneer can be asked", function()
		local env = wow.install()
		env.npcPresent = false
		local A = addon.boot(env, STATS)
		assert.are.equal("6931-Horde", A.Auctioneer:AuctionKey())
	end)

	it("separates rulesets: another server number is another key", function()
		local env = wow.install()
		_G.UnitGUID = function() return "Player-6934-05230286" end
		local A = addon.boot(env, STATS)
		assert.are.equal("6934-Horde", A.Auctioneer:AuctionKey())
	end)
end)

describe("Stats:OverTime data per house", function()
	it("drops data saved under the old realm keys, mixed and unsortable", function()
		openAt("Horde", {[""] = {[1] = {}}, TestRealm = {[1] = {}}, ["6931-Neutral"] = {[1] = {}}})
		assert.is_nil(AuctioneerStatsOverTimeData[""])
		assert.is_nil(AuctioneerStatsOverTimeData.TestRealm)
		assert.is_table(AuctioneerStatsOverTimeData["6931-Neutral"])
	end)

	it("stores a scan at a goblin house under Neutral, not the player's faction", function()
		local _, A = openAt(nil)
		A.scan(addon.rows(3))
		assert.is_table(AuctioneerStatsOverTimeData["6931-Neutral"])
		assert.is_nil(AuctioneerStatsOverTimeData["6931-Horde"])
	end)
end)
