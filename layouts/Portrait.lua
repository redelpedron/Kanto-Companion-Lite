local Helpers = require("util.Helpers")

return function(W, H, cfg)
    local insets = Helpers.getSafeInsets(cfg)
    local x0 = insets.left
    local x1 = W - insets.right
    local usableW = math.max(0, x1 - x0)

    local topY  = 0
    local rowH = cfg.TOP_BAR_ROW_H
    local totalTopH = rowH * 2

    local gbW, gbH = 160, 144
    local scale = math.min(W / gbW, H / gbH)
    local renderH = gbH * scale
    local gameY = (H - renderH) / 2
    local gameTop = gameY

    local tabH = cfg.TAB_H

    local partyH = tabH + cfg.PARTY_ROW_H_COMPACT + cfg.PARTY_PANEL_PAD_B

    local VIEWPORT_GAP = 4
    local contentY = topY + totalTopH
    local contentH = math.max(0, gameTop - contentY - VIEWPORT_GAP)

    local ENCOUNTER_MAX_H = 140

    local tabsY = contentY
    local tabsH = math.min(tabH, contentH)

    local encY = tabsY + tabsH
    local encH = math.min(ENCOUNTER_MAX_H, contentH - tabsH - partyH)

    local partyY = encY + encH
    local partyH_actual = math.min(partyH, math.max(0, contentH - tabsH - encH))

    return {
        isPortrait = true,
        topBar   = { x=x0, y=topY, w=usableW, h=totalTopH, isPortrait=true, stackMode=true },

        rightTabs    = { x=x0, y=tabsY, w=usableW, h=tabsH },

        rightContent = { x=x0, y=encY, w=usableW, h=encH },

        party    = { x=x0, y=partyY, w=usableW, h=partyH_actual, isPortrait=true, compact=true, showTabHeader=true },

        partyTabs    = { x=x0, y=partyY, w=usableW, h=tabH },
        partyContent = { x=x0, y=partyY+tabH, w=usableW, h=math.max(0, partyH_actual-tabH),
            isPortrait=true, compact=true, showTabHeader=true },
    }
end
