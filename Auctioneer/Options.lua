-- Auctioneer settings page: Options > AddOns > Auctioneer, or /auc.
-- A canvas panel (so labels get the room they need), drawn with Blizzard's own
-- checkbox and slider widgets, in three boxed sections.
-- Values live in AuctioneerSettings (saved per account); modules read them with
-- Auctioneer:Setting(key), which falls back to the defaults in Internal.lua.
if not Auctioneer then return end
if not (Settings and Settings.RegisterCanvasLayoutCategory and EventUtil) then return end

local ROW_HEIGHT = 28
local BOX_PAD = 10
local SLIDER_WIDTH = 220
local VALUE_WIDTH = 70
local INDENT = 22

local controls = {}   -- every control has :Refresh() to show the saved value

local function setting(key) return Auctioneer:Setting(key) end
local function refreshAll()
	for _, control in ipairs(controls) do control:Refresh() end
end

local function tooltip(owner, title, text)
	owner:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	owner:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A boxed section: gold title above, short grey description, then rows.
local function section(parent, anchor, title, description, rows)
	local heading = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	heading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
	heading:SetText(title)

	local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	box:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
	box:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
	box:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = {left = 3, right = 3, top = 3, bottom = 3},
	})
	box:SetBackdropColor(0, 0, 0, 0.3)
	box:SetBackdropBorderColor(0.6, 0.5, 0.3, 0.8)

	local text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("TOPLEFT", box, "TOPLEFT", BOX_PAD + 2, -BOX_PAD)
	text:SetPoint("RIGHT", box, "RIGHT", -BOX_PAD, 0)
	text:SetJustifyH("LEFT")
	text:SetTextColor(0.7, 0.7, 0.7)
	text:SetText(description)

	box:SetHeight(BOX_PAD + 14 + 6 + rows * ROW_HEIGHT + BOX_PAD)
	box.nextRow = 0
	box.top = BOX_PAD + 14 + 6
	return box
end

local function rowFrame(box, indent)
	local row = CreateFrame("Frame", nil, box)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", box, "TOPLEFT", BOX_PAD + (indent and INDENT or 0), -(box.top + box.nextRow * ROW_HEIGHT))
	row:SetPoint("RIGHT", box, "RIGHT", -BOX_PAD, 0)
	box.nextRow = box.nextRow + 1
	return row
end

local function checkbox(box, key, label, help, indent)
	local row = rowFrame(box, indent)
	local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	check:SetPoint("LEFT", row, "LEFT", 0, 0)

	local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("LEFT", check, "RIGHT", 4, 1)
	text:SetText(label)
	-- The label is part of the button: clicking it toggles too.
	check:SetHitRectInsets(0, -(text:GetStringWidth() + 8), 0, 0)

	check:SetScript("OnClick", function(self)
		Auctioneer:SetSetting(key, self:GetChecked() and true or false)
		PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		refreshAll()
	end)
	tooltip(check, label, help)

	local control = {row = row}
	function control:Refresh()
		check:SetChecked(setting(key) and true or false)
	end
	function control:SetEnabled(on)
		check:SetEnabled(on)
		text:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
	end
	tinsert(controls, control)
	return control
end

local function slider(box, key, label, low, high, step, format, help, indent)
	local row = rowFrame(box, indent)
	local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("LEFT", row, "LEFT", 4, 0)
	text:SetText(label)

	local widget = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
	widget:SetSize(SLIDER_WIDTH, ROW_HEIGHT)
	widget:SetPoint("RIGHT", row, "RIGHT", -VALUE_WIDTH, 0)
	widget:Init(setting(key), low, high, (high - low) / step,
		{[MinimalSliderWithSteppersMixin.Label.Right] = function(value) return format(floor(value + 0.5)) end})
	widget:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		value = floor(value + 0.5)
		if value ~= setting(key) then
			Auctioneer:SetSetting(key, value)
		end
	end, row)
	tooltip(widget.Slider, label, help)

	local control = {row = row}
	function control:Refresh()
		widget:SetValue(setting(key))
	end
	function control:SetEnabled(on)
		widget:SetEnabled(on)
		text:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
	end
	tinsert(controls, control)
	return control
end

local function hours(value) return value == 1 and "1 hour" or format("%d hours", value) end
local function percent(value) return format("%d%%", value) end
local function silver(value) return value == 0 and "any" or format("%d silver", value) end

EventUtil.ContinueOnAddOnLoaded("Auctioneer", function()
	AuctioneerSettings = AuctioneerSettings or {}

	local panel = CreateFrame("Frame")
	panel:Hide()

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
	title:SetText("Auctioneer")

	local version = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
	version:SetText((C_AddOns.GetAddOnMetadata("Auctioneer", "Version") or "")..
		"   |cff808080/auc opens this page|r")

	local scanning = section(panel, title, "Scanning",
		"One scan when you open the auction house and the prices are old. Never on a timer.", 3)
	local autoScan = checkbox(scanning, "autoScan", "Scan when the auction house opens",
		"When you open the auction house and the last scan is old, scan it once.")
	local announce = checkbox(scanning, "announceScan", "Announce the scan in chat",
		"Print a line in chat when Auctioneer starts a scan by itself.", true)
	local hoursSlider = slider(scanning, "autoScanHours", "Only if the last scan is older than", 1, 24, 1, hours,
		"How old the last full scan must be before opening the auction house scans again.", true)

	local deals = section(panel, scanning, "Deal finder",
		"Auctions listed well below what a vendor pays, or below the item's usual price.", 3)
	checkbox(deals, "dealsOpenAfterScan", "Open after a scan you start",
		"Show the Deal finder when a scan you started finishes. The automatic scan never opens it.")
	slider(deals, "dealsMinDiscount", "Minimum discount", 5, 90, 5, percent,
		"How far below the vendor or usual price an auction must be. The Deal finder's own slider sets the same value.")
	slider(deals, "dealsMinProfit", "Minimum profit", 0, 50, 1, silver,
		"Only list deals that make at least this much after the auction house cut.")

	local selling = section(panel, deals, "Selling",
		"Help on the auction house Sell tab.", 3)
	checkbox(selling, "vendorCheck", "Vendor check in the Valuer",
		"Compare the auction, after the 5% cut, with selling to a vendor.")
	checkbox(selling, "sellSlotSwap", "Keep the old item when swapping the sell item",
		"Dropping a new item on the sell slot leaves the old one in your bags instead of on the cursor.")
	slider(selling, "staleHours", "Price history counts as old after", 1, 48, 1, hours,
		"In the Valuer, 'last seen' turns orange when an item's newest price is older than this.")

	-- The scan's own options only matter while it is on.
	local refreshControls = refreshAll
	refreshAll = function()
		refreshControls()
		local on = setting("autoScan") and true or false
		announce:SetEnabled(on)
		hoursSlider:SetEnabled(on)
	end

	-- Settings panel hooks: shown, and the Defaults button.
	panel.OnRefresh = function() refreshAll() end
	panel.OnDefault = function()
		wipe(AuctioneerSettings)
		refreshAll()
	end
	panel:SetScript("OnShow", function() refreshAll() end)

	local category = Settings.RegisterCanvasLayoutCategory(panel, "Auctioneer")
	Settings.RegisterAddOnCategory(category)
	Auctioneer.settingsCategory = category

	SLASH_AUCTIONEER1 = "/auctioneer"
	SLASH_AUCTIONEER2 = "/auc"
	SlashCmdList.AUCTIONEER = function()
		Settings.OpenToCategory(category:GetID())
	end
end)
