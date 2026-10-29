-- Digs DAT-based message lookup (Windower 4).
-- V8: independently detects four currency rewards plus fail, success, skill-up, full, and ease.
-- Other message IDs are untouched; ambiguous matches are not accepted.
require('pack')
local bit = require('bit')
local files = require('files')
local zone_dats = require('search_settings').zones
local M = {}
local targets = {
    fail = 'You dig and you dig, but find nothing.',
    success = 'Obtained:',
    points = ' conquest point',
    skillup = 'Your wing skill improved to',
    full = 'your inventory is full',
    ease = 'It appears your chocobo found this item with ease.',
    standing = ' Imperial Standing!',
    notes = ' allied note',
    bayld = 'bayld!',
}
local version = (windower.get_windower_settings() or {}).ffxi_version or 'unknown'
local cache = files.new('data/digs_dat_message_ids.lua')
local found, tried = {}, {}
local function note(s) windower.add_to_chat(207, '[Digs IDs] '..s) end

local function dat_path(dat)
    local root = windower.ffxi_path
    if not root then return nil end
    for i = 1, 9 do
        local prefix = (i == 1) and '' or ('ROM'..i..'/')
        local suffix = (i == 1) and '' or tostring(i)
        local v = io.open(root..prefix..'VTABLE'..suffix..'.DAT', 'rb')
        if v then
            v:seek('set', dat)
            local b = v:read(1)
            v:close()
            if b and b:byte() == i then
                local f = io.open(root..prefix..'FTABLE'..suffix..'.DAT', 'rb')
                if not f then return nil end
                f:seek('set', 2*dat)
                local entry = f:read(2)
                f:close()
                if not entry or #entry ~= 2 then return nil end
                local file_id, dir_id = entry:unpack('b7b9')
                return root..(i == 1 and 'ROM' or 'ROM'..i)..'/'..dir_id..'/'..file_id..'.DAT'
            end
        end
    end
end

local function matches_prefix(encoded, target)
    if #encoded < #target then return false end
    for j = 1, #target do
        if bit.bxor(encoded:byte(j), 0x80) ~= target:byte(j) then
            return false
        end
    end
    return true
end

-- Some DAT entries contain leading text/control bytes or variable values.
local function matches_anywhere(encoded, target)
    if #encoded < #target then return false end
    for start = 1, #encoded - #target + 1 do
        local match = true
        for j = 1, #target do
            if bit.bxor(encoded:byte(start + j - 1), 0x80) ~= target:byte(j) then
                match = false
                break
            end
        end
        if match then return true end
    end
    return false
end

local function scan(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local header = f:read(8)
    if not header or #header < 8 then f:close(); return nil end
    local size, first = header:unpack('II')
    size = size - 0x10000000
    first = bit.bxor(first, 0x80808080)
    if first <= 0 or first > 2000000 or first % 4 ~= 0 or size <= first or size > 16000000 then
        f:close(); return nil
    end
    f:seek('set', 4)
    local offsets = f:read(first)
    local data = f:read('*a')
    f:close()
    if not offsets or #offsets < first or not data then return nil end
    local result = {}
    local ambiguous = {}
    local previous = 0
    for i = 1, first/4 do
        local next_offset = (i == first/4 and size or bit.bxor(offsets:unpack('I', 4*i+1), 0x80808080)) - first
        if next_offset < previous or next_offset > #data then return nil end
        local encoded = data:sub(previous+1, next_offset)
        for kind, target in pairs(targets) do
            local matched
            if kind == 'points' or kind == 'standing' then
                matched = matches_prefix(encoded, 'You discover a cache of beastman resources and receive')
                    and matches_anywhere(encoded, target)
            elseif kind == 'notes' then
                matched = matches_prefix(encoded, 'You discover a cache of beastman confederate resources and receive')
                    and matches_anywhere(encoded, target)
            elseif kind == 'bayld' then
                matched = matches_prefix(encoded, 'You receive ' .. string.char(0x0A, 0x00) .. ' bayld!')
            elseif kind == 'skillup' or kind == 'full' then
                matched = matches_anywhere(encoded, target)
            else
                matched = matches_prefix(encoded, target)
            end
            if matched then
                if result[kind] then ambiguous[kind] = true end
                result[kind] = i - 1
            end
        end
        previous = next_offset
    end
    for kind in pairs(ambiguous) do result[kind] = nil end
    return result
end

local function valid_id(id)
    return type(id) == 'number' and id >= 0 and id < 32768 and id % 1 == 0
end

local function save()
    local lines = {'-- Generated automatically by Digs.\n', 'return ', string.format('%q', version), ', {\n'}
    for z, ids in pairs(found) do
        lines[#lines+1] = ('    [%d] = {'):format(z)
        for kind, id in pairs(ids) do
            lines[#lines+1] = ('%s=%d, '):format(kind, id)
        end
        lines[#lines+1] = '},\n'
    end
    lines[#lines+1] = '}\n'
    cache:write(table.concat(lines))
end

-- Old cache entries were numbers (failure ID only); migrate them in memory.
local ok, saved_version, saved = pcall(function()
    if cache:exists() then return loadstring(cache:read())() end
end)
if ok and saved_version == version and type(saved) == 'table' then
    for z, ids in pairs(saved) do
        if type(z) == 'number' then
            if valid_id(ids) then
                found[z] = {fail=ids}
            elseif type(ids) == 'table' then
                local clean = {}
                for kind in pairs(targets) do
                    if valid_id(ids[kind]) then clean[kind] = ids[kind] end
                end
                if next(clean) then found[z] = clean end
            end
        end
    end
end

function M.update(zone, messages)
    if not messages[zone] or not zone_dats[zone] then return end
    local ids = found[zone] or {}
    for kind, id in pairs(ids) do messages[zone][kind] = id end
    if ids.fail and ids.success and ids.points and ids.skillup and ids.full and ids.ease and ids.standing and ids.notes and ids.bayld then return end
    if tried[zone] then return end
    tried[zone] = true
    local ok_scan, detected = pcall(function()
        local path = dat_path(zone_dats[zone])
        return path and scan(path)
    end)
    if ok_scan and type(detected) == 'table' then
        local changed = false
        for kind in pairs(targets) do
            if valid_id(detected[kind]) then
                ids[kind] = detected[kind]
                messages[zone][kind] = detected[kind]
                note(('Zone %d: %s message ID %d (%s)'):format(zone, kind, detected[kind], version))
                changed = true
            elseif not ids[kind] then
                note(('Zone %d: %s DAT lookup unavailable; using existing ID %d'):format(zone, kind, messages[zone][kind]))
            end
        end
        if changed then
            found[zone] = ids
            save()
        end
    else
        note(('Zone %d: DAT lookup unavailable; using existing message IDs'):format(zone))
    end
end

return M
