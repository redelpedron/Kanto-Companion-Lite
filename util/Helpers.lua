local Colors = require("util.Colors")

local Helpers = {}

function Helpers.mixin(class, mixinTable)
    for k, v in pairs(mixinTable) do
        if type(v) == "function" then
            class[k] = v
        end
    end
    return class
end

function Helpers.getSafeInsets(cfg)
    local insets = { top = 0, right = 0, bottom = 0, left = 0 }
    if not (love and love.window and love.graphics) then return insets end

    local ok, sx, sy, sw, sh = pcall(love.window.getSafeArea)
    if not ok or not sx then return insets end

    local W, H = love.graphics.getDimensions()
    local cap = (cfg and cfg.SAFE_AREA_MAX_INSET) or 60

    insets.left   = math.min(cap, math.max(0, sx))
    insets.top    = math.min(cap, math.max(0, sy))
    insets.right  = math.min(cap, math.max(0, W - (sx + sw)))
    insets.bottom = math.min(cap, math.max(0, H - (sy + sh)))
    return insets
end

local ICONS = {}

ICONS.coin = function(cx, cy, s)
    love.graphics.circle("line", cx, cy, s * 0.5)
    love.graphics.circle("fill", cx, cy, s * 0.16)
end

ICONS.badge = function(cx, cy, s)
    local r, pts = s * 0.5, {}
    for i = 0, 4 do
        local a = -math.pi / 2 + i * (2 * math.pi / 5)
        pts[#pts + 1] = cx + math.cos(a) * r
        pts[#pts + 1] = cy + math.sin(a) * r
    end
    love.graphics.polygon("fill", pts)
end

ICONS.clock = function(cx, cy, s)
    local r = s * 0.5
    love.graphics.circle("line", cx, cy, r)
    love.graphics.line(cx, cy, cx, cy - r * 0.6)
    love.graphics.line(cx, cy, cx + r * 0.45, cy + r * 0.1)
end

ICONS.caught = function(cx, cy, s)
    local r = s * 0.5
    love.graphics.circle("line", cx, cy, r)
    love.graphics.line(cx - r, cy, cx + r, cy)
    love.graphics.circle("fill", cx, cy, r * 0.28)
    love.graphics.circle("line", cx, cy, r * 0.28)
end

ICONS.seen = function(cx, cy, s)
    love.graphics.ellipse("line", cx, cy, s * 0.48, s * 0.28)
    love.graphics.circle("fill", cx, cy, s * 0.13)
end

ICONS.pin = function(cx, cy, s)
    local r = s * 0.3
    love.graphics.circle("fill", cx, cy - r * 0.3, r)
    love.graphics.polygon("fill",
        cx - r * 0.6, cy + r * 0.2,
        cx + r * 0.6, cy + r * 0.2,
        cx, cy + r * 1.6)
end

ICONS.sun = function(cx, cy, s)
    local r = s * 0.26
    love.graphics.circle("fill", cx, cy, r)
    for i = 0, 7 do
        local a = i * (math.pi / 4)
        love.graphics.line(
            cx + math.cos(a) * r * 1.5, cy + math.sin(a) * r * 1.5,
            cx + math.cos(a) * r * 2.1, cy + math.sin(a) * r * 2.1)
    end
end

ICONS.moon = function(cx, cy, s, bg)
    local r = s * 0.42
    love.graphics.circle("fill", cx, cy, r)
    if bg then
        Colors.set(bg, 1)
        love.graphics.circle("fill", cx + r * 0.55, cy - r * 0.28, r * 0.85)
    end
end

ICONS.dot = function(cx, cy, s)
    love.graphics.circle("fill", cx, cy, s * 0.28)
end

ICONS.battery = function(cx, cy, s)

    local bw, bh = s * 0.62, s * 0.36
    local bx, by = cx - bw / 2 - s * 0.07, cy - bh / 2
    love.graphics.rectangle("line", bx, by, bw, bh, 1, 1)
    local nubW, nubH = s * 0.08, bh * 0.5
    love.graphics.rectangle("fill", bx + bw, cy - nubH / 2, nubW, nubH)
end

ICONS.bolt = function(cx, cy, s)
    local w, h = s * 0.5, s * 0.7
    love.graphics.polygon("fill",
        cx + w * 0.12, cy - h / 2,
        cx - w * 0.32, cy + h * 0.08,
        cx - w * 0.02, cy + h * 0.08,
        cx - w * 0.12, cy + h / 2,
        cx + w * 0.32, cy - h * 0.08,
        cx + w * 0.02, cy - h * 0.08)
end

function Helpers.drawIcon(name, cx, cy, size, bg)
    local fn = ICONS[name]
    if not fn then return end
    fn(cx, cy, size, bg)
end

local MISSING = {}
local _requireCache = {}

function Helpers.safeRequire(path)
    local cached = _requireCache[path]
    if cached ~= nil then
        return cached ~= MISSING and cached or nil
    end
    local ok, m = pcall(require, path)
    _requireCache[path] = ok and m or MISSING
    return ok and m or nil
end

function Helpers.normalizeGender(g)
    if type(g) ~= "string" then return nil end
    local up = g:upper()
    if up == "M" or up == "MALE" then return "M" end
    if up == "F" or up == "FEMALE" then return "F" end
    return nil
end

function Helpers.dedupeTypes(types)
    if type(types) ~= "table" then return {} end
    local seen, out = {}, {}
    for _, t in ipairs(types) do
        if not seen[t] then
            seen[t] = true
            out[#out + 1] = t
        end
    end
    return out
end

function Helpers.formatMapName(mapId)
    if not mapId then return "" end
    return mapId:lower():gsub("_", " "):gsub("(%a)(%w*)", function(a, b)
        return a:upper() .. b
    end)
end

function Helpers.sanitizeName(name)
    if not name then return "" end
    name = tostring(name)
    name = name:gsub("♀", " (F)")
    name = name:gsub("♂", " (M)")
    return name
end

local HEAL_IDS = {
    POTION=true, SUPER_POTION=true, HYPER_POTION=true, MAX_POTION=true, FULL_RESTORE=true,
    FULL_HEAL=true, ANTIDOTE=true, BURN_HEAL=true, ICE_HEAL=true, AWAKENING=true, PARLYZ_HEAL=true,
    REVIVE=true, MAX_REVIVE=true, ETHER=true, MAX_ETHER=true, ELIXER=true, MAX_ELIXER=true,
    FRESH_WATER=true, SODA_POP=true, LEMONADE=true,
}

function Helpers.isBallItem(id)
    return type(id) == "string" and id:find("BALL", 1, true) ~= nil
end

function Helpers.isHealItem(id)
    if type(id) ~= "string" then return false end
    return HEAL_IDS[id] == true
        or id:find("POTION", 1, true) ~= nil
        or id:find("HEAL", 1, true) ~= nil
        or id:find("REVIVE", 1, true) ~= nil
        or id:find("RESTORE", 1, true) ~= nil
        or id:find("ETHER", 1, true) ~= nil
        or id:find("ELIXER", 1, true) ~= nil
end

local STATUS_ABBR = {
    PSN = "PSN", POISON = "PSN", POISONED = "PSN",
    PAR = "PAR", PARALYZE = "PAR", PARALYZED = "PAR", PARALYSIS = "PAR",
    BRN = "BRN", BURN = "BRN", BURNED = "BRN",
    FRZ = "FRZ", FREEZE = "FRZ", FROZEN = "FRZ",
    SLP = "SLP", SLEEP = "SLP", ASLEEP = "SLP",
    TOX = "TOX", TOXIC = "TOX", BADLYPOISONED = "TOX",
}

function Helpers.formatStatus(status)
    if status == nil then return status end
    local s = tostring(status)
    if s == "" then return s end
    local key = s:upper():gsub("[^%u]", "")
    return STATUS_ABBR[key] or s
end

function Helpers.expProgress(growth, def, mon, rates)

    local exp = mon.exp or mon.experience
    if not (growth and def and def.growthRate and exp and mon.level) then
        return nil, nil
    end
    local cur = growth.expForLevel(def.growthRate, mon.level, rates)
    local nxt = growth.expForLevel(def.growthRate, mon.level + 1, rates)
    if mon.level >= 100 or nxt <= cur then
        return 1, 0
    end
    local prog = math.max(0, math.min(1, (exp - cur) / (nxt - cur)))
    local next_ = math.max(0, nxt - cur)
    return prog, next_
end

function Helpers.categorizeItems(dItem, itemsTable)
    local balls, heals, other = {}, {}, {}
    for id, count in pairs(itemsTable) do
        if type(count) == "number" and count > 0 then
            local name = (dItem[id] and dItem[id].name) or id
            local row = { id = id, name = name, qty = count }
            if Helpers.isBallItem(id) then
                balls[#balls + 1] = row
            elseif Helpers.isHealItem(id) then
                heals[#heals + 1] = row
            else
                other[#other + 1] = row
            end
        end
    end
    local function byName(a, b) return a.name < b.name end
    table.sort(balls, byName)
    table.sort(heals, byName)
    table.sort(other, byName)
    return balls, heals, other
end

function Helpers.sectionedContentHeight(sections, rowH, headerH, spacing, maxRows)
    local nonEmptyCount = 0
    local totalRows = 0
    for _, sec in ipairs(sections) do
        if #sec.rows > 0 then
            nonEmptyCount = nonEmptyCount + 1
            totalRows = totalRows + #sec.rows
        end
    end
    local rows = maxRows and math.min(totalRows, maxRows) or totalRows
    return (nonEmptyCount * (headerH + spacing)) + (rows * rowH)
end

return Helpers
