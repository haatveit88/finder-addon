-- Maintains the Finder item cache db
local ADDON, finder = ...
local DB_CURRENT_VERSION = 2

--[[ DB layouts across versions:
1: FinderCache = {
    [categoryID] = {
        "itemName" = {
            itemID = 1234,
            itemLink = "wowitemlink",
        }
    }
}

2: FinderCache = {
    [categoryID] = {
        [itemID] = "itemName",
    }
}

3: FinderCache = {
    index = {
        [1] = "xyz",
        . . .
        [n] = "abc",
    },

    items = {
        [itemID] = {
            index_1,
            . . .
            index_n,
        },
    }
}
--]]

-- initialize the db (SavedVariables table) to be ready for use
local function initNewDB(db)
    -- plug in item class IDs
    for i = 0, NUM_LE_ITEM_CLASSS do
        local class = GetItemClassInfo(i)
        if class then
            db[i] = {}
        end
    end

    -- append version
    db.__DBVERSION = DB_CURRENT_VERSION

    return true
end


-- perform an upgrade of an older database version
local upgradeDB = {}

-- "upgrade" from blank / corrupt
upgradeDB[0] = initNewDB

-- upgrade from legacy v1
upgradeDB[1] = function(db)
    for category = 0, #db do
        local oldItems = db[category]

        -- temporary holding
        local newItems = {}

        -- extract the existing items
        for name, data in pairs(oldItems) do
            newItems[data.id] = name
        end

        -- wipe the old table
        wipe(oldItems)

        -- reinstate the items using new layout
        for id, name in pairs(newItems) do
            db[category][id] = name
        end
    end

    return true
end


-- determine if db version is current, and try to upgrade if it isn't
-- returns true if db was upgraded (plus result), always returns false if db was up to date
local function checkDBVersion(db)
    local upgrade = false

    -- try to detect db version
    if db.__DBVERSION then
        if db.__DBVERSION ~= DB_CURRENT_VERSION then
            -- if we get here, db must be corrupt
            upgrade = 0
        elseif db.__DBVERSION == 2 then
            -- this is current
        end
    else
        -- no version tag, so guess that it's v1. Although it could be corrupt
        upgrade = 1
    end

    if upgrade then
        local success, error = pcall(upgradeDB[upgrade], db)
        if success then
            db.__DBVERSION = DB_CURRENT_VERSION -- remember to tag it with new ver
            return true, success, DB_CURRENT_VERSION
        else
            return true, success, error
        end
    else
        return false
    end
end

-- export to addon table
finder.db = {
    checkDBVersion = checkDBVersion,
    DB_CURRENT_VERSION = DB_CURRENT_VERSION,
    initNewDB = initNewDB,
}