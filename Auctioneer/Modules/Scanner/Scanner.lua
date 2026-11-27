if not Auctioneer then return end

-- Create a new Auctioneer module.
local Module = Auctioneer:Module("Scanner")
local Const = Auctioneer:Const()

-- We will fire this off when we have items.
Const.Trigger:Add("ScannerItemsPush")
Const.Trigger:Add("ScannerItemsCompleted")

local progressFrame

local PUSH_BLOCK_SIZE = 50
-- Soft budget for saving statistics, in ms per frame: checked after each block, so a frame can
-- run one block over it, and the first frame also carries Collect().
-- ponytail: fixed 8ms; tie it to the frame rate if 8ms ever stutters
local PUSH_FRAME_BUDGET_MS = 8

-- Hook our method
function Module:Boot(hook)
	hook(Const.BrowseResultsAvailable, Module.BrowseResultsAvailable)
	hook(Const.AuctionHouseOpened, Module.AuctionHouseOpened)
	hook(Const.AuctionHouseClosed, Module.AuctionHouseClosed)
	hook(Const.DisplayModeChanged, Module.DisplayModeChanged)
	hook(Const.ThrottledSystemReady, Module.ThrottledSystemReady)

	Module:CreateProgress()
end

-- Our job:
--   Page through the browse results until the auction house has sent them all.
--   Build an item from each browse result. Item key info (name, icon, quality)
--   is not needed to record prices, so the scan never waits for it; display
--   code fetches it lazily.
--   Push the items to the statistics modules.

function Module:BrowseResultsAvailable(type, results)
	-- We have some browse results here, so lets process them.
	self:Fetch(type, results)
end

-- A full scan is a browse with an empty search box, no category, no level range
-- and Blizzard's default filters. Opening the auction house starts one when the
-- last full scan is older than the autoScanHours setting (at least an hour). One
-- scan per visit, because you opened it: Auctioneer never searches on a timer.
local function staleSeconds()
	return math.max(1, Auctioneer:Setting("autoScanHours") or 1) * 3600
end

-- Blizzard's default browse filters, as the array a query carries.
local function defaultFilters()
	local filters = {}
	for filter, on in pairs(AUCTION_HOUSE_DEFAULT_FILTERS or {}) do
		if on then
			tinsert(filters, filter)
		end
	end
	return filters
end

local function sameSet(a, b)
	if #a ~= #b then return false end
	local seen = {}
	for _, v in ipairs(a) do seen[v] = true end
	for _, v in ipairs(b) do
		if not seen[v] then return false end
	end
	return true
end

function Module.IsFullQuery(query)
	if not query or (query.searchString or "") ~= "" then return false end
	if query.itemClassFilters and #query.itemClassFilters > 0 then return false end
	if (query.minLevel or 0) > 0 or (query.maxLevel or 0) > 0 then return false end
	if AUCTION_HOUSE_DEFAULT_FILTERS and not sameSet(query.filters or {}, defaultFilters()) then
		return false
	end
	return true
end

-- Seconds since the last full scan finished, or nil if there never was one.
function Module:ScanAge()
	local scans = AuctioneerData and AuctioneerData.lastFullScans
	local last = scans and scans[Auctioneer:AuctionKey()]
	return last and (GetServerTime() - last)
end

function Module:AuctionHouseOpened()
	self:Reset()
	self:HookSearch()
	if self.autoScanPending then
		return
	end
	self.autoScanPending = true
	-- Let the auction house finish opening before searching.
	C_Timer.After(1, function()
		self.autoScanPending = false
		self:AutoScan(5)
	end)
end

-- Start a full scan if the prices are stale. Retries a few times while the
-- auction house throttle is busy.
function Module:AutoScan(tries)
	if not Auctioneer:Setting("autoScan") then
		return
	end
	if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or self.scanning then
		return
	end
	if AuctionHouseFrame:GetDisplayMode() ~= AuctionHouseFrameDisplayMode.Buy then
		return
	end
	local age = self:ScanAge()
	if age and age < staleSeconds() then
		return
	end
	if not C_AuctionHouse.IsThrottledMessageSystemReady() then
		if tries > 1 then
			C_Timer.After(1, function() self:AutoScan(tries - 1) end)
		end
		return
	end
	if Auctioneer:Setting("announceScan") then
		if age then
			print(format("|cffffd100Auctioneer:|r last scan was %s, scanning the auction house.", Auctioneer:Ago(age)))
		else
			print("|cffffd100Auctioneer:|r no scan yet, scanning the auction house.")
		end
	end
	Module.autoQueryPending = true
	C_AuctionHouse.SendBrowseQuery({
		searchString = "",
		sorts = {},
		filters = defaultFilters(),
		itemClassFilters = {},
	})
end

-- Note which kind of browse each search is, whoever sent it (post-hook, reads only).
-- And a hint on Blizzard's Search button: an empty search is also a price scan.
function Module:HookSearch()
	if not self.queryHooked then
		self.queryHooked = true
		hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", function(query)
			Module.lastQueryFull = Module.IsFullQuery(query)
			-- Our own auto-scan query, or one the player started.
			Module.lastQueryAuto = Module.autoQueryPending or false
			Module.autoQueryPending = false
		end)
	end

	local searchBar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
	local button = searchBar and searchBar.SearchButton
	if button and not self.buttonHooked then
		self.buttonHooked = true
		button:HookScript("OnEnter", function(b)
			GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
			if Module:SearchBarIsFull() then
				GameTooltip:SetText("Scan")
				GameTooltip:AddLine("Auctioneer: scan the whole auction house for prices.", 1, 1, 1, true)
			else
				GameTooltip:SetText("Search")
				GameTooltip:AddLine("Auctioneer: to scan the whole auction house, clear the search box, the category and any filters.", 1, 1, 1, true)
			end
			local age = Module:ScanAge()
			GameTooltip:AddLine(age and ("Last scan: "..Auctioneer:Ago(age)) or "No scan yet.", 0.6, 0.6, 0.6, true)
			GameTooltip:Show()
		end)
		button:HookScript("OnLeave", function() GameTooltip:Hide() end)
		self:HookSearchLabel(searchBar)
	end
end

-- The query the search bar would send now, as far as a full scan is concerned.
function Module:SearchBarQuery()
	local searchBar = AuctionHouseFrame.SearchBar
	local query = {searchString = searchBar.SearchBox:GetText() or ""}
	query.minLevel, query.maxLevel = searchBar.FilterButton:GetLevelRange()
	query.filters = searchBar.FilterButton:CalculateFiltersArray()
	local categories = AuctionHouseFrame.CategoriesList
	local selected = categories and categories.GetSelectedCategory and categories:GetSelectedCategory()
	query.itemClassFilters = selected and {selected} or {}
	return query
end

function Module:SearchBarIsFull()
	local ok, query = pcall(self.SearchBarQuery, self)
	return ok and Module.IsFullQuery(query)
end

-- The Search button reads "Scan" while pressing it would scan the whole auction house.
function Module:UpdateSearchLabel()
	local button = AuctionHouseFrame and AuctionHouseFrame.SearchBar and AuctionHouseFrame.SearchBar.SearchButton
	if not button then return end
	local label = SEARCH or "Search"
	if Auctioneer:Setting("scanLabel") and self:SearchBarIsFull() then
		label = "Scan"
	end
	if button:GetText() ~= label then
		button:SetText(label)
	end
end

-- Follow what changes a search: its text, the category, the filters and level range.
function Module:HookSearchLabel(searchBar)
	local update = function() Module:UpdateSearchLabel() end
	if searchBar.SearchBox then
		searchBar.SearchBox:HookScript("OnTextChanged", update)
	end
	searchBar:HookScript("OnShow", update)
	if searchBar.UpdateClearFiltersButton then
		hooksecurefunc(searchBar, "UpdateClearFiltersButton", update)
	end
	local categories = AuctionHouseFrame.CategoriesList
	if categories and categories.SetSelectedCategory then
		hooksecurefunc(categories, "SetSelectedCategory", update)
	end
	update()
end

function Module:AuctionHouseClosed()
	self:Push()
	self:Reset()
end

function Module:DisplayModeChanged(displayMode)
	if self.scanning and displayMode ~= AuctionHouseFrameDisplayMode.Buy then
		self:Push()
		self:Reset()
	end
end

-- Add the current browse results to our list and keep fetching more until we
-- have all the results loaded.
function Module:Fetch(type, results)
	if AuctionHouseFrame:GetDisplayMode() ~= AuctionHouseFrameDisplayMode.Buy then
		if self.scanning then
			self:Push()
			self:Reset()
		end
		return
	end

	if type == "updated" then
		self.scanning = true
		self.fullScan = Module.lastQueryFull
		self.autoScan = Module.lastQueryAuto
		self.complete = false
		self.browseResults = C_AuctionHouse.GetBrowseResults()
		self.browseSize = 12000
		self:InvertedProgress(false)
		self.marks = {}
		self:Mark("start")
		Auctioneer:Log("scan started")
	elseif not self.scanning then
		return
	else
		tAppendAll(self.browseResults, results)
		Auctioneer:Log("page received: %d results so far", #self.browseResults)
	end

	local numResults = #self.browseResults
	if C_AuctionHouse.HasFullBrowseResults() then
		self.complete = true
		self:Mark("fetched")
		return self:Push()
	end

	if numResults > self.browseSize - 1000 then
		self.browseSize = self.browseSize + 1000
	end

	self:SetProgress(numResults/self.browseSize * 100,
		("Getting results: %d"):format(numResults))

	self:RequestMore()
end

-- Ask for the next page as soon as the client's throttle allows it. When it does
-- not, wait for AUCTION_HOUSE_THROTTLED_SYSTEM_READY, with a 1s retry as backstop
-- in case that event never comes.
function Module:RequestMore()
	if not self.scanning then
		return
	end
	if AuctionHouseFrame:GetDisplayMode() ~= AuctionHouseFrameDisplayMode.Buy then
		self:Push()
		self:Reset()
		return
	end

	if C_AuctionHouse.IsThrottledMessageSystemReady() then
		self.waitingThrottle = false
		C_AuctionHouse.RequestMoreBrowseResults()
		return
	end

	Auctioneer:Log("throttle wait")
	self.waitingThrottle = true
	if not self.backstopPending then
		self.backstopPending = true
		C_Timer.After(1.0, self.BackstopCallback)
	end
end

-- Retry the page request we are holding back for the throttle, if any.
function Module:ResumeAfterThrottle(reason)
	if self.waitingThrottle then
		Auctioneer:Log(reason)
		self:RequestMore()
	end
end

function Module:ThrottledSystemReady()
	self:ResumeAfterThrottle("throttle ready")
end

-- Static callback function to use in C_Timer.After calls
function Module.BackstopCallback()
	Module.backstopPending = false
	Module:ResumeAfterThrottle("throttle backstop retry")
end

-- Build an item from every browse result received so far.
function Module:Collect()
	local items = {}
	for _, itemData in ipairs(self.browseResults or {}) do
		--[[
		itemData = { itemKey, appearanceLink, totalQuantity, minPrice, containsOwnerItem }
		itemKey = { itemID, itemLevel, itemSuffix, battlePetSpeciesID }
		]]
		local itemKey = itemData.itemKey
		Auctioneer:RecordItemLevel(itemKey)
		Auctioneer:RecordVariant(itemKey)
		tinsert(items, Auctioneer:Item{
			id = Auctioneer:ItemKeyKey(itemKey),
			itemKey = itemKey,
			itemData = itemData,
		})
	end
	return items
end

-- Collate the browse results received so far and push them to the stats modules.
function Module:Push()
	if not self.scanning then
		return
	end
	self.scanning = false
	-- Only a finished full scan counts as fresh prices; a filtered search or
	-- one cut short by a tab switch does not.
	if self.fullScan and self.complete and AuctioneerData then
		AuctioneerData.lastFullScans = AuctioneerData.lastFullScans or {}
		AuctioneerData.lastFullScans[Auctioneer:AuctionKey()] = GetServerTime()
	end

	local items = self:Collect()
	local auto = self.autoScan
	self.autoScan = false
	-- This scan's timing travels with its push: a new scan may start meanwhile.
	local marks = self.marks
	self.marks = nil
	if marks then
		marks.processed = GetTime()
	end

	self:InvertedProgress(false)
	self:SetProgress(0, "Sending items")

	-- Push the items to the stats modules in blocks, as many blocks per frame as fit in
	-- the frame budget: a big scan is saved in a few frames without stalling the game.
	coroutine.wrap(function ()
		local co = coroutine.running()
		local function resume() coroutine.resume(co) end

		local pos = 1
		local size = #items
		local frameStart = debugprofilestop()
		while pos <= size do
			local to = math.min(pos + PUSH_BLOCK_SIZE - 1, size)
			Auctioneer:Trigger(Const.ScannerItemsPush, {unpack(items, pos, to)})
			self:SetProgress(to / size * 100, ("Statistics: %d"):format(to))
			pos = to + 1

			if pos <= size and debugprofilestop() - frameStart >= PUSH_FRAME_BUDGET_MS then
				C_Timer.After(0, resume)
				coroutine.yield()
				frameStart = debugprofilestop()
			end
		end
		-- Only the progress bar: a new scan may already be running.
		self:ClearProgress()

		-- The ScannerItemsCompleted listeners (Deal finder) are heavy: give them a frame of their own.
		C_Timer.After(0, resume)
		coroutine.yield()

		if marks then
			marks.pushed = GetTime()
		end
		self:ReportTiming(#items, marks)
		-- auto: the scan Auctioneer started on opening, not one the player clicked.
		Auctioneer:Trigger(Const.ScannerItemsCompleted, items, auto)
	end)()
end

-- Reset state.
function Module:Reset()
	self.scanning = false
	self:ClearProgress()
end

-- Scan timing: phases are marked as the scan goes; one line per finished scan.
function Module:Mark(phase)
	if self.marks then
		self.marks[phase] = GetTime()
	end
end

function Module:ReportTiming(count, marks)
	if not Auctioneer:Debugging() then
		return
	end
	if not (marks and marks.start and marks.fetched and marks.processed and marks.pushed) then
		return
	end
	local line = format("Auctioneer scan: %d results | fetch %.1fs | process %.1fs | stats %.1fs",
		count, marks.fetched - marks.start, marks.processed - marks.fetched, marks.pushed - marks.processed)
	Auctioneer:Log("%s", line)
	print(line)
end

function Module:CreateProgress()
	progressFrame = CreateFrame("STATUSBAR", "AuctioneerScannerFrame", AuctionHouseFrame)
	progressFrame:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "TOPRIGHT")
	progressFrame:SetWidth(200)
	progressFrame:SetHeight(20)
	progressFrame:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
	progressFrame:GetStatusBarTexture():SetHorizTile(false)
	progressFrame:GetStatusBarTexture():SetVertTile(false)
	progressFrame:SetMinMaxValues(0, 100)
	progressFrame:Hide()

	progressFrame.bg = progressFrame:CreateTexture(nil, "BACKGROUND")
	progressFrame.bg:SetTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
	progressFrame.bg:SetAllPoints(true)

	progressFrame.value = progressFrame:CreateFontString(nil, "OVERLAY")
	progressFrame.value:SetPoint("LEFT", progressFrame, "LEFT", 4, 0)
	progressFrame.value:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	progressFrame.value:SetJustifyH("LEFT")
	progressFrame.value:SetTextColor(0.6, 0.6, 0.6)

	progressFrame.Set = Module.SetProgress
	progressFrame.Clear = Module.ClearProgress
	progressFrame.Inverted = Module.InvertedProgress

	self:InvertedProgress(false)
end

function Module:InvertedProgress(invert)
	if invert then
		progressFrame:SetStatusBarColor(0.1, 0.1, 0.1)
		progressFrame.bg:SetVertexColor(0, 0.35, 0.65)
	else
		progressFrame:SetStatusBarColor(0, 0.35, 0.65)
		progressFrame.bg:SetVertexColor(0.1, 0.1, 0.1)
	end
	progressFrame.invert = invert
end

function Module:SetProgress(percent, text)
	progressFrame:Show()
	progressFrame:SetValue(percent)
	progressFrame.value:SetText(text)
end

function Module:ClearProgress()
	progressFrame:Hide()
end
