local ADDON, finder = ...
--SavedVariablesPerCharacter: FinderOptions
--SavedVariables: FinderCache

-- local vars
local cPurple = "|cffa335ee"
local confirmTimer
local confirmWipe = false -- used for 2 step cache wipe command
local WIPE_TIMER_DURATION = 60 -- safety timer for user to type '/finder wipe' a 2nd time in order to wipe the item cache

-- some options
local MAX_HITS = 20
local hush = false -- this silences rebuild progress updates for the duration of the player session

-- cache rebuild stuff
-- TODO: some of this should be player options
local CACHE_MAX_ITEMID = 25000
local CACHE_STOP_REBUILD = false
local CACHE_REBUILDING = false -- changes to an int when rebuilding, indicating current itemID position
local CACHE_IS_PREPARED = false
local CACHE_CURRENT_REQUESTS = {}

-- forward dec
local addOrUpdateCache
local prepareCache

-- enums
local SCAN_SPEED = {
	insane = 1000,
	fast = 500,
	normal = 250,
	slow = 100,
	glacial = 50,
	custom = true,
}

-- helpers
local fmsg = function(msg)
	return "/|cffa335eeFinder|r:: " .. msg
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

-- event frame setup
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

local handlers = {}

function handlers.ADDON_LOADED(self, ...)
	if ... == ADDON then
		frame:UnregisterEvent("ADDON_LOADED")

		print(fmsg("|cff9d9d9dby |cffffffffAvael|r |cff9d9d9d@ |cff00ccffHydraxian Waterlords EU |cff9d9d9dhas loaded \\o/"))

		-- Hook up SavedVariable
		FinderOptions = FinderOptions or getDefaults("options")

		if (not (type(FinderCache) == "table")) then
			prepareCache()
		else
			CACHE_IS_PREPARED = true
		end

		if (not FinderCache.completedScan) then
			print(fmsg("|cfff00000It looks like you have not built the item cache!|r Try '/finder rebuild' to populate the cache."))
		else
			print(fmsg("Item cache looks |cff00f000OK|r."))
		end
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

-- used to prepare the cache structure (after a wipe, or fresh start, f.ex.)
function prepareCache()
	FinderCache = {}
	for i = 0, NUM_LE_ITEM_CLASSS do
		local class = GetItemClassInfo(i)
		if class then
			FinderCache[i] = {}
		end
	end

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

	FinderCache[itemClassID][itemName] = {
		id = validID,
		link = itemLink
	}
end

-- stop any in-progress cache rebuild
local function stopCacheRebuild()
	CACHE_REBUILDING = false
	CACHE_STOP_REBUILD = true
	hush = false
end

-- queries for a batch of items
local function queryBatch(first, last)
	for i=first, last do
		GetItemInfo(i)
	end
end

-- rebuild item cache
local function rebuildCache(startID, endID)
	if not CACHE_REBUILDING then
		CACHE_STOP_REBUILD = false

		endID = endID or CACHE_MAX_ITEMID
		startID = startID or 0

		frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

		CACHE_REBUILDING = startID
		local tickerHandle
		local lastUpdate = startID
		local startedTimer = GetTime()

		local batchsize = (function()
			if FinderOptions.speed == "custom" then
				return FinderOptions.custombatchsize
			else
				return SCAN_SPEED[FinderOptions.speed] or SCAN_SPEED.glacial
			end
		end)()

		print(fmsg(("Rebuilding item cache... This should take about ~%.0f seconds. Type '/finder hush' to disable progress updates for this rebuild. Type '/finder stop' to abort the rebuild."):format(((endID-startID) / batchsize))))

		local function worker()
			if CACHE_STOP_REBUILD or (not CACHE_REBUILDING) then
				tickerHandle:Cancel()
			elseif CACHE_REBUILDING < endID then
				local nextBatch = math.min(endID - CACHE_REBUILDING, batchsize)
				queryBatch(CACHE_REBUILDING, CACHE_REBUILDING + nextBatch)

				CACHE_REBUILDING = CACHE_REBUILDING + nextBatch

				if (CACHE_REBUILDING - lastUpdate) >= FinderOptions.progressinterval then
					local itemsTotal = (endID-startID)
					local progress = (CACHE_REBUILDING / itemsTotal)

					local itemsProcessed = (CACHE_REBUILDING-startID)
					local itemsRemaining = itemsTotal - itemsProcessed

					local timePerUpdate = (GetTime() - startedTimer) / itemsProcessed

					local estimate = itemsRemaining * timePerUpdate

					if not hush then
						local msg = ("Rebuild status: %i/%i (%i%%), ~%i seconds remaining"):format(CACHE_REBUILDING, endID, math.floor(progress*100), estimate	)
						print(fmsg(msg))
					end

					lastUpdate = CACHE_REBUILDING
				end
			else
				CACHE_REBUILDING = false
				frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
				hush = false
				FinderCache.completedScan = true

				local msg = ("Finished rebuilding cache! Took: %.0f seconds"):format(((GetTime() - startedTimer)))
				print(fmsg(msg))
			end
		end

		tickerHandle = C_Timer.NewTicker(1, worker, endID-startID)
	end
end

local function findItem(fragment)
	if not FinderCache.completedScan then
		print(fmsg("(|cfff00000INCOMPLETE or EMPTY ITEMCACHE!|r You should /finder rebuild)"))
	end

	local maxhits = 20
	local hits = 0
	local results = {}
	local stop

	for category = 0, #FinderCache do
		local items = FinderCache[category]

		if stop then
			break
		else
			for name, item in pairs(items) do
				if name:lower():find(fragment) then
					results[category] = results[category] or {
						items = {},
						count = 0
					}

					results[category].count = results[category].count + 1
					tinsert(results[category].items, {
						id = item.id,
						link = item.link
					})

					hits = hits + 1

					if hits >= maxhits then
						stop = true
						break
					end
				end
			end
		end
	end

	--[[
	results = {
		[0] = {
			items = {},
			count = 0
		}
	}
	]]

	if hits > 0 then
		DEFAULT_CHAT_FRAME:AddMessage("\n")
		print(fmsg("Searching for \"".. fragment .."\"..."))
		local output = DEFAULT_CHAT_FRAME
		output:AddMessage(fmsg(("Found %i hits:"):format(hits)))
		if hits == MAX_HITS then
			output:AddMessage(("(|cfff00000Hit the result cap of |cff00ccff%i|r, try narrowing down your search!):"):format(MAX_HITS))
		end
		for category, data in pairs(results) do
			output:AddMessage(("|cffe6cc80%s|r (%i):"):format(GetItemClassInfo(category), data.count))

			for k, item in pairs(data.items) do
				output:AddMessage(("    %s"):format(item.link))
			end
		end
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
			-- using WoW's wipe() since 'data = {}' simply resets the pointer and the global SavedVariable doesn't actually get wiped
			wipe(FinderCache)

			PlaySound(5694, "Master")
			print(fmsg("Item cache has been wiped! SpooOooky! |cfff90000Start rebuilding it using /finder rebuild|r"))
			if confirmTimer then
				confirmTimer:Cancel()
			end

			confirmWipe = false -- reset the confirmation step

			-- prebuild some cache table structure
			prepareCache()
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
		rebuildCache()
	elseif cmd == "search" or cmd == "find" or cmd == "s" then
		searchHandler(table.concat(args, " ", 2), EditBox)
	elseif cmd == "stop" or cmd == "abort" or cmd == "cancel" then
		print(fmsg("Stopping cache rebuild"))
		stopCacheRebuild()
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