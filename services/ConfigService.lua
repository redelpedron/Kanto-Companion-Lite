local ConfigService = {}
ConfigService.__index = ConfigService

function ConfigService.new(locator)
    local self = setmetatable({}, ConfigService)
    self._locator = locator
    return self
end

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

    tabActive   = {0.55, 0.55, 0.58},
    tabBg       = {0.14, 0.14, 0.16},
    catch       = {0.5, 0.9, 0.5},
    se          = {0.3, 0.9, 0.4},
    male        = {0.4, 0.7, 1},
    female      = {1, 0.5, 0.75},
}

ConfigService.BALL_MULT = {
    POKE_BALL = 1,
    GREAT_BALL = 1.5,
    ULTRA_BALL = 2,
    MASTER_BALL = 255,
    SAFARI_BALL = 1.5,
}

ConfigService.TOP_BAR_H = 28
ConfigService.TOP_BAR_ROW_H = 24
ConfigService.SIDE_PCT = 0.26
ConfigService.OFF_LIMITS_PCT = 0.20
ConfigService.TAB_H = 28

ConfigService.PARTY_MAX           = 6
ConfigService.PARTY_HEADER_H      = 20
ConfigService.PARTY_ROW_H         = 34
ConfigService.PARTY_ROW_H_COMPACT = 56

ConfigService.PARTY_PANEL_PAD_B   = 4

ConfigService.TOPBAR_FONT_SZ   = 12
ConfigService.TOPBAR_PAD_X     = 12
ConfigService.TOPBAR_GAP       = 16
ConfigService.TOPBAR_ICON_SZ   = 10
ConfigService.TOPBAR_ICON_GAP  = 5

ConfigService.SAFE_AREA_MAX_INSET = 60

ConfigService.DEBUG_SAFARI = false

return ConfigService
