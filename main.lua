return function(mod)
    -- ========================================================================
    -- BOOTSTRAP: gen1recomp loads a mod's main.lua as a standalone chunk;
    -- package.path is never repointed at the mod's own folder, so a plain
    -- require("core.ServiceLocator") can never resolve here — not in a dev
    -- checkout, not from the save-dir mods folder, and never from inside a
    -- packaged/fused build (where there is no real OS path to io.open at
    -- all). That mismatch is exactly what the mod manager was reporting.
    --
    -- The one supported, packaging-safe way to read a mod's own files is
    -- mod:read() (Reference: The Mod Object > Assets and files). Rather
    -- than rewrite every require("core.X") / require("services.X") call
    -- across this mod's ~30 files, we populate package.preload for each
    -- of them: require() always checks package.preload first, before it
    -- ever touches package.path, so every existing require() call below
    -- and inside components/, services/, systems/, layouts/ and util/
    -- keeps working completely unchanged.
    -- ========================================================================
    local MOD_MODULES = {
        "core.Component", "core.EventBus", "core.Lifecycle",
        "core.Scheduler", "core.ServiceLocator", "core.System",
        "layouts.Adaptive", "layouts.Landscape", "layouts.Portrait",
        "services.BattleService", "services.ConfigService", "services.FontService",
        "services.GameService", "services.LogService", "services.PCService",
        "services.SaveService", "services.SpriteService",
        "systems.BattleSystem", "systems.GameDataSystem", "systems.InputSystem",
        "systems.LayoutSystem", "systems.RenderSystem", "systems.UISystem",
        "components.BadgeWidget", "components.CatchRate", "components.EnemyPanel",
        "components.ExpBar", "components.ItemsPanel", "components.PCPopup",
        "components.PokemonPanel", "components.RoutePanel", "components.StatusWidget",
        "components.Tabs", "components.TopBar", "components.TypeEffectiveness",
        "util.Colors", "util.Helpers", "util.Math", "util.TypeColors", "util.Viewport",
    }

    local modBase = (mod.path or ("mods/" .. mod.id)):gsub("/+$", "")
    local registeredPreloads = {}
    for _, name in ipairs(MOD_MODULES) do
        if not package.preload[name] then
            local relPath = name:gsub("%.", "/") .. ".lua"
            registeredPreloads[name] = true
            package.preload[name] = function()
                local src, err = mod:read(relPath)
                if not src then
                    error(("voxel_hud: could not read '%s' (%s)"):format(relPath, tostring(err)), 0)
                end
                local chunk, loadErr = load(src, "@" .. modBase .. "/" .. relPath)
                if not chunk then
                    error(("voxel_hud: syntax error in '%s': %s"):format(relPath, loadErr), 0)
                end
                return chunk()
            end
        end
    end

    -- Core bootstrap
    local ServiceLocator = require("core.ServiceLocator")
    local EventBus       = require("core.EventBus")
    local Lifecycle      = require("core.Lifecycle")
    local Scheduler      = require("core.Scheduler")

    local locator = ServiceLocator.new()
    local bus     = EventBus.new()
    local life    = Lifecycle.new()
    local sched   = Scheduler.new()

    locator:register("EventBus", bus)
    locator:register("Scheduler", sched)
    locator:register("Lifecycle", life)

    local LogService = require("services.LogService")
    local log = LogService.new(locator)
    log:setModLog(mod.log)
    locator:register("LogService", log)
    bus:setLogger(log)
    sched:setLogger(log)

    local ConfigService = require("services.ConfigService")
    locator:register("ConfigService", ConfigService.new(locator))

    local GameService   = require("services.GameService")
    local BattleService = require("services.BattleService")
    local SaveService   = require("services.SaveService")
    local PCService     = require("services.PCService")
    local gameSvc   = GameService.new(locator)
    local battleSvc = BattleService.new(locator)
    local saveSvc   = SaveService.new(locator)
    local pcSvc     = PCService.new(locator)
    saveSvc:setModSave(mod.save)
    locator:register("GameService", gameSvc)
    locator:register("BattleService", battleSvc)
    locator:register("SaveService", saveSvc)
    locator:register("PCService", pcSvc)

    local SpriteService = require("services.SpriteService")
    local FontService   = require("services.FontService")
    locator:register("SpriteService", SpriteService.new(locator))
    locator:register("FontService", FontService.new(locator))

    local TypeEffectiveness = require("components.TypeEffectiveness")
    local CatchRate         = require("components.CatchRate")
    locator:register("TypeEffectiveness", TypeEffectiveness.new(locator, {}))
    locator:register("CatchRate", CatchRate.new(locator, {}))

    local RenderSystem   = require("systems.RenderSystem")
    local InputSystem    = require("systems.InputSystem")
    local LayoutSystem   = require("systems.LayoutSystem")
    local BattleSystem   = require("systems.BattleSystem")
    local GameDataSystem = require("systems.GameDataSystem")
    local UISystem       = require("systems.UISystem")

    local renderSys = RenderSystem.new(locator)
    local inputSys  = InputSystem.new(locator)
    local layoutSys = LayoutSystem.new(locator)
    local battleSys = BattleSystem.new(locator)
    local dataSys   = GameDataSystem.new(locator)
    local uiSys     = UISystem.new(locator)

    life:registerSystem(renderSys)
    life:registerSystem(inputSys)
    life:registerSystem(layoutSys)
    life:registerSystem(battleSys)
    life:registerSystem(dataSys)
    life:registerSystem(uiSys)

    layoutSys:registerLayout("portrait", require("layouts.Portrait"))
    layoutSys:registerLayout("landscape", require("layouts.Landscape"))
    layoutSys:registerLayout("adaptive", require("layouts.Adaptive"))

    local TopBar      = require("components.TopBar")
    local PokemonPanel= require("components.PokemonPanel")
    local EnemyPanel  = require("components.EnemyPanel")
    local RoutePanel  = require("components.RoutePanel")
    local ItemsPanel  = require("components.ItemsPanel")
    local PCPopup     = require("components.PCPopup")
    local Tabs        = require("components.Tabs")

    local topBar   = life:createComponent(TopBar, locator, {})
    local topBar2  = life:createComponent(TopBar, locator, {})  -- Second bar for portrait stacked mode
    local partyPan = life:createComponent(PokemonPanel, locator, {})
    local enemyPan = life:createComponent(EnemyPanel, locator, { pokemonData={}, moveData={} })
    local routePan = life:createComponent(RoutePanel, locator, { pokemonData={} })
    local itemsPan = life:createComponent(ItemsPanel, locator, {})
    local tabs     = life:createComponent(Tabs, locator, { x=0, y=0, w=100, tabs={}, activeIdx=1 })
    -- PCPopup is a full-screen modal, not a HUD panel: it opens/closes
    -- itself (via the "pc.open" event and its own battle/visibility
    -- listeners) rather than being driven by UISystem's shouldShow loop,
    -- so it's deliberately left out of uiSys:registerComponent below.
    local pcPopup  = life:createComponent(PCPopup, locator, {})
    pcPopup:setActive(false)

    renderSys:registerComponent(topBar)
    renderSys:registerComponent(topBar2)  -- Second top bar for portrait stacked mode
    renderSys:registerComponent(partyPan)
    renderSys:registerComponent(enemyPan)
    renderSys:registerComponent(routePan)
    renderSys:registerComponent(itemsPan)
    renderSys:registerComponent(tabs)
    -- Registered last so it draws on top of every other panel.
    renderSys:registerComponent(pcPopup)

    uiSys:registerComponent("topBar", topBar)
    uiSys:registerComponent("topBar2", topBar2, true)  -- tabbed: UISystem only turns OFF, main.lua controls ON
    uiSys:registerComponent("party", partyPan)
    uiSys:registerComponent("enemy", enemyPan, true)
    uiSys:registerComponent("route", routePan, true)
    uiSys:registerComponent("items", itemsPan, true)
    uiSys:registerComponent("tabs", tabs)

    bus:subscribe("layout.updated", function(rects)
        -- Handle portrait stacked mode with two bars
        if rects.topBar1 and rects.topBar2 then
            -- Portrait stacked mode
            topBar:setLayout(rects.topBar1)
            topBar2:setLayout(rects.topBar2)
            topBar:setActive(true)
            topBar2:setActive(true)
        else
            -- Landscape mode: use single topBar, disable second
            topBar:setLayout(rects.topBar)
            topBar2:setActive(false)
        end

        partyPan:setLayout(rects.party)

        -- rightTabs/rightContent are the right column's own tab-strip
        -- vs. body split, computed by the active layout module (see
        -- layouts/Landscape.lua and layouts/Portrait.lua) -- main.lua
        -- just wires each rect to the component that owns it instead of
        -- re-deriving the split itself. setLayout() merges x/y/w/h in
        -- without disturbing pokemonData/moveData already sitting in
        -- enemyPan/routePan's props (see party.updated below).
        -- v1.0.68: portrait battle uses two-column layout
        -- v1.0.68-fix: explicitly clear twoColumn when not in portrait battle
        -- because setLayout() merges props and twoColumn would persist
        local inBattle = locator:resolve("BattleService"):isInBattle()
        if inBattle and rects.isPortrait then
            enemyPan:setLayout({ x=rects.rightContent.x, y=rects.rightContent.y,
                                 w=rects.rightContent.w, h=rects.rightContent.h, twoColumn=true })
        else
            enemyPan:setLayout({ x=rects.rightContent.x, y=rects.rightContent.y,
                                 w=rects.rightContent.w, h=rects.rightContent.h,
                                 twoColumn=false, wrapHeight=true })
        end
        routePan:setLayout(rects.rightContent)
        itemsPan:setLayout(rects.rightContent)
        tabs:setLayout(rects.rightTabs)
    end)

    local currentTabDrawers = {}
    local function activateTab(idx)
        for _, comp in ipairs({enemyPan, routePan, itemsPan}) do
            comp:setActive(false)
        end
        if currentTabDrawers[idx] then
            currentTabDrawers[idx]:setActive(true)
        end
    end
    bus:subscribe("tab.changed", function(idx, label)
        activateTab(idx)
    end)

    -- UISystem forces every tabbed panel off while a native menu (e.g. the
    -- battle Item list) is open, and has no way to turn the right one back
    -- on itself once that menu closes -- see UISystem.lua. Restore whatever
    -- tab was active before it closed.
    bus:subscribe("hud.restored", function()
        activateTab(tabs.activeIdx)
    end)

    bus:subscribe("battle.started", function()
        currentTabDrawers = { enemyPan }
        tabs:setTabs({ "Battle" })
        tabs.activeIdx = 1
        enemyPan:setActive(true)
        routePan:setActive(false)
        itemsPan:setActive(false)
        local W, H = love.graphics.getDimensions()
        local cfg = locator:resolve("ConfigService")
        topBar:setLayout({ x=0, y=H-cfg.TOP_BAR_H, w=W, h=cfg.TOP_BAR_H })
    end)

    bus:subscribe("battle.ended", function()
        -- The Encounter tab's real hasEnc check lives in route.updated,
        -- which GameDataSystem republishes right away on the next tick;
        -- default to Items only here and let that handler add Encounter
        -- back in as soon as it knows the current route's data.
        currentTabDrawers = { itemsPan }
        local labels = { "Items" }
        tabs:setTabs(labels)
        tabs.activeIdx = 1
        enemyPan:setActive(false)
        routePan:setActive(false)
        itemsPan:setActive(true)
        local W, H = love.graphics.getDimensions()
        topBar:setLayout({ x=0, y=0, w=W, h=locator:resolve("ConfigService").TOP_BAR_H })
    end)

    bus:subscribe("route.updated", function(route)
        local inBattle = locator:resolve("BattleService"):isInBattle()
        if inBattle then return end
        local hasEnc = route and ((route.grass and #route.grass.species>0) or (route.water and #route.water.species>0))
        local drawers = {}
        local labels  = {}
        if hasEnc then
            table.insert(drawers, routePan)
            table.insert(labels, "Encounter")
        end
        table.insert(drawers, itemsPan)
        table.insert(labels, "Items")
        currentTabDrawers = drawers
        tabs:setTabs(labels)
        if tabs.activeIdx > #labels then tabs.activeIdx = 1 end
        for i, comp in ipairs(drawers) do
            comp:setActive(i == tabs.activeIdx)
        end
    end)

    -- NOTE: this still writes individual _props fields directly rather
    -- than through setLayout(). That's deliberate for now -- pokemonData/
    -- moveData are data props, not layout geometry, so they're a
    -- different problem than the one setLayout() was introduced to fix.
    -- Left as a follow-up (see roadmap: reducing direct component data
    -- pokes from main.lua).
    bus:subscribe("party.updated", function(party)
        local dPoke = locator:resolve("GameService"):getPokemonData()
        local dMove = locator:resolve("GameService"):getMoveData()
        partyPan._props.pokemonData = dPoke
        enemyPan._props.pokemonData = dPoke
        enemyPan._props.moveData    = dMove
        routePan._props.pokemonData = dPoke
    end)

    mod.events:on("game.ready", function(p)
        gameSvc:setGame((p and p.game) or gameSvc:getGame())
        local BattleState = require("src.battle.BattleState")
        battleSvc:setBattleStateClass(BattleState)
    end)

    mod.hooks:wrap("ui.options.rows", function(next, game, rows)
        local out = next(game, rows)
        if type(out) ~= "table" then return out end
        out[#out+1] = {
            id = "kanto_companion_lite",
            label = "KANTO COMPANION LITE",
            value = function(g)
                return saveSvc:isVisible() and "ON" or "OFF"
            end,
            step = function(g, dir)
                saveSvc:toggleVisible()
                return true
            end,
        }
        return out
    end)

    pcall(function()
        mod.hooks:wrap("ui.start_menu.items", function(original, game)
            local items = original(game)
            table.insert(items, {
                label = saveSvc:isVisible() and "Hide Companion" or "Show Companion",
                action = function() saveSvc:toggleVisible() end
            })
            return items
        end)
    end)

    local _origUpdate = nil
    local _origDraw   = nil

    local function installHooks()
        local g = gameSvc:getGame()
        if g and g.update and not _origUpdate then
            _origUpdate = g.update
            g.update = function(self, dt)
                _origUpdate(self, dt)
                -- Scheduler is registered with the ServiceLocator but is not
                -- a Lifecycle System, so nothing else drives its tasks.
                -- GameDataSystem's 0.2s tick() (party/trainer/route/inventory
                -- data pull) is registered via scheduler:every() in its
                -- init(), so without this call it silently never fires and
                -- every panel is stuck on its empty default state.
                sched:update(dt)
                life:update(dt)
            end
        end
        if love and love.draw and not _origDraw then
            _origDraw = love.draw
            love.draw = function(...)
                if _origDraw then _origDraw(...) end
                life:draw()
            end
        end
    end

    mod.events:on("game.ready", installHooks)
    if gameSvc:getGame() and gameSvc:getGame().save and love then
        installHooks()
    end

    mod.log:info("Kanto Companion Lite (refactored) loaded.")

    -- package.preload entries are only needed for each module's first
    -- require(); after that, require() serves the cached instance
    -- straight out of package.loaded (util.TypeColors, required lazily
    -- at draw time by EnemyPanel/PokemonPanel, is already cached here
    -- because TypeEffectiveness required it up front). Clearing our
    -- entries now avoids leaving this mod's module names sitting in the
    -- shared, engine-wide package.preload table indefinitely.
    for name in pairs(registeredPreloads) do
        package.preload[name] = nil
    end
end