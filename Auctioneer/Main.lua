local addonName, _ = ... -- return addon name dynamically
_G.Auctioneer = _G.Auctioneer or {}
local Auctioneer = _G.Auctioneer
local private = CreateFrame("Frame")

if not Stubby then
	error("Auctioneer requires Stubby")
end

if not LibStub then
	error("Auctioneer requires LibStub")
end

local AUC_VERSION = "<%version%>"
if AUC_VERSION:byte(1) == 60 then -- 60 = '<'
	AUC_VERSION = "8.3.DEV"
end

local parts = {}
private.parts = parts

-- Get the original frame object.
function parts:Frame()
	return private
end

local libs = {}
libs.DebugLib = LibStub("DebugLib", true)
libs.Configator = LibStub("Configator", true)
libs.Babylonian = LibStub("Babylonian", true)
libs.TipHelper = LibStub("nTipHelper:1", true)
libs.LibDataBroker = LibStub("LibDataBroker-1.1", true)

local missing = ""
if not libs.Configator then
	missing = missing.." Configator"
end
if not libs.Babylonian then
	missing = missing.." Babylonian"
end
if not libs.TipHelper then
	missing = missing.." TipHelper"
end
if missing ~= "" then
	error("Auctioneer is missing:"..missing)
end

if not AuctioneerData then
	AuctioneerData = {}
end

if not AuctioneerLocal then
	AuctioneerLocal = {}
end

if not AuctioneerData.itemHasLevel then
	AuctioneerData.itemHasLevel = {}
end

-- Register an Auctioneer module.
function private:Module(name, ...)
	if not name then
		error("Auctioneer: Registering module did not supply a name")
	end

	local reg = {}
	reg.name = name
	reg.deps = {...}
	reg.hooks = {}
	reg.bootType = parts.Const.BootType.AuctionHouseLoaded
	reg.Hook = parts.Internal.Hook
	reg.Dump = parts.Internal.Dump
	reg.Coins = libs.TipHelper.Coins

	for k,v in pairs(libs) do
		reg[k] = v
	end

	parts.Internal:Add(reg)
	return reg
end

-- Trigger an Auctioneer event to be sent to all modules.
function private:Trigger(event, ...)
	for _, module in ipairs(parts.Internal.modules) do
		if module.hooks[event] then
			local status, err = pcall(module.hooks[event], module, ...)
			if not status then
				print("Auctioneer: Error triggering", module.name, "("..parts.Const:Name(event).."):", err)
			end
		end
	end
end

-- Allow specific internal methods to boot up and get access to private object.
-- This method only functions from Main.lua load until Register.lua finishes.
function private:Boot(name)
	if private.booted or parts[name] then
		return
	end

	local item = {}
	item._ = parts
	item.libs = libs
	parts[name] = item
	return item
end

function private:Const()
	return parts.Const
end

-- Prices are kept per server and auction house, as "<server>-<house>", e.g. "6931-Horde".
-- WoW Forever gives addons an empty realm name and realm ID 0. A character's GUID
-- ("Player-6931-051C6261") still names its server, and every character an account
-- has on one ruleset shares that server, while another ruleset gives another one
-- (seen 27 Nov 2026). Saved data is per account, so the number keeps rulesets apart.
-- House is "Horde", "Alliance" or "Neutral" (the goblin houses in Booty Bay,
-- Gadgetzan and Everlook). At the auction house it is that house's; anywhere else
-- the player's own faction's.
function private:AuctionKey()
	local internal = parts.Internal
	return private:Server() .. "-" .. ((internal and internal.house) or private:PlayerHouse())
end

local server
function private:Server()
	if not server then
		local guid = UnitGUID("player")
		server = type(guid) == "string" and guid:match("^Player%-(%d+)%-") or nil
	end
	return server or "0"
end

function private:PlayerHouse()
	local faction = UnitFactionGroup("player")
	if faction == "Horde" or faction == "Alliance" then
		return faction
	end
	return "Neutral"
end

-- The house of the auctioneer being talked to. A goblin auctioneer has no
-- faction (or "Neutral"); without an NPC to ask, assume the player's own house.
function private:CurrentHouse()
	if not UnitExists("npc") then
		return private:PlayerHouse()
	end
	local faction = UnitFactionGroup("npc")
	if faction == "Horde" or faction == "Alliance" then
		return faction
	end
	return "Neutral"
end

function private:Timeslice(whole)
	local ts = GetServerTime() / 3600
	if whole then ts = floor(ts) end
	return ts
end

--[[ setting adjusted due to manifest conflict
-- This is all the outside world is allowed to access.
local major, minor, release, revision = strsplit(".", AUC_VERSION)
private.Auctioneer = {
	Version = AUC_VERSION,
	MajorVersion = major,
	MinorVersion = minor,
	RelVersion = release,
	Revision = revision,
}
]]--
local major, minor, release, revision = strsplit(".", AUC_VERSION)
Auctioneer.Version = AUC_VERSION
Auctioneer.MajorVersion = major
Auctioneer.MinorVersion = minor
Auctioneer.RelVersion = release
Auctioneer.Revision = revision

function private:Booted()
	-- "private." removed from function for manifest compatibility; all items: private.Auctioneer -> Auctioneer
	Auctioneer.Booted = nil

	Auctioneer.Trigger = private.Trigger
	Auctioneer.AuctionKey = private.AuctionKey
	Auctioneer.PlayerHouse = private.PlayerHouse
	Auctioneer.CurrentHouse = private.CurrentHouse
	Auctioneer.Timeslice = private.Timeslice

	Auctioneer.Stat = parts.Statistics.NewStat
	Auctioneer.Point = parts.Statistics.NewPoint
	Auctioneer.Points = parts.Statistics.NewPoints
	Auctioneer.Statistics = parts.Statistics.Stats

	Auctioneer.Item = parts.Items.NewItem

	Auctioneer.GUI = parts.GUI.Components
	Auctioneer.Money = parts.GUI.Money

	Auctioneer.Dump = parts.Internal.Dump
	Auctioneer.DumpOne = parts.Internal.DumpOne
	Auctioneer.Log = parts.Internal.Log
	Auctioneer.Debugging = parts.Internal.Debugging
	Auctioneer.RecordItemLevel = parts.Internal.RecordItemLevel
	Auctioneer.ItemGroupedByLevel = parts.Internal.ItemGroupedByLevel
	Auctioneer.RecordVariant = parts.Internal.RecordVariant
	Auctioneer.VariantKeys = parts.Internal.VariantKeys
	Auctioneer.VariantFromLink = parts.Internal.VariantFromLink
	Auctioneer.Ago = parts.Internal.Ago
	Auctioneer.Setting = parts.Internal.Setting
	Auctioneer.SetSetting = parts.Internal.SetSetting
	Auctioneer.settingDefaults = parts.Internal.settingDefaults
	Auctioneer.ItemKeyKey = parts.Internal.ItemKeyKey
	Auctioneer.ItemKeyString = parts.Internal.ItemKeyString
	Auctioneer.ItemKeyFromLink = parts.Internal.ItemKeyFromLink
	Auctioneer.ItemKeyFromString = parts.Internal.ItemKeyFromString

	private.booted = true
end

-- "private." removed from the next block for manifest compatibility; all items: private.Auctioneer -> Auctioneer
Auctioneer.Boot = private.Boot
Auctioneer.Booted = private.Booted
Auctioneer.Const = private.Const
Auctioneer.Module = private.Module

--[[ commented out due to manifest conflict
-- Expose the global Auctioneer object.
Auctioneer = {}
setmetatable(Auctioneer, {__index = private.Auctioneer})
]]--

loadedOrLoading, loaded = C_AddOns.IsAddOnLoaded(addonName)
if loadedOrLoading then
    -- Fix: Ensure Locale exists before calling OnLoad
    if Auctioneer.Locale and Auctioneer.Locale.OnLoad then
        Auctioneer.Locale.OnLoad() 
    else
        -- If it doesn't exist yet, we'll let the specific Locale file 
        -- handle its own loading when it gets parsed by the game engine.
        print("Auctioneer: Locale not yet initialized, skipping early load.")
    end
end