-- SPDX-FileCopyrightText: 2026 Sayantan Santra <sayantan.santra689@gmail.com>
-- SPDX-License-Identifier: GPL-3.0

--[[ Repo:https://github.com/SinTan1729/koreader-patches
   This automatically creates KOReader collections using a custom collection from calibre.
   By default, a custom column called `#collections` is used. But the script can easily be edited
   to use any other column name. Just change the variable CUSTOM_COLUMN_USED below.

   It does not touch already existing collections. So please don't create any collections with
   the same name an entry in `#collections` manually. Collections are created/updated at startup.
   Automatically managed collections are marked with a ⚡ in the viewer. This is also customizable.
]]

-- !!! Change this variable if you want to use a different custom column name
-- Note that you need to add a # to the front.
local CUSTOM_COLUMN_USED = '#collections' -- string
-- Or use an array, colliding collection names are merged into one collection
-- local CUSTOM_COLUMN_USED = { '#collections', '#other_collection_column' } --array
local MARKER = '⚡'

-- You shouldn't need to touch anything after this line
local userpatch = require('userpatch')
local ReadCollection = require('readcollection')
local FileManagerCollection = require('apps/filemanager/filemanagercollection')
local DataStorage = require('datastorage')
---@diagnostic disable-next-line: undefined-global
local g_reader_settings = G_reader_settings
local Device = require('device')
local LuaSettings = require('luasettings')
local logger = require('logger')
local lfs = require('libs/libkoreader-lfs')
local json = require('rapidjson')

-- Internal constants
-- Don't touch these unless you know what you're doing
local METADATA_ROOT = nil
local METADATA_FILE = nil
local LIBRARY_ROOT = nil
local SETTINGS_FILE =
    DataStorage:getSettingsDir() .. '/calibre_collections.lua'

-- State
local settings = LuaSettings:open(SETTINGS_FILE)
local managed =
    settings:readSetting('managed_collections', {})
local startup_done = false

-- Persistence
local function saveState()
    settings:saveSetting(
        'managed_collections',
        managed
    )
    settings:flush()
end

-- Marker support
local function isManaged(name)
    return managed[name] == true
end
local orig_getCollMarker = FileManagerCollection.getCollMarker

function FileManagerCollection.getCollMarker(name)
    local marker = orig_getCollMarker(name)
    if isManaged(name) then
        marker = marker and
            (marker .. ' ' .. MARKER)
            or MARKER
    end
    return marker
end

-- Collection helpers
local function collectionExists(name)
    return ReadCollection.coll[name]
end

local function createCollection(name)
    if collectionExists(name) then
        return true
    end

    logger.info(
        'Calibre Collections: Creating collection:',
        name
    )

    ReadCollection:addCollection(name)
    ReadCollection:write({ [name] = true })
end

local function ensureCollection(name)
    if collectionExists(name) then
        return
    end
    createCollection(name)
end

local function collectionContains(filepath, collection)
    return ReadCollection:isFileInCollection(
        filepath,
        collection
    )
end

local function addBook(filepath, collection)
    if collectionContains(filepath, collection) then
        return
    end

    logger.dbg(
        'Calibre Collections: Adding',
        filepath, 'to', collection
    )

    ReadCollection:addItem(
        filepath,
        collection
    )
end

local function removeBook(filepath, collection)
    if not collectionContains(filepath, collection) then
        return
    end

    logger.dbg(
        'Calibre Collections: Removing',
        filepath, 'from', collection
    )

    ReadCollection:removeItem(
        filepath,
        collection,
        true
    )
end

local function removeManagedCollection(name)
    if not isManaged(name) then
        return
    end
    ReadCollection:removeCollection(name)

    logger.info(
        'Calibre Collections: Removing collection:',
        name
    )

    managed[name] = nil
    ReadCollection:write({ [name] = true })
end


-- Metadata parsing
local function initConstants()
    if LIBRARY_ROOT == nil then
        LIBRARY_ROOT = g_reader_settings:readSetting('home_dir')
            or Device.home_dir
        LIBRARY_ROOT = LIBRARY_ROOT:gsub('/+$', '')
        logger.info('Using library root:', LIBRARY_ROOT)
    end
    if LIBRARY_ROOT ~= nil and METADATA_ROOT == nil then
        local dir = LIBRARY_ROOT
        while dir do
            for _, file in ipairs({ 'metadata.calibre', '.metadata.calibre' }) do
                local candidate = dir .. '/' .. file
                if lfs.attributes(candidate, 'mode') == 'file' then
                    METADATA_ROOT = dir
                    METADATA_FILE = file
                    logger.info('Using metadata file:', METADATA_ROOT .. '/' .. METADATA_FILE)
                    return
                end
            end

            local parent = dir:match('(.+)/[^/]+$')
            if not parent or parent == dir then
                break
            end
            dir = parent
        end
    end
    logger.warn('No metadata file found')
end

local function loadMetadata()
    initConstants()
    local f
    if METADATA_ROOT ~= nil then
        f = io.open(METADATA_ROOT .. '/' .. METADATA_FILE, 'rb')
    end
    if not f then
        logger.warn(
            'Calibre Collections: Calibre metadata not found'
        )
        return nil
    end

    local text = f:read('*a')
    f:close()

    local ok, data = pcall(function()
        return json.decode(text)
    end)

    if not ok then
        logger.err(
            'Calibre Collections: JSON parse failed'
        )
        return nil
    end

    return data
end

local VALID_CUSTOM_COLUMNS = nil
local function getConfiguredColumns()
    if VALID_CUSTOM_COLUMNS ~= nil then
        return VALID_CUSTOM_COLUMNS
    end

    local columns = type(CUSTOM_COLUMN_USED) == 'table'
        and CUSTOM_COLUMN_USED
        or { CUSTOM_COLUMN_USED }

    VALID_CUSTOM_COLUMNS = {}
    for _, column_name in ipairs(columns) do
        if type(column_name) == 'string' and column_name:sub(1, 1) == '#' then
            table.insert(VALID_CUSTOM_COLUMNS, column_name)
        else
            logger.warn(string.format(
                'Calibre Collections: skipping invalid custom column %q (must start with #)',
                tostring(column_name)
            ))
        end
    end

    return VALID_CUSTOM_COLUMNS
end

local function addCollectionValue(collections, value)
    if not value then
        return
    end

    if type(value) == 'string' then
        value = value:match('^%s*(.-)%s*$')
        if value ~= '' then
            collections[value] = true
        end
        return
    end

    if type(value) == 'table' then
        -- calibre multi-value custom columns may come through as arrays
        for _, item in ipairs(value) do
            if type(item) == 'string' then
                item = item:match('^%s*(.-)%s*$')
                if item ~= '' then
                    collections[item] = true
                end
            end
        end
    end
end

local function getBookCollections(book)
    local md = book.user_metadata
    if not md then
        return nil
    end

    local columns = VALID_CUSTOM_COLUMNS
    if not columns or #columns == 0 then
        logger.warn('No valid collection columns were configured.')
        return nil
    end

    local collections = {}

    for _, column_name in ipairs(columns) do
        local c = md[column_name]
        if c and c['#value#'] ~= nil then
            addCollectionValue(collections, c['#value#'])
        end
    end

    return next(collections) and collections or nil
end

local function getBookPath(book)
    local lpath = book.lpath
    if not lpath then
        return nil
    end
    local path = METADATA_ROOT .. '/' .. lpath
    if path:sub(1, #LIBRARY_ROOT + 1) ~= LIBRARY_ROOT .. '/' then
        return nil
    end
    return path
end

-- Sync
local function buildDesiredMembership(metadata)
    local desired = {}
    for _, book in ipairs(metadata) do
        local path = getBookPath(book)
        if path and lfs.attributes(path) then
            local collections =
                getBookCollections(book)

            if collections then
                for collection in pairs(collections) do
                    desired[collection] =
                        desired[collection] or {}

                    desired[collection][path] = true
                end
            end
        end
    end

    return desired
end

local function syncManagedCollection(
    collection_name,
    desired_members
)
    if next(desired_members) == nil then
        removeManagedCollection(collection_name)
        return
    end
    ensureCollection(collection_name)
    local current = {}
    local coll = ReadCollection.coll[collection_name]
    if coll then
        for filepath in pairs(coll) do
            current[filepath] = true
        end
    end

    -- additions
    for filepath in pairs(desired_members) do
        if not current[filepath] then
            addBook(
                filepath,
                collection_name
            )
        end
    end

    -- removals
    for filepath in pairs(current) do
        if not desired_members[filepath] then
            removeBook(
                filepath,
                collection_name
            )
        end
    end
end

local function runSync()
    local metadata = loadMetadata()
    if not metadata then
        return
    end

    getConfiguredColumns()
    local desired =
        buildDesiredMembership(metadata)

    -- create newly discovered collections
    for collection_name in pairs(desired) do
        if not collectionExists(collection_name) then
            createCollection(collection_name)
            managed[collection_name] = true
        end
    end

    saveState()

    -- sync only managed collections
    for collection_name in pairs(managed) do
        local desired_members =
            desired[collection_name] or {}

        syncManagedCollection(
            collection_name,
            desired_members
        )
        ReadCollection:write({ [collection_name] = true })
    end

    saveState()

    logger.dbg(
        'Calibre Collections: sync complete'
    )
end

-- Startup
local function startup()
    if startup_done then
        return
    end


    startup_done = true

    local ok, err = pcall(runSync)

    if not ok then
        logger.err(
            'Calibre Collections failed:',
            err
        )
    end
end

-- Hook
userpatch.registerPatchPluginFunc(
    'coverbrowser',
    function()
        startup()
    end
)

logger.info(
    'Calibre Collections were successfully created and/or synced.'
)

-- Prevent KOReader's default folder syncing for smart collections
local orig_ReadCollection_updateCollectionFromFolder = ReadCollection.updateCollectionFromFolder
function ReadCollection:updateCollectionFromFolder(collection_name, folders, is_showing)
    if isManaged(collection_name) then
        return 0
    end
    return orig_ReadCollection_updateCollectionFromFolder(self, collection_name, folders, is_showing)
end
