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
    -- True bottom edge of the screen, only pulled in by a real device
    -- safe-area inset (notch/gesture-bar), not by OFF_LIMITS_PCT -- that
    -- reservation is for the on-screen touch controls, which "Bottom
    -- Topbar" is meant to ignore (positioned/adjusted separately).
    local trueB = H - insets.bottom

    -- "Bottom Topbar" option (landscape only -- see LayoutSystem/SaveService):
    -- the bar's topH slice is taken from the *bottom of the screen*
    -- (trueB) instead of the top, deliberately overlapping the
    -- touch-control strip rather than stopping above it -- and every
    -- content panel below simply shifts to fill whichever end the bar
    -- vacated. contentTop/contentH stay the single source of truth for
    -- party/right/tabs sizing either way, so nothing downstream needs to
    -- know which mode is active.
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
        topBar   = { x=x0, y=barY, w=usableW, h=topH, isPortrait=false, stackMode=false },
        -- showTabHeader is explicit here too, same reasoning as the
        -- isPortrait/compact comment above: `party` is the fallback rect
        -- used when the tab strip is hidden (landscape with no rival
        -- trainer -- see AppController:_applyPartyLayout), so it needs
        -- its own internal "Party" label and must explicitly say so,
        -- not just omit the key, or it could inherit a stale `true` left
        -- over from the last frame that used partyContent instead.
        party    = { x=x0, y=contentTop, w=sideW, h=contentH, isPortrait=false, compact=false, showTabHeader=false },
        -- Party column's own tab-strip/body split (Party / Rival), mirroring
        -- the right column below. Only Landscape publishes these two keys --
        -- Portrait has no party tab strip, so AppController falls back to
        -- plain `party` (untabbed, single panel) whenever they're absent.
        partyTabs    = { x=x0, y=contentTop, w=sideW, h=tabH },
        -- showTabHeader=true: partyTabs (above) already renders the
        -- "Party"/trainer-name label as a tab, so PokemonPanel skips its
        -- own internal copy for whichever of party/rival panel is laid
        -- out here to avoid showing the same text twice.
        partyContent = { x=x0, y=contentTop+tabH, w=sideW, h=contentH-tabH, isPortrait=false, compact=false, showTabHeader=true },
        right    = right,
        -- Right column's own tab-strip/body split, so main.lua (or any
        -- other caller) never has to know the right panel is internally
        -- "tabs on top, content below" or by how much.
        rightTabs    = { x=right.x, y=right.y, w=right.w, h=tabH },
        rightContent = { x=right.x, y=right.y+tabH, w=right.w, h=right.h-tabH, wrapHeight=true },
    }
end
