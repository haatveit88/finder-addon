-- Maintains the Finder item cache db
local ADDON, finder = ...
local DB_CURRENT_VERSION = 3

-- initialize the db (SavedVariables table) to be ready for use
local function initNewDB(db)
    -- plug in item class IDs
    for i = 0, NUM_LE_ITEM_CLASSS do
        db[i] = {}
    end

    -- add "unknown" category for certain items
    db[-1] = {}

    -- append version
    db.__DBVERSION = DB_CURRENT_VERSION

    -- append TOC version so we know how old the db is
    db.__tocversion = select(4, GetBuildInfo())

    return true
end

-- determine if db version is current, returns 0 if up to date, <0 if old, >0 if ... from the future?
local function isDatabaseOutdated(db)
    return (db.__DBVERSION or -99) - DB_CURRENT_VERSION
end

-- export to addon table
finder.db = {
    isDatabaseOutdated = isDatabaseOutdated,
    initNewDB = initNewDB,
}