
--- ConfigService: holds all constants, colors, and lookup tables.
-- Single source of truth for configuration data.
local ConfigService = {}
ConfigService.__index = ConfigService

function ConfigService.new(locator)
    local self = setmetatable({}, ConfigService)
    self._locator = locator
    return self
end

-- Panel & UI colors
ConfigService.COL = {
    panel       = {0.06, 0.06, 0.08},
    panelTop    = {0.08, 0.08, 0.14},
    border      = {0.2, 0.2, 0.28},
    text        = {1, 1, 1},
    dim         = {0.55, 0.55, 0.6},
    hi          = {0.3, 0.9, 0.4},
    mid         = {0.95, 0.8, 0.2},
    lo          = {0.95, 0.3, 0.3},
    xp          = {0.4, 0.7, 1},
    gold        = {1, 0.8, 0.3},
    tabActive   = {0.25, 0.5, 0.9},
    tabBg       = {0.12, 0.12, 0.18},
    catch       = {0.5, 0.9, 0.5},
    se          = {0.3, 0.9, 0.4},
}

-- Type colors
-- Ball catch-rate multipliers
ConfigService.BALL_MULT = {
    POKE_BALL = 1,
    GREAT_BALL = 1.5,
    ULTRA_BALL = 2,
    MASTER_BALL = 255,
    SAFARI_BALL = 1.5,
}

-- Layout constants
ConfigService.TOP_BAR_H = 28        -- landscape single-row top bar height
ConfigService.TOP_BAR_ROW_H = 24    -- per-row height in portrait's stacked top bar
ConfigService.SIDE_PCT = 0.26
ConfigService.OFF_LIMITS_PCT = 0.20
ConfigService.TAB_H = 28

-- Party panel row/header heights. Centralized here (rather than as
-- local magic numbers inside PokemonPanel.lua) because layouts/Portrait.lua
-- also needs them: portrait's party panel now wraps its height to fit
-- its one compact row, and a pure layout function `(W, H, cfg)` has no
-- access to the live party count/font metrics to size itself off real
-- rendered content.
ConfigService.PARTY_MAX           = 6   -- a Pokémon party is always <= 6
ConfigService.PARTY_HEADER_H      = 20  -- "Party N/6" header row
ConfigService.PARTY_ROW_H         = 34  -- landscape: one row per mon (full detail)
ConfigService.PARTY_ROW_H_COMPACT = 56  -- portrait: ONE row, all mons side by side
                                         -- (icon, then HP number, then status per column)
ConfigService.PARTY_PANEL_PAD_B   = 4   -- bottom inner padding

-- TopBar visual rhythm (icon + text "chips", grouped left/right)
ConfigService.TOPBAR_FONT_SZ   = 12
ConfigService.TOPBAR_PAD_X     = 12  -- inner left/right padding off the bar edge
ConfigService.TOPBAR_GAP       = 16  -- gap between chips within a group
ConfigService.TOPBAR_ICON_SZ   = 10  -- vector icon glyph size
ConfigService.TOPBAR_ICON_GAP  = 5   -- gap between an icon and its text

-- Safe-area (notch / punch-hole camera / gesture-bar) handling
ConfigService.SAFE_AREA_MAX_INSET = 60  -- clamp so a bad reading can't eat the whole bar

return ConfigService
