local ADDON, finder = ...
--SavedVariablesPerCharacter: FinderOptions
--SavedVariables: FinderCache
local FINDER_VERSION = GetAddOnMetadata(ADDON, "Version")

local ExpansionData = {
	[0] = {name = "Vanilla", maxItemID = 25000, color = "|cffe6cc80"},
	[1] = {name = "TBC", maxItemID = 190000, color = "|cff67f100"},
}

-- local vars
local cPurple = "|cffa335ee"
local confirmTimer
local confirmWipe = false -- used for 2 step cache wipe command
local WIPE_TIMER_DURATION = 60 -- safety timer for user to type '/finder wipe' a 2nd time in order to wipe the item cache
local cItemExists = C_Item.DoesItemExistByID

-- some options
local MAX_HITS = 20
local hush = false -- this silences rebuild progress updates for the duration of the player session

-- cache rebuild stuff
-- TODO: some of this should be player options
local CURRENT_EXPANSION = GetExpansionLevel()
local CACHE_MAX_ITEMID = ExpansionData[CURRENT_EXPANSION].maxItemID
local CACHE_STOP_REBUILD = false
local CACHE_REBUILDING = false -- changes to an int when rebuilding, indicating current itemID position
local CACHE_IS_PREPARED = false
local AVERAGE_FRAMERATE = 60   -- reasonable first guess, hardly matters
local CACHE_ITEMSPERFRAME = 1000 / 60 -- safe default, targeting ~30 second rebuild
local MAX_WAIT_TIME = 5 -- the maximum amount of time we're willing to wait for GetItemInfo() to return results. If exceeded, print what we got so far, plus a warning
local CACHE_CURRENT_REQUESTS = {} -- item info queue

-- forward dec
local addOrUpdateCache
local prepareCache

-- enums
local SCAN_SPEED = {
	fast = 2000,
	normal = 1000,
	slow = 250,
}

-- helpers
local fmsg = function(msg)
	return string.format("/|cffa335eeFinder [%s%s|r]|r:: %s", ExpansionData[CURRENT_EXPANSION].color, ExpansionData[CURRENT_EXPANSION].name, msg)
end

local function getDefaults(category)
	if not finder.defaults[category] then
		error("Trying to load defaults for a non-existant category: "..tostring(category))
	end
	local t = {}
	for k, v in pairs(finder.defaults[category]) do
		t[k] = v
	end

	return t
end

-- quick and dirty table_contains implementation for array tables
local function tcontains(table, item)
	local index = 1
	while table[index] do
		if (item == table[index]) then
			return index
		end
		index = index + 1
	end

	return false
end

-- maintains an average framerate and item scanning speed
local function UpdateItemsPerFrame()
	AVERAGE_FRAMERATE = (AVERAGE_FRAMERATE + GetFramerate()) / 2
	local speed = SCAN_SPEED[FinderOptions.speed] or SCAN_SPEED.normal
	CACHE_ITEMSPERFRAME = math.ceil(speed / AVERAGE_FRAMERATE)

	C_Timer.After(5, UpdateItemsPerFrame)
end

-- event frame setup
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

local handlers = {}

function handlers.ADDON_LOADED(self, ...)
	if ... == ADDON then
		frame:UnregisterEvent("ADDON_LOADED")

		-- Hook up SavedVariable
		FinderOptions = FinderOptions or getDefaults("options")

		-- Check if we need to do any forced setting upgrades
		if not FinderOptions._ver then
			-- < v0.1.2, re-set 'speed' opt to normal
			FinderOptions.speed = "normal"
			FinderOptions._ver = FINDER_VERSION
		end
		if FinderOptions.greeting == nil then
			-- greeting option added in v1.9
			FinderOptions.greeting = true
		end

		if (not (type(FinderCache) == "table")) then
			prepareCache()
		else
			CACHE_IS_PREPARED = true
		end

		if FinderOptions.greeting then
			print(fmsg("|cff9d9d9dby |cffffffffAvael|r |cff9d9d9d@ |cff00ccffHydraxian Waterlords EU |cff9d9d9dhas loaded \\o/"))
		end

		-- check database version and try to upgrade if possible
		local dbOutdated = finder.db.isDatabaseOutdated(FinderCache)

		if dbOutdated == 0 then
			local tocv = select(4, GetBuildInfo())
			if not (tocv == FinderCache.__tocversion) then
				-- let player know the database is probably out of date
				print(fmsg("|cfff00000Hey, the item cache may be out of date (Major game update?)! You should consider rebuilding it with|r |cffffffff'/finder rebuild'|r"))
			elseif (not FinderCache.completedScan) then
				-- let the player know there doesn't appear to be any item cache built
				print(fmsg("|cfff00000It looks like you have not built the item cache! Try|r |cffffffff'/finder rebuild'|cfff00000 to populate the cache."))
			else
				if FinderOptions.greeting then
					print(fmsg("Item cache looks |cff00f000OK|r."))
				end
			end
		else
			-- let the player know the db is incompatible and should be rebuilt.
			if dbOutdated < 0 then
				print(fmsg("|cfff00000!!Item cache is from an old version of Finder and may not work!|r"))
			elseif dbOutdated > 0 then
				print(fmsg("|cfff00000!!Item cache is from a future version of Finder and may not work! |cff9d9d9dAre you a time traveler?|r"))
			end

			print(fmsg("|cfff00000!!Please rebuild (|cffffffff'/finder rebuild'|cfff00000) to build a fresh item cache.|r"))
		end

		-- start the rate tracker, it'll self-sustain after this call
		C_Timer.After(2, UpdateItemsPerFrame)
	end
end

function handlers.GET_ITEM_INFO_RECEIVED(self, ...)
	local itemID, success = ...
	if success then
		addOrUpdateCache(itemID)
	end
end

frame:SetScript("OnEvent", function(self, event, ...)
	if handlers[event] then
		handlers[event](self, ...)
	end
end)

-- rest of the fucking owl
--------------------------

-- used to prepare the cache structure (after a wipe, fresh install, db failed verification, etc)
function prepareCache()
	-- using WoW's wipe() since 'data = {}' simply resets the pointer and the global SavedVariable doesn't actually get wiped
	if FinderCache then
		wipe(FinderCache)
	else
		FinderCache = {}
	end

	finder.db.initNewDB(FinderCache)

	FinderCache.completedScan = false
	CACHE_IS_PREPARED = true
end

-- add or update an item in the item cache
function addOrUpdateCache(validID)
	if not CACHE_IS_PREPARED then
		error("Trying to add or update FinderCache before cache has been prepared?! This is an error!")
	end

	local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
	itemEquipLoc, itemIcon, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID,
	isCraftingReagent = GetItemInfo(validID)

	FinderCache[itemClassID or -1][validID] = itemName
end

-- stop any in-progress cache rebuild
local function stopCacheRebuild()
	CACHE_REBUILDING = false
	CACHE_STOP_REBUILD = true
	hush = false
	FinderCache.completedScan = false -- we're in an impartial scan state
end

-- rebuild item cache
local function rebuildCache(startID, endID)
	if not CACHE_REBUILDING then
		CACHE_STOP_REBUILD = false

		local validIDs = {}
		for i = startID or 0, endID or CACHE_MAX_ITEMID do
			if cItemExists(i) then
				tinsert(validIDs, i)
			end
		end

		frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

		CACHE_REBUILDING = 1
		local tickerHandle
		local lastUpdate = 0
		local startedTimer = GetTime()
		local itemsTotal = #validIDs

		print(fmsg(string.format("Rebuilding item cache... ETA ~%i seconds", itemsTotal / (CACHE_ITEMSPERFRAME * AVERAGE_FRAMERATE))))
		print(fmsg(("Type '/finder hush' to disable progress updates for this rebuild. Type '/finder stop' to abort the rebuild.")))

		local function worker()
			if CACHE_STOP_REBUILD or (not CACHE_REBUILDING) then
				tickerHandle:Cancel()
				CACHE_STOP_REBUILD = false
				CACHE_REBUILDING = false
			elseif CACHE_REBUILDING < #validIDs then
				local nextBatch = math.min(itemsTotal - CACHE_REBUILDING, CACHE_ITEMSPERFRAME)

				-- queries for a batch of items
				for i=CACHE_REBUILDING, (CACHE_REBUILDING + nextBatch) - 1 do
					GetItemInfo(validIDs[i])
				end

				CACHE_REBUILDING = CACHE_REBUILDING + nextBatch

				if (CACHE_REBUILDING - lastUpdate) >= FinderOptions.progressinterval then
					local progress = (CACHE_REBUILDING / itemsTotal)

					local itemsRemaining = itemsTotal - CACHE_REBUILDING
					local timePerUpdate = (GetTime() - startedTimer) / CACHE_REBUILDING
					local estimate = itemsRemaining * timePerUpdate

					if not hush then
						local msg = ("Rebuild status: %i/%i (%i%%), ~%i seconds remaining"):format(CACHE_REBUILDING - 1, itemsTotal, math.floor(progress*100), estimate	)
						print(fmsg(msg))
					end

					lastUpdate = CACHE_REBUILDING
				end
			else
				CACHE_REBUILDING = false
				frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
				hush = false
				FinderCache.completedScan = true
				FinderCache.__tocversion = select(4, GetBuildInfo())

				local msg = ("Finished rebuilding cache! Took: %.0f seconds"):format(((GetTime() - startedTimer)))
				print(fmsg(msg))
			end
		end

		tickerHandle = C_Timer.NewTicker(0, worker, itemsTotal) -- runs every frame
	end
end

-- print search results
local function printResults(results, hits, searchTime, expired)
	local output = DEFAULT_CHAT_FRAME
	local timeStr = ("|cff9d9d9d(%ims)|r"):format(math.floor(searchTime) * 1000)

	if expired then
		-- warn that our search expired and results may be incomplete
		local msg = ("(|cfff00000Servers response is slow (>%.1fs), search results may be incomplete. You may want to try again|r)"):format(MAX_WAIT_TIME)
		output:AddMessage(msg)
	end

	if hits == MAX_HITS then
		local msg = ("(|cfff00000Hit the result cap of |cff00ccff%i|r, try narrowing down your search!): %s"):format(MAX_HITS, timeStr)
		output:AddMessage(msg)
	else
		output:AddMessage(fmsg(("Found %i hits: %s"):format(hits, timeStr)))
	end

	for category, data in pairs(results) do
		output:AddMessage(("|cffe6cc80%s|r (%i):"):format(GetItemClassInfo(category), data.count))

		for k, item in pairs(data.items) do
			output:AddMessage(("    %s"):format(item.link))
		end
	end
end

-- perform actual item search
local function findItem(fragment)
	if not FinderCache.completedScan then
		print(fmsg("(|cfff00000INCOMPLETE or EMPTY ITEMCACHE!|r You should /finder rebuild)"))
	end

	print(fmsg("Searching for \"".. fragment .."\"..."))

	local startTime = GetTime()
	local maxhits = 20
	local hits = 0
	local results = {}
	local stop

	-- clear the itemQueue table in case it has any previous search queries. Said previous queries will be mercilessly abandoned!
	wipe(CACHE_CURRENT_REQUESTS)

	for category = 0, #FinderCache do
		local items = FinderCache[category]

		if stop then
			break
		else
			for id, name in pairs(items) do
				if name:lower():find(fragment) then
					results[category] = results[category] or {
						items = {},
						count = 0
					}

					results[category].count = results[category].count + 1

					tinsert(CACHE_CURRENT_REQUESTS, id)
					local item = Item:CreateFromItemID(id)


					item:ContinueOnItemLoad(function()
						local _, link = GetItemInfo(id)

						tinsert(results[category].items, {
							id = id,
							link = item:GetItemLink()
						})


						local qIndex = tcontains(CACHE_CURRENT_REQUESTS, id)
						if qIndex then
							tremove(CACHE_CURRENT_REQUESTS, qIndex)
						end
					end)

					hits = hits + 1

					if hits >= maxhits then
						stop = true
						break
					end
				end
			end
		end
	end

	-- only do something if we got >0 results
	if hits > 0 then
		local triggerTime = GetTime()
		local lastPoll = triggerTime
		local poller

		-- polls the itemQueue until it is either empty or we've exceeded the max wait time
		local function pollQueue()
			local time = GetTime()
			local waited = time - triggerTime
			local expired = (waited >= MAX_WAIT_TIME)

			if expired or (#CACHE_CURRENT_REQUESTS == 0) then
				printResults(results, hits, (time - startTime) - (lastPoll - time), expired)

				-- remember to stop the ticker
				poller:Cancel()
			end

			lastPoll = time
		end

		-- start polling the itemQueue
		poller = C_Timer.NewTicker(0.01, pollQueue)
	else
		print(fmsg("Found nothing at all while searching for \""..fragment.."\""))
	end
end

-- print generic help message
local function printHelp()
	print(fmsg("Quick help:"))
	print("    Search for items using '/find <anything>' or '/search <anything>'")
	print("      For example: /find searing arrows")
	print("      Results in : " .. "\124cffa335ee\124Hitem:2825::::::::60:::::\124h[Bow of Searing Arrows]\124h\124r")
	print("    To configure "..cPurple.."Finder|r, use '/finder <command/option>' instead.")
	print("      Notice the difference! |cff9d9d9d/find|r vs |cff9d9d9d/find|cffffffffer|r")
end

-- SlashCMD setup
SLASH_FIND1 = "/find"
SLASH_FIND2 = "/search"
SLASH_FINDER1 = "/finder"

-- SlashCmd handler for triggering a new item search
local function searchHandler(fragment, EditBox)
	fragment = strtrim(fragment) -- trim it
	fragment = fragment:lower() -- lowercase it

	if fragment:match("[^%s]") then
		findItem(fragment)
	else
		printHelp()
	end
end

-- SlashCmd handler for interacting with the addon configuration etc, NOT for searching (unless passing the 'search' argument)
local function commandHandler(msg, EditBox)
	-- force lowercase all messages
	msg = strtrim(msg:lower())

	-- split into parts
	local args = {}
	for v in string.gmatch(msg, "[^ ]+") do
		tinsert(args, v)
	end

	local cmd = args[1]
	if not cmd then
		printHelp()
		return false
	end

	if cmd == "wipe" then
		if confirmWipe then
			-- trigger wipe
			prepareCache()

			PlaySound(5694, "Master")
			print(fmsg("Item cache has been wiped! SpooOooky! |cfff90000Start rebuilding it using /finder rebuild|r"))
			if confirmTimer then
				confirmTimer:Cancel()
			end

			confirmWipe = false -- reset the confirmation step
		else
			print(fmsg("You are trying to wipe the Finder item cache. Type '/finder wipe' again within "..WIPE_TIMER_DURATION.." seconds to confirm!"))
			confirmWipe = true

			confirmTimer = C_Timer.NewTimer(WIPE_TIMER_DURATION, function()
				confirmWipe = false
				print(fmsg("Wipe timer expired..."))
			end)
		end
	elseif cmd == "wipesettings" then
		wipe(FinderOptions)
		for k, v in pairs(finder.defaults.options) do
			FinderOptions[k] = v
		end
		print(fmsg("User options been reset"))
	elseif cmd == "rebuild" then
		rebuildCache(tonumber(args[2]), tonumber(args[3]))
	elseif cmd == "search" or cmd == "find" or cmd == "s" then
		searchHandler(table.concat(args, " ", 2), EditBox)
	elseif cmd == "stop" or cmd == "abort" or cmd == "cancel" then
		print(fmsg("Stopping cache rebuild"))
		stopCacheRebuild()
	elseif cmd == "greeting" then
		FinderOptions.greeting = not FinderOptions.greeting
		print(fmsg(string.format("Login greeting now %s", FinderOptions.greeting and "enabled." or "disabled.")))
	elseif cmd == "set" then
		-- we're setting an option!
		local name, value = args[2], args[3]
		local result

		if name and value then

			if finder.defaults.options[name] then
				local valIsNumber = (type(finder.defaults.options[name]) == "number")
				FinderOptions[name] = valIsNumber and tonumber(value) or tostring(value)
				result = ("Set option %s to value %s"):format(name, tostring(value))
			else
				result = ("No such option: %s"):format(name)
			end
		else
			result = ("Missing option or value (You said: /finder set %s %s)"):format(tostring(name), tostring(value))
		end

		print(fmsg(result))
	elseif cmd == "hush" or cmd == "shutup" then
		hush = not hush
		print(fmsg(("is now %s"):format(hush and ("|cff808080v e r y  q u i e t|r") or "|cff808080talkative again...|r")))
	elseif cmd == "status" then
		if (not FinderCache.completedScan) then
			print(fmsg("Item cache is |cfff00000invalid|r, you should |cff808080/finder rebuild|r it."))
		else
			print(fmsg("Item cache looks |cff00f000OK|r."))
		end
	else
		-- trap unknown commands and trigger help
		if msg ~= "" then
			print(fmsg("Unknown command \"".. msg .."\", did you mean to use |cff9d9d9d/find|r or |cff9d9d9d/search|r instead?"))
		end

		printHelp()
	end
end

SlashCmdList["FINDER"] = commandHandler
SlashCmdList["FIND"] = searchHandler