
--- Helpers: general-purpose utilities.
local Colors = require("util.Colors")

local Helpers = {}

-- ---------------------------------------------------------------------
-- Mixin composition: copy every function from `mixin` onto `class` without
-- disturbing `class`'s own `__index`/metatable chain to Component. Used to
-- attach ScrollableMixin to components that already inherit from Component.
-- ---------------------------------------------------------------------

function Helpers.mixin(class, mixinTable)
    for k, v in pairs(mixinTable) do
        if type(v) == "function" then
            class[k] = v
        end
    end
    return class
end

-- ---------------------------------------------------------------------
-- Safe-area (notch / punch-hole front camera / gesture-bar) support.
-- Pure engine query, same category as util.Colors already touching
-- love.graphics -- not a "game.save" architecture leak.
-- ---------------------------------------------------------------------

--- Returns { top, right, bottom, left } padding (px) to keep clear of
-- device cutouts. Backed by love.window.getSafeArea() (LOVE 11.4+); on
-- engines/backends where it's unavailable this safely reports all
-- zeros rather than guessing.
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

-- ---------------------------------------------------------------------
-- Tiny vector icon glyphs for HUD chips (TopBar and friends). Pure
-- love.graphics drawing -- caller sets the color beforehand with
-- Colors.set, same convention as everywhere else in this codebase.
-- ---------------------------------------------------------------------
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

ICONS.caught = function(cx, cy, s) -- pokeball
    local r = s * 0.5
    love.graphics.circle("line", cx, cy, r)
    love.graphics.line(cx - r, cy, cx + r, cy)
    love.graphics.circle("fill", cx, cy, r * 0.28)
    love.graphics.circle("line", cx, cy, r * 0.28)
end

ICONS.seen = function(cx, cy, s) -- eye
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

-- Cuts a crescent out of a filled circle using a second circle drawn in
-- the background color -- cheap, no stencil buffer needed, correct as
-- long as the chip sits on a flat-colored background (true for this
-- HUD's top bar). `bg` is that background color; falls back to a plain
-- filled circle if the caller doesn't supply one.
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

--- Draws a small icon glyph centered at (cx, cy). `size` is its
-- bounding box in px. `bg` is only used by "moon" (see above). Colors
-- are the caller's responsibility (Colors.set before calling), except
-- "moon" which resets its own color for the cutout and leaves the
-- graphics color state as `bg` on return -- callers drawing anything
-- after a moon icon should re-apply Colors.set themselves.
function Helpers.drawIcon(name, cx, cy, size, bg)
    local fn = ICONS[name]
    if not fn then return end
    fn(cx, cy, size, bg)
end

-- Successful requires are already cached by Lua's own package.loaded, but a
-- FAILED require (module genuinely absent) is not cached anywhere, so every
-- caller re-walks the package search path on every single call. Cache both
-- outcomes here so callers (e.g. GameService's per-tick lookups) don't pay
-- that cost repeatedly. MISSING is a distinct sentinel from nil so "never
-- tried" and "tried, confirmed absent" aren't ambiguous.
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

-- Gen 1 has no bag pockets, so items are classified by id for display.
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

-- Progress toward the next level, as a 0..1 fraction (plus exp still
-- needed) for `mon` given its species growth-rate curve. Requires the
-- engine's growth system (src.pokemon.Growth, see GameService) and the
-- species def for its growthRate. Returns nil, nil if any required piece
-- is missing (no growth system, no def, mon not carrying exp/level yet)
-- -- callers that want to hide an xp bar rather than draw a misleading
-- empty one (see PokemonPanel's `m.xpProgress ~= nil` check) rely on
-- that nil, not a 0 fallback.
-- Extracted from two near-identical copies: GameDataSystem (building the
-- party.updated payload) and PCPopup (the PC-popup party view), which
-- had drifted into two independent implementations of the same formula.
function Helpers.expProgress(growth, def, mon, rates)
    if not (growth and def and def.growthRate and mon.exp and mon.level) then
        return nil, nil
    end
    local cur = growth.expForLevel(def.growthRate, mon.level, rates)
    local nxt = growth.expForLevel(def.growthRate, mon.level + 1, rates)
    if mon.level >= 100 or nxt <= cur then
        return 1, 0
    end
    local prog = math.max(0, math.min(1, (mon.exp - cur) / (nxt - cur)))
    local next_ = math.max(0, nxt - cur)
    return prog, next_
end

-- Splits {itemId=count} into Balls / Healing / Other, sorted by name --
-- the shared 3-bucket scheme both ItemsPanel and PCPopup display, so
-- both mod-wide item lists always agree on categorization/ordering.
-- Extracted from two near-identical hand-rolled copies (v2.1.41 and
-- earlier). Each row is {id, name, qty}.
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

-- Sum content height across a list of {rows = {...}, ...} sections -- the
-- shape both ItemsPanel and PCPopup's item lists use after categorizeItems
-- (BALLS/HEALING/OTHER). Empty sections contribute nothing. Was previously
-- reimplemented independently in three places: ItemsPanel's wrap-height
-- size prediction, ItemsPanel's real scroll content height, and PCPopup's
-- _drawItemList -- the last of those uses different rowH/headerH (its
-- modal has bigger rows), which is real, deliberate variability, but the
-- formula shape was identical in all three.
--
-- maxRows caps the TOTAL row count summed across all sections (not
-- per-section) before multiplying by rowH -- this is what lets
-- ItemsPanel's wrap-height prediction (capped at ~9 visible rows) share
-- this same helper with the real, uncapped content-height calculations.
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
