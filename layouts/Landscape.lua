local Helpers = require("util.Helpers")

return function(W, H, cfg)

    local insets = Helpers.getSafeInsets(cfg)
    local x0 = 0
    local x1 = W
    local usableW = W

    local sideW = usableW * cfg.SIDE_PCT
    local topY  = insets.top
    local topH  = cfg.TOP_BAR_H
    local safeB = H * (1 - cfg.OFF_LIMITS_PCT)

    local trueB = H - insets.bottom

    local bottomBar = cfg.topBarBottom == true
    local barY, contentTop
    if bottomBar then
        barY = trueB - topH
        contentTop = topY
    else
        barY = topY
        contentTop = topY + topH
    end
    local contentH = (bottomBar and barY or safeB) - contentTop

    local right = { x=x1-sideW, y=contentTop, w=sideW, h=contentH }
    local tabH  = cfg.TAB_H

    return {

        topBar   = { x=x0, y=barY, w=usableW, h=topH, isPortrait=false, stackMode=false },

        party    = { x=x0, y=contentTop, w=sideW, h=contentH, isPortrait=false, compact=false, showTabHeader=false },

        partyTabs    = { x=x0, y=contentTop, w=sideW, h=tabH },

        partyContent = { x=x0, y=contentTop+tabH, w=sideW, h=contentH-tabH, isPortrait=false, compact=false, showTabHeader=true },
        right    = right,

        rightTabs    = { x=right.x, y=right.y, w=right.w, h=tabH },
        rightContent = { x=right.x, y=right.y+tabH, w=right.w, h=right.h-tabH, wrapHeight=true },
    }
end
