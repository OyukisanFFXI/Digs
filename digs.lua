-- addon information

_addon.name = 'digs'
_addon.version = '1.2.0'
_addon.command = 'digs'
_addon.author = 'Oyukisan (Oyukisan@Odin)'

-- modules

config = require('config')
require('pack')
local packets = require('packets')
local resources = require('resources')

-- default settings

defaults = {}
defaults.delay = {}
defaults.delay.area = 60
defaults.delay.lag = 3
defaults.delay.dig = 15
defaults.fatigue = {}
defaults.fatigue.date = os.date('!%Y-%m-%d', os.time() + 32400)
defaults.fatigue.items = 0
defaults.fatigue.diff = 0
defaults.fatigue.free = 0
defaults.accuracy = {}
defaults.accuracy.failed = 0
defaults.accuracy.total = 0
-- Item IDs are saved as string keys for stable config serialization.
defaults.item_log = {date = defaults.fatigue.date, today = {}, lifetime = {}}
-- New characters start with unknown wing skill until calibrated or observed.
defaults.wing_skill = {level = -1, increases = 0, history_data = ''}

-- Windower config.load automatically selects the logged-in character section
-- in data/settings.xml. History is stored as a scalar to avoid nested tables
-- inherited from <global> being shared between characters.
local player = windower.ffxi.get_player()
if not player or type(player.name) ~= 'string' or player.name == '' then
    error('[Digs] Character identity unavailable. Load Digs after logging in.')
end
settings = config.load(defaults)
windower.add_to_chat(207, '[Digs] Active character: ' .. player.name)
if type(settings.wing_skill) ~= 'table' then
    settings.wing_skill = {level = -1, increases = 0, history_data = ''}
end
settings.wing_skill.level = tonumber(settings.wing_skill.level) or -1
settings.wing_skill.increases = tonumber(settings.wing_skill.increases) or 0
if type(settings.wing_skill.history_data) ~= 'string' then
    settings.wing_skill.history_data = ''
end

-- Each event is YYYY-MM-DD HH:MM:SS|LEVEL, separated by semicolons.
-- A string value saves in the active character section without merging
-- the legacy global history table into every character.
local function read_skill_history()
    local entries = {}
    for date, level in settings.wing_skill.history_data:gmatch('(%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d)|(%d+)') do
        entries[#entries + 1] = {date = date, level = tonumber(level)}
    end
    table.sort(entries, function(a, b)
        if a.date == b.date then return a.level < b.level end
        return a.date < b.date
    end)
    return entries
end

local function append_skill_history(date, level)
    local event = date .. '|' .. tostring(level)
    local history = settings.wing_skill.history_data
    for existing in history:gmatch('[^;]+') do
        if existing == event then return end
    end
    settings.wing_skill.history_data = history == '' and event or (history .. ';' .. event)
end

-- Windower XML settings may contain numeric values as strings. Normalize all
-- values used in comparisons, arithmetic, or numeric formatting on load.
local function normalize_number(group, key, fallback)
    group[key] = tonumber(group[key]) or fallback
end
if type(settings.delay) ~= 'table' then settings.delay = {} end
normalize_number(settings.delay, 'area', defaults.delay.area)
normalize_number(settings.delay, 'lag', defaults.delay.lag)
normalize_number(settings.delay, 'dig', defaults.delay.dig)
if type(settings.accuracy) ~= 'table' then settings.accuracy = {} end
normalize_number(settings.accuracy, 'failed', 0)
normalize_number(settings.accuracy, 'total', 0)
if type(settings.fatigue) ~= 'table' then settings.fatigue = {} end
normalize_number(settings.fatigue, 'items', 0)
normalize_number(settings.fatigue, 'diff', 0)
normalize_number(settings.fatigue, 'free', 0)
if type(settings.fatigue.date) ~= 'string' then
    settings.fatigue.date = defaults.fatigue.date
end

-- load message constants

require('messages')
local dat_ids = require('digs_dat_ids')
dat_ids.update(windower.ffxi.get_info().zone, messages)

-- buff helper function

function get_chocobo_buff()
    for _,buff_id in pairs(windower.ffxi.get_player().buffs) do
        if buff_id == 252 then
            return true
        end
    end
    return false
end

-- inventory helper function

function get_gysahl_count()
    local count = 0
    for _,item in pairs(windower.ffxi.get_items(0)) do
        if type(item) == 'table' and item.id == 4545 and item.status == 0 then
            count = count + item.count
        end
    end
    return count
end

-- stats helper functions

function update_day()
    if type(settings.item_log) ~= 'table' then
        settings.item_log = {date = settings.fatigue.date, today = {}, lifetime = {}}
    end
    local log = settings.item_log
    if type(log.today) ~= 'table' then log.today = {} end
    if type(log.lifetime) ~= 'table' then log.lifetime = {} end
    local today = os.date('!%Y-%m-%d', os.time() + 32400)
    if log.date ~= today then
        log.date = today
        log.today = {}
        settings:save()
    end
    local today = os.date('!%Y-%m-%d', os.time() + 32400)
    if settings.fatigue.date ~= today then
        settings.fatigue.date = today
        settings.fatigue.items = 0
        settings.fatigue.free = 0
        settings.fatigue.diff = settings.accuracy.failed - settings.accuracy.total
    end
end

-- Rank names follow the supplied Wing Skill chart (0-9 through 100).
local wing_ranks = {'Amateur', 'Recruit', 'Initiate', 'Novice',
    'Apprentice', 'Journeyman', 'Craftsman', 'Artisan',
    'Adept', 'Veteran', 'Expert'}
local function current_wing_rank(level)
    local tier = math.max(0, math.min(10, math.floor((tonumber(level) or 0) / 10)))
    return wing_ranks[tier + 1]
end

function display_stats()
    local accuracy = 0
    local successful = settings.accuracy.total - settings.accuracy.failed
    if settings.accuracy.total > 0 then
        accuracy = (successful / settings.accuracy.total) * 100
    end
    windower.add_to_chat(207, 'dig accuracy: %d%% (%d/%d), fatigue today: %d, items today: %d gysahl greens remaining: %d, wing skill: %s, rank: %s':format(accuracy, successful, settings.accuracy.total, successful - settings.fatigue.free + settings.fatigue.diff, settings.fatigue.items, get_gysahl_count(), (settings.wing_skill.level >= 0 and tostring(settings.wing_skill.level) or 'Unknown'), (settings.wing_skill.level >= 0 and current_wing_rank(settings.wing_skill.level) or 'Unknown')))
end

function update_stats(mode)
    update_day()
    if mode == 3 then
        settings.fatigue.free = settings.fatigue.free + 1
    elseif mode == 2 then
        settings.fatigue.items = settings.fatigue.items + 1
        display_stats()
    elseif mode == 1 then
        settings.accuracy.total = settings.accuracy.total + 1
    else
        settings.accuracy.failed = settings.accuracy.failed + 1
        display_stats()
    end
    settings:save()
end

-- Item counts are updated only for the verified digging success message.
local function record_dig_item(original)
    local ok, packet = pcall(packets.parse, 'incoming', original)
    if not ok or type(packet) ~= 'table' then return end
    local id = tonumber(packet['Param 1'])
    if not id or id <= 0 or not resources.items[id] then return end
    update_day()
    local key = tostring(id)
    local log = settings.item_log
    log.today[key] = (tonumber(log.today[key]) or 0) + 1
    log.lifetime[key] = (tonumber(log.lifetime[key]) or 0) + 1
    settings:save()
end

local function display_items(lifetime)
    update_day()
    local counts = lifetime and settings.item_log.lifetime or settings.item_log.today
    local entries = {}
    for key, count in pairs(counts) do
        local id = tonumber(key)
        local item = id and resources.items[id]
        if item and tonumber(count) and tonumber(count) > 0 then
            entries[#entries + 1] = {name = item.en or ('Item '..key), id = id, count = tonumber(count)}
        end
    end
    table.sort(entries, function(a, b)
        local an, bn = a.name:lower(), b.name:lower()
        if an == bn then return a.id < b.id end
        return an < bn
    end)
    local label = lifetime and 'Lifetime' or 'Today'
    windower.add_to_chat(207, ('[Digs Items] %s (%d item types):'):format(label, #entries))
    if #entries == 0 then
        windower.add_to_chat(207, '[Digs Items] No items recorded yet.')
        return
    end
    for _, entry in ipairs(entries) do
        windower.add_to_chat(207, ('[Digs Items] %s: %d'):format(entry.name, entry.count))
    end
end

-- Read the actual new wing skill level from the verified 0x2A Param 1.
local function record_wing_skill(original)
    local ok, packet = pcall(packets.parse, 'incoming', original)
    local new_level = ok and packet and tonumber(packet['Param 1']) or nil
    if not new_level or new_level < 0 or new_level > 255 or new_level % 1 ~= 0 then
        windower.add_to_chat(167, '[Digs Skill] Could not read the new wing skill level; no changes saved.')
        return
    end
    local skill = settings.wing_skill
    if new_level == skill.level then
        -- Ignore duplicate notifications for the same recorded level.
        return
    end
    -- The game's reported level is authoritative, even if an older saved
    -- setting was too high (for example, after a character migration).
    local previous_level = skill.level
    local timestamp = os.date('%Y-%m-%d %H:%M:%S')
    append_skill_history(timestamp, new_level)
    skill.level = new_level
    skill.increases = (tonumber(skill.increases) or 0) + 1
    settings:save()
    windower.add_to_chat(207, ('[Digs Skill] Wing skill updated to %d (previously %s; recorded events: %d).'):format(new_level, previous_level >= 0 and tostring(previous_level) or 'Unknown', skill.increases))
end

local function display_skill_history()
    local entries = read_skill_history()

    windower.add_to_chat(207,
        ('[Digs Skill] Recorded level increases: %d'):format(#entries))

    if #entries == 0 then
        windower.add_to_chat(207,
            '[Digs Skill] No level increases recorded since tracking began.')
        return
    end

    for _, entry in ipairs(entries) do
        windower.add_to_chat(207,
            ('[Digs Skill] %s - level %s'):format(
                tostring(entry.date),
                tostring(entry.level)
            ))
    end
end

-- event callback functions

function check_zone_change(new_zone_id, old_zone_id)
    dat_ids.update(new_zone_id, messages)
    if messages[new_zone_id] then
        windower.send_command('timers c "Chocobo Area Delay" %d down':format(settings.delay.area + settings.delay.lag))
    else
        windower.send_command('timers d "Chocobo Area Delay"')
    end
    windower.send_command('timers d "Chocobo Dig Delay"')
end

function check_incoming_chunk(id, original, modified, injected, blocked)
    local zone_id = windower.ffxi.get_info().zone
    dat_ids.update(zone_id, messages)
    if messages[zone_id] then
        if id == 0x2A then
            local message_id = original:unpack('H', 27) % 0x8000
            if (messages[zone_id].full == message_id or messages[zone_id].success == message_id or messages[zone_id].points == message_id or messages[zone_id].standing == message_id or messages[zone_id].notes == message_id or messages[zone_id].bayld == message_id) and get_chocobo_buff() then
                update_stats(2)
                if messages[zone_id].success == message_id then
                    record_dig_item(original)
                end
            elseif messages[zone_id].skillup == message_id and get_chocobo_buff() then
                record_wing_skill(original)
            elseif messages[zone_id].ease == message_id then
                update_stats(3)
            end
        elseif id == 0x2F and windower.ffxi.get_player().id == original:unpack('I', 5) then
            if settings.delay.dig > 0 then
                windower.send_command('timers c "Chocobo Dig Delay" %d down':format(settings.delay.dig))
            end
            update_stats(1)
        elseif id == 0x36 then
            local message_id = original:unpack('H', 11) % 0x8000
            if messages[zone_id].fail == message_id then
                update_stats(0)
            end
        end
    end
end

function digs_command(...)
    local arg = {...}
    if #arg == 1 and arg[1]:lower() == 'skill' then
        windower.add_to_chat(207, ('[Digs Skill] Wing skill: %s; recorded level increases: %d'):format(settings.wing_skill.level >= 0 and tostring(settings.wing_skill.level) or 'Unknown', settings.wing_skill.increases))
    elseif #arg == 3 and arg[1]:lower() == 'skill' and arg[2]:lower() == 'set' then
        local level = tonumber(arg[3])
        if not level or level < 0 or level > 100 or level % 1 ~= 0 then
            windower.add_to_chat(167, '[Digs Skill] Usage: //digs skill set <0-100>')
            return
        end
        -- Manual calibration does not fabricate a level-up or history entry.
        settings.wing_skill.level = level
        settings:save()
        windower.add_to_chat(207, ('[Digs Skill] %s: current wing skill set to %d'):format(player.name, level))
    elseif #arg == 1 and arg[1]:lower() == 'skillhistory' then
        display_skill_history()
    elseif #arg == 1 and arg[1]:lower() == 'items' then
        display_items(false)
    elseif #arg == 1 and arg[1]:lower() == 'itemslife' then
        display_items(true)
    elseif #arg == 1 and arg[1]:lower() == 'stats' then
        update_day()
        display_stats()
    elseif #arg == 2 and arg[1]:lower() == 'stats' and arg[2]:lower() == 'clear' then
        update_day()
        settings.fatigue.diff = settings.accuracy.total - settings.accuracy.failed + settings.fatigue.diff
        settings.accuracy.failed = 0
        settings.accuracy.total = 0
        settings:save()
        windower.add_to_chat(204, 'reset dig accuracy statistics')
    elseif #arg == 2 and arg[1]:lower() == 'rank' then
        local rank = arg[2]:lower()
        if rank == 'amateur' or rank == 'a60' then
            settings.delay.area = 60
            settings.delay.dig = 15
        elseif rank == 'recruit' or rank == 'a55' then
            settings.delay.area = 55
            settings.delay.dig = 10
        elseif rank == 'initiate' or rank == 'a50' then
            settings.delay.area = 50
            settings.delay.dig = 5
        elseif rank == 'novice' or rank == 'a45' then
            settings.delay.area = 45
            settings.delay.dig = 0
        elseif rank == 'apprentice' or rank == 'a40' then
            settings.delay.area = 40
            settings.delay.dig = 0
        elseif rank == 'journeyman' or rank == 'a35' then
            settings.delay.area = 35
            settings.delay.dig = 0
        elseif rank == 'craftsman' or rank == 'a30' then
            settings.delay.area = 30
            settings.delay.dig = 0
        elseif rank == 'artisan' or rank == 'a25' then
            settings.delay.area = 25
            settings.delay.dig = 0
        elseif rank == 'adept' or rank == 'a20' then
            settings.delay.area = 20
            settings.delay.dig = 0
        elseif rank == 'veteran' or rank == 'a15' then
            settings.delay.area = 15
            settings.delay.dig = 0
        elseif rank == 'expert' or rank == 'a10' then
            settings.delay.area = 10
            settings.delay.dig = 0
        else
            windower.add_to_chat(167, 'invalid digging rank')
            return
        end
        windower.add_to_chat(204, 'digging rank: %s, area delay: %d seconds, dig delay: %d seconds':format(rank, settings.delay.area, settings.delay.dig))
        settings:save()
    else
        windower.add_to_chat(167, 'usage:')
        windower.add_to_chat(167, '  digs rank <crafting rank>')
        windower.add_to_chat(167, '  digs stats [clear]')
        windower.add_to_chat(167, '  digs items')
        windower.add_to_chat(167, '  digs itemslife')
        windower.add_to_chat(167, '  digs skill')
        windower.add_to_chat(167, '  digs skill set <0-100>')
        windower.add_to_chat(167, '  digs skillhistory')
    end
end

-- register event callbacks

windower.register_event('zone change', check_zone_change)
windower.register_event('incoming chunk', check_incoming_chunk)
windower.register_event('addon command', digs_command)
