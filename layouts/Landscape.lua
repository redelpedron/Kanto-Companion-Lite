local Helpers = require("util.Helpers")

return function(W, H, cfg)
    -- Landscape intentionally runs edge-to-edge left/right: the top bar,
    -- party panel, and right (items/enemy/route) panel all span the full
    -- device width with no side margins, even under a side-mounted
    -- notch/punch-hole camera. Only the top inset is still respected here
    -- (a top-mounted cutout would stay top-mounted after rotation).
    local insets = Helpers.getSafeInsets(cfg)
    local x0 = 0
    local x1 = W
    local usableW = W

    local sideW = usableW * cfg.SIDE_PCT
    local topY  = insets.top
    local topH  = cfg.TOP_BAR_H
    local safeB = H * (1 - cfg.OFF_LIMITS_PCT)

    local right = { x=x1-sideW, y=topY+topH, w=sideW, h=safeB-(topY+topH) }
    local tabH  = cfg.TAB_H

    return {
        -- isPortrait/compact are explicit `false` here (not just absent)
        -- on purpose: LayoutSystem republishes a fresh rect every frame,
        -- but Component:setLayout() only *merges* keys into _props, it
        -- never clears ones missing from the new rect. If this rect
        -- omitted these flags, rotating from portrait to landscape would
        -- leave TopBar/PokemonPanel's props holding the previous frame's
        -- isPortrait=true/compact=true forever (Lua can't merge-clear a
        -- key with an absent value the way it could with an explicit
        -- false) -- exactly the "landscape party/top bar showing stale
        -- portrait content" bug this guards against.
        topBar   = { x=x0, y=topY, w=usableW, h=topH, isPortrait=false, stackMode=false },
        party    = { x=x0, y=topY+topH, w=sideW, h=safeB-(topY+topH), isPortrait=false, compact=false },
        right    = right,
        -- Right column's own tab-strip/body split, so main.lua (or any
        -- other caller) never has to know the right panel is internally
        -- "tabs on top, content below" or by how much.
        rightTabs    = { x=right.x, y=right.y, w=right.w, h=tabH },
        rightContent = { x=right.x, y=right.y+tabH, w=right.w, h=right.h-tabH, wrapHeight=true },
    }
end
