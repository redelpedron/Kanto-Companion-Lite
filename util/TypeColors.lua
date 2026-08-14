local TypeColors = {}

local TYPE = {
    NORMAL = {0.65,0.65,0.6},   FIRE = {0.95,0.45,0.25},
    WATER = {0.25,0.55,0.95},   ELECTRIC = {0.95,0.85,0.2},
    GRASS = {0.4,0.8,0.35},     ICE = {0.5,0.85,0.9},
    FIGHTING = {0.85,0.35,0.25}, POISON = {0.75,0.4,0.75},
    GROUND = {0.8,0.7,0.4},     FLYING = {0.6,0.55,0.9},
    PSYCHIC = {0.9,0.35,0.55},  BUG = {0.65,0.75,0.25},
    ROCK = {0.7,0.6,0.4},       GHOST = {0.55,0.4,0.65},
    DRAGON = {0.5,0.35,0.85},
}

local DEFAULT_COLOR = {0.55, 0.55, 0.6}

local NORMALIZED_CACHE = {}

function TypeColors.normalize(t)
    if type(t) ~= "string" then return "" end

    local cached = NORMALIZED_CACHE[t]
    if cached then return cached end

    local normalized = t:gsub("_TYPES?$", ""):upper():match("^%s*(.-)%s*$")

    if TYPE[normalized] then
        NORMALIZED_CACHE[t] = normalized
    end

    return normalized
end

function TypeColors.getColor(typeName)
    return TYPE[TypeColors.normalize(typeName)] or DEFAULT_COLOR
end

return TypeColors
