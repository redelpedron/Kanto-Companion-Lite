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
    local partyH = cfg.PARTY_HEADER_H + cfg.PARTY_ROW_H_COMPACT + cfg.PARTY_PANEL_PAD_B

    -- v1.0.67: Encounter panel shows max 5 entries, then party sits directly below it.
    -- Both live in the black space above the game viewport.
    local contentY = topY + totalTopH
    local contentH = math.max(0, gameTop - contentY)

    -- Height for max 5 encounter entries (2 section headers + 5 rows + padding)
    local ENCOUNTER_MAX_H = 140

    -- Tab strip at top of content area
    local tabsY = contentY
    local tabsH = math.min(tabH, contentH)

    -- Encounter/items/battle panel below tabs, capped at 5-entry height
    local encY = tabsY + tabsH
    local encH = math.min(ENCOUNTER_MAX_H, contentH - tabsH - partyH)

    -- Party strip sits directly below the encounter panel
    local partyY = encY + encH
    local partyH_actual = math.min(partyH, math.max(0, contentH - tabsH - encH))

    return {
        isPortrait = true,
        topBar   = { x=x0, y=topY, w=usableW, h=totalTopH, isPortrait=true, stackMode=true },
        -- Tab strip
        rightTabs    = { x=x0, y=tabsY, w=usableW, h=tabsH },
        -- Encounter/Items/Battle panel (max 5 entries visible)
        rightContent = { x=x0, y=encY, w=usableW, h=encH },
        -- Party anchored to bottom of encounter window
        -- showTabHeader=false (explicit): Portrait has no party tab
        -- strip at all, so this panel's own internal "Party" label is
        -- the only place that text appears here.
        party    = { x=x0, y=partyY, w=usableW, h=partyH_actual, isPortrait=true, compact=true, showTabHeader=false },
    }
end
