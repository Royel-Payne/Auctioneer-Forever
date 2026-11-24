-- Auctioneer settings page: Options > AddOns > Auctioneer, or /auc.
-- Values live in AuctioneerSettings (saved per account); modules read them with
-- Auctioneer:Setting(key), which falls back to the defaults in Internal.lua.
if not Auctioneer then return end
if not (Settings and Settings.RegisterVerticalLayoutCategory and EventUtil) then return end

local function silver(value)
	return value == 0 and "any" or format("%d silver", value)
end

local function hours(value)
	return value == 1 and "1 hour" or format("%d hours", value)
end

local function percent(value)
	return format("%d%%", value)
end

EventUtil.ContinueOnAddOnLoaded("Auctioneer", function()
	AuctioneerSettings = AuctioneerSettings or {}
	local defaults = Auctioneer.settingDefaults
	local category, layout = Settings.RegisterVerticalLayoutCategory("Auctioneer")

	local function checkbox(key, label, tooltip)
		local setting = Settings.RegisterAddOnSetting(category, "AUCTIONEER_"..key:upper(), key,
			AuctioneerSettings, Settings.VarType.Boolean, label, defaults[key])
		return Settings.CreateCheckbox(category, setting, tooltip), setting
	end

	local function slider(key, label, low, high, step, format, tooltip)
		local setting = Settings.RegisterAddOnSetting(category, "AUCTIONEER_"..key:upper(), key,
			AuctioneerSettings, Settings.VarType.Number, label, defaults[key])
		local options = Settings.CreateSliderOptions(low, high, step)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
		return Settings.CreateSlider(category, setting, options, tooltip), setting
	end

	local function header(text)
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
	end

	header("Scanning")
	local autoScan, autoScanSetting = checkbox("autoScan", "Scan when the auction house opens",
		"When you open the auction house and the last scan is old, scan it once. Auctioneer never scans on a timer.")
	local function autoScanOn() return autoScanSetting:GetValue() end
	slider("autoScanHours", "Only if the last scan is older than", 1, 24, 1, hours,
		"How old the last full scan must be before opening the auction house scans again.")
		:SetParentInitializer(autoScan, autoScanOn)
	checkbox("announceScan", "Say so in chat",
		"Print a line in chat when Auctioneer starts a scan by itself.")
		:SetParentInitializer(autoScan, autoScanOn)

	header("Deal finder")
	checkbox("dealsOpenAfterScan", "Open after a scan you start",
		"Show the Deal finder when a scan you started finishes. The automatic scan on opening never opens it.")
	slider("dealsMinDiscount", "Minimum discount", 5, 90, 5, percent,
		"Only list items at least this far below what a vendor pays, or below their usual auction price. The slider on the Deal finder sets the same value.")
	slider("dealsMinProfit", "Minimum profit", 0, 50, 1, silver,
		"Only list deals that make at least this much after the auction house cut.")

	header("Selling")
	checkbox("vendorCheck", "Vendor check in the Valuer",
		"Compare the auction, after the 5% cut, with selling to a vendor.")
	checkbox("sellSlotSwap", "Keep the old item when swapping the sell item",
		"Dropping a new item on the sell slot leaves the old one in your bags instead of on the cursor.")
	slider("staleHours", "Price history is old after", 1, 48, 1, hours,
		"In the Valuer, 'last seen' turns orange when an item's newest price is older than this.")

	Settings.RegisterAddOnCategory(category)
	Auctioneer.settingsCategory = category

	SLASH_AUCTIONEER1 = "/auctioneer"
	SLASH_AUCTIONEER2 = "/auc"
	SlashCmdList.AUCTIONEER = function()
		Settings.OpenToCategory(category:GetID())
	end
end)
