--- AppController: orchestrates mod bootstrap, DI wiring, and lifecycle.
-- Extracted from main.lua to eliminate the God Object anti-pattern.
local AppController = {}
AppController.__index = AppController

function AppController.new(mod)
    local self = setmetatable({}, AppController)
    self.mod = mod
    return self
end

function AppController:init()
    self:_createCore()
    self:_createServices()
    self:_createUtilityComponents()
    self:_createSystems()
    self:_createUIComponents()
    self:_registerSystems()
    self:_registerLayouts()
    self:_registerRenderables()
    self:_wireUISystem()
    self:_subscribeEvents()
    self:_wrapHooks()
    self:_installGameHooks()
    self:_registerUnload()
    self.mod.log:info("Kanto Companion Lite (refactored) loaded.")
end

-- =======================================================================
-- Shutdown: clean restoration of all global hooks and lifecycle teardown
-- =======================================================================
function AppController:shutdown()
    self.mod.log:info("Kanto Companion Lite shutting down...")

    -- Restore game.update hook (only if our wrapper is still in place)
    if self._wrappedGame and self._ourUpdate then
        if self._wrappedGame.update == self._ourUpdate then
            self._wrappedGame.update = self._origUpdate
        end
    end

    -- Restore love.draw hook (only if our wrapper is still in place)
    if love and love.draw and self._ourDraw and love.draw == self._ourDraw then
        love.draw = self._origDraw
    end

    -- Teardown all components and systems (calls InputSystem:destroy(), etc.)
    self.life:shutdown()
end

-- =======================================================================
-- Core infrastructure
-- =======================================================================
function AppController:_createCore()
    local ServiceLocator = require("core.ServiceLocator")
    local EventBus       = require("core.EventBus")
    local Lifecycle      = require("core.Lifecycle")

    self.locator = ServiceLocator.new()
    self.bus     = EventBus.new()
    self.life    = Lifecycle.new()

    self.locator:register("EventBus", self.bus)
    self.locator:register("Lifecycle", self.life)

    local LogService = require("services.LogService")
    local log = LogService.new(self.locator)
    log:setModLog(self.mod.log)
    self.locator:register("LogService", log)
    self.bus:setLogger(log)
    self.life:setLogger(log)
    self.life:setLocator(self.locator)

    local ConfigService = require("services.ConfigService")
    self.locator:register("ConfigService", ConfigService.new(self.locator))

    -- FIX: register DrawContext so components never touch love.graphics directly
    local DrawContext = require("util.DrawContext")
    self.locator:register("DrawContext", DrawContext.new())
end

-- =======================================================================
-- Services
-- =======================================================================
function AppController:_createServices()
    local GameService   = require("services.GameService")
    local BattleService = require("services.BattleService")
    local SaveService   = require("services.SaveService")
    local PCService     = require("services.PCService")

    self.gameSvc   = GameService.new(self.locator)
    self.battleSvc = BattleService.new(self.locator)
    self.saveSvc   = SaveService.new(self.locator)
    self.pcSvc     = PCService.new(self.locator)

    self.saveSvc:setModSave(self.mod.save)
    self.locator:register("GameService", self.gameSvc)
    self.locator:register("BattleService", self.battleSvc)
    self.locator:register("SaveService", self.saveSvc)
    self.locator:register("PCService", self.pcSvc)

    local SpriteService = require("services.SpriteService")
    local FontService   = require("services.FontService")
    self.locator:register("SpriteService", SpriteService.new(self.locator))
    self.locator:register("FontService", FontService.new(self.locator))
end

-- =======================================================================
-- Stateless utility components (no listeners, safe to register early)
-- =======================================================================
function AppController:_createUtilityComponents()
    local TypeEffectiveness = require("components.TypeEffectiveness")
    local CatchRate         = require("components.CatchRate")
    self.locator:register("TypeEffectiveness", TypeEffectiveness.new(self.locator, {}))
    self.locator:register("CatchRate", CatchRate.new(self.locator, {}))
end

-- =======================================================================
-- Systems
-- =======================================================================
function AppController:_createSystems()
    local RenderSystem   = require("systems.RenderSystem")
    local InputSystem    = require("systems.InputSystem")
    local LayoutSystem   = require("systems.LayoutSystem")
    local BattleSystem   = require("systems.BattleSystem")
    local GameDataSystem = require("systems.GameDataSystem")
    local UISystem       = require("systems.UISystem")

    self.renderSys = RenderSystem.new(self.locator)
    self.inputSys  = InputSystem.new(self.locator)
    self.layoutSys = LayoutSystem.new(self.locator)
    self.battleSys = BattleSystem.new(self.locator)
    self.dataSys   = GameDataSystem.new(self.locator)
    self.uiSys     = UISystem.new(self.locator)
end

function AppController:_registerSystems()
    self.life:registerSystem(self.renderSys)
    self.life:registerSystem(self.inputSys)
    self.life:registerSystem(self.layoutSys)
    self.life:registerSystem(self.battleSys)
    self.life:registerSystem(self.dataSys)
    self.life:registerSystem(self.uiSys)
end

function AppController:_registerLayouts()
    self.layoutSys:registerLayout("portrait", require("layouts.Portrait"))
    self.layoutSys:registerLayout("landscape", require("layouts.Landscape"))
    self.layoutSys:registerLayout("adaptive", require("layouts.Adaptive"))
end

-- =======================================================================
-- UI Components
-- =======================================================================
function AppController:_createUIComponents()
    local TopBar       = require("components.TopBar")
    local PokemonPanel = require("components.PokemonPanel")
    local EnemyPanel   = require("components.EnemyPanel")
    local RoutePanel   = require("components.RoutePanel")
    local ItemsPanel   = require("components.ItemsPanel")
    local Tabs         = require("components.Tabs")
    local PCPopup      = require("components.PCPopup")

    self.topBar   = self.life:createComponent(TopBar, self.locator, {})
    self.partyPan = self.life:createComponent(PokemonPanel, self.locator, {})

    -- Landscape-only Rival tab: same row layout as partyPan (PokemonPanel),
    -- fed from the opposing trainer's roster instead of the player's party.
    -- trackEnemyTypes=false: the super-effective name glow is about the
    -- *player's* mons vs the enemy, not the enemy's mons vs itself.
    -- No xpProgress ever gets set on rival rows (see GameDataSystem), so
    -- PokemonPanel's existing per-row check already leaves the xp bar off.
    self.rivalPan = self.life:createComponent(PokemonPanel, self.locator, {
        partyEvent = "rival.updated",
        activeMonEvent = "enemy_active_mon.changed",
        trackEnemyTypes = false,
        label = "Rival",
        emptyMessage = "No trainer battle",
    })

    self.enemyPan = self.life:createComponent(EnemyPanel, self.locator, { pokemonData={}, moveData={} })
    self.routePan = self.life:createComponent(RoutePanel, self.locator, { pokemonData={} })
    self.itemsPan = self.life:createComponent(ItemsPanel, self.locator, {})
    self.tabs     = self.life:createComponent(Tabs, self.locator, { x=0, y=0, w=100, tabs={}, activeIdx=1 })

    -- Second, independent tab strip for the party column (landscape only).
    -- changeEvent keeps its taps from colliding with the right column's
    -- "tab.changed" on the shared EventBus.
    self.partyTabs = self.life:createComponent(Tabs, self.locator, {
        x=0, y=0, w=100, tabs={ "Party", "Rival" }, activeIdx=1,
        changeEvent = "party_tab.changed",
    })

    -- PCPopup is a full-screen modal, not driven by UISystem
    self.pcPopup  = self.life:createComponent(PCPopup, self.locator, {})
    self.pcPopup:setActive(false)

    -- Rival tab and its tab strip start hidden: we don't know yet whether
    -- we're in landscape (layout.updated hasn't fired), and the tab strip
    -- itself only ever appears once a trainer battle is actually underway
    -- (see _hasRivalTrainer / rival_trainer.updated below) -- wild
    -- encounters and free-roam never show it, even in landscape.
    self.rivalPan:setActive(false)
    self.partyTabs:setActive(false)
    self.currentPartyDrawers = { self.partyPan }
    self._isLandscapeParty = false
    -- True only while BattleSystem reports an opposing trainer (see
    -- rival_trainer.updated). Gates whether the Party/Rival tab strip is
    -- allowed to show at all, independent of orientation.
    self._hasRivalTrainer = false
    -- Most recent rects from layout.updated, replayed through
    -- _applyPartyLayout() whenever _hasRivalTrainer flips so the tab strip
    -- can appear/disappear mid-battle without waiting on a resize/rotate.
    self._lastLayoutRects = nil
end

function AppController:_registerRenderables()
    self.renderSys:registerComponent(self.topBar)
    self.renderSys:registerComponent(self.partyTabs)
    self.renderSys:registerComponent(self.partyPan)
    self.renderSys:registerComponent(self.rivalPan)
    self.renderSys:registerComponent(self.enemyPan)
    self.renderSys:registerComponent(self.routePan)
    self.renderSys:registerComponent(self.itemsPan)
    self.renderSys:registerComponent(self.tabs)
    -- Drawn last so it appears on top
    self.renderSys:registerComponent(self.pcPopup)
end

function AppController:_wireUISystem()
    self.uiSys:registerComponent("topBar", self.topBar)
    -- party/rival/partyTabs are tabbed=true: like the right column, only
    -- one of party/rival is ever visible at a time (landscape) or only
    -- party ever exists at all (portrait), and this system must only ever
    -- turn them OFF -- _applyPartyTab()/layout.updated/hud.restored below
    -- own turning them back on.
    self.uiSys:registerComponent("party", self.partyPan, true)
    self.uiSys:registerComponent("rival", self.rivalPan, true)
    self.uiSys:registerComponent("partyTabs", self.partyTabs, true)
    self.uiSys:registerComponent("enemy", self.enemyPan, true)
    self.uiSys:registerComponent("route", self.routePan, true)
    self.uiSys:registerComponent("items", self.itemsPan, true)
    self.uiSys:registerComponent("tabs", self.tabs)
end

-- =======================================================================
-- Event subscriptions
-- =======================================================================
function AppController:_subscribeEvents()
    local locator = self.locator
    local bus     = self.bus

    -- Layout routing -----------------------------------------------------
    bus:subscribe("layout.updated", function(rects)
        -- New TopBar consolidation: single topBar with stackMode in portrait
        self.topBar:setLayout(rects.topBar)

        -- Party column: landscape gets a Party/Rival tab strip (see
        -- Landscape.lua's partyTabs/partyContent), but only while a trainer
        -- battle is actually on (_hasRivalTrainer); otherwise -- and always
        -- in portrait, which has neither key -- it falls back to the
        -- original single, untabbed panel.
        self:_applyPartyLayout(rects)

        local inBattle = locator:resolve("BattleService"):isInBattle()
        if inBattle and rects.isPortrait then
            self.enemyPan:setLayout({
                x = rects.rightContent.x, y = rects.rightContent.y,
                w = rects.rightContent.w, h = rects.rightContent.h,
                twoColumn = true,
            })
        else
            -- FIX: add wrapHeight so landscape EnemyPanel shrinks to content
            self.enemyPan:setLayout({
                x = rects.rightContent.x, y = rects.rightContent.y,
                w = rects.rightContent.w, h = rects.rightContent.h,
                twoColumn = false,
                wrapHeight = true,
            })
        end
        self.routePan:setLayout(rects.rightContent)
        self.itemsPan:setLayout(rects.rightContent)
        self.tabs:setLayout(rects.rightTabs)
    end)

    -- Tab restoration ----------------------------------------------------
    self.currentTabDrawers = {}

    bus:subscribe("hud.restored", function()
        for i, comp in ipairs(self.currentTabDrawers) do
            comp:setActive(i == self.tabs.activeIdx)
        end
        -- Party column: in portrait this is always just {partyPan}; in
        -- landscape it's whichever of party/rival was last selected.
        for _, comp in ipairs(self.currentPartyDrawers or {}) do
            comp:setActive(true)
        end
        if self._isLandscapeParty then
            self.partyTabs:setActive(true)
        end
    end)

    bus:subscribe("tab.changed", function(idx)
        for i, comp in ipairs(self.currentTabDrawers) do
            comp:setActive(i == idx)
        end
    end)

    -- Party/Rival tab strip (landscape only) ------------------------------
    bus:subscribe("party_tab.changed", function(idx)
        self:_applyPartyTab(idx)
    end)

    -- Rival tab label: falls back to "Rival" outside of trainer battles
    -- (or before the first one starts), and to the actual trainer's name
    -- once BattleSystem reports one. `name` is nil for wild encounters and
    -- whenever no battle is running (see BattleSystem), so it doubles as
    -- the trainer-battle flag that gates the tab strip itself below.
    bus:subscribe("rival_trainer.updated", function(name)
        self.partyTabs:setTabs({ "Party", name or "Rival" })
        self.rivalPan._props.label = name or "Rival"

        local hasTrainer = name ~= nil
        if hasTrainer ~= self._hasRivalTrainer then
            self._hasRivalTrainer = hasTrainer
            -- Re-run the party column layout immediately so the tab strip
            -- appears/disappears the instant the trainer battle starts or
            -- ends, rather than waiting on the next resize/rotate to pick
            -- up the new _hasRivalTrainer value.
            self:_applyPartyLayout(self._lastLayoutRects)
        end
    end)

    -- Battle lifecycle ---------------------------------------------------
    bus:subscribe("battle.started", function()
        local drawers = { self.enemyPan }
        local labels  = { "Enemy" }
        table.insert(drawers, self.itemsPan)
        table.insert(labels, "Items")
        self.currentTabDrawers = drawers
        self.tabs:setTabs(labels)
        self.tabs.activeIdx = 1
        -- FIX: explicitly hide the encounter list so it doesn't paint over the battle
        self.routePan:setActive(false)
        for i, comp in ipairs(drawers) do
            comp:setActive(i == 1)
        end
    end)

    bus:subscribe("battle.ended", function()
        local drawers = {}
        local labels  = {}
        table.insert(drawers, self.itemsPan)
        table.insert(labels, "Items")
        self.currentTabDrawers = drawers
        self.tabs:setTabs(labels)
        self.tabs.activeIdx = 1
        self.enemyPan:setActive(false)
        self.routePan:setActive(false)
        self.itemsPan:setActive(true)
        local W, H = love.graphics.getDimensions()
        self.topBar:setLayout({ x=0, y=0, w=W, h=locator:resolve("ConfigService").TOP_BAR_H })
    end)

    -- Route updates ------------------------------------------------------
    bus:subscribe("route.updated", function(route)
        local inBattle = locator:resolve("BattleService"):isInBattle()
        if inBattle then return end
        local hasEnc = route and ((route.grass and #route.grass.species>0) or (route.water and #route.water.species>0))
        local drawers = {}
        local labels  = {}
        if hasEnc then
            table.insert(drawers, self.routePan)
            table.insert(labels, "Encounter")
        end
        table.insert(drawers, self.itemsPan)
        table.insert(labels, "Items")
        self.currentTabDrawers = drawers
        self.tabs:setTabs(labels)
        if self.tabs.activeIdx > #labels then self.tabs.activeIdx = 1 end
        for i, comp in ipairs(drawers) do
            comp:setActive(i == self.tabs.activeIdx)
        end
    end)

    -- Data refresh -------------------------------------------------------
    bus:subscribe("party.updated", function(party)
        local dPoke = locator:resolve("GameService"):getPokemonData()
        local dMove = locator:resolve("GameService"):getMoveData()
        self.partyPan._props.pokemonData = dPoke
        self.enemyPan._props.pokemonData = dPoke
        self.enemyPan._props.moveData    = dMove
        self.routePan._props.pokemonData = dPoke
    end)

    -- Engine game.ready --------------------------------------------------
    self.mod.events:on("game.ready", function(p)
        self.gameSvc:setGame((p and p.game) or self.gameSvc:getGame())
        self.battleSvc:setBattleStateClass(self.gameSvc:getBattleStateClass())
    end)
end

-- =======================================================================
-- Party column tab switching (landscape only: Party / Rival)
-- =======================================================================
-- Decides whether the party column shows the tabbed Party/Rival strip or
-- falls back to a single untabbed panel, and lays out whichever is active.
-- Tabbed mode requires BOTH landscape (rects.partyTabs present) AND an
-- actual trainer battle in progress (self._hasRivalTrainer) -- so the
-- Rival tab never appears outside of a rival/trainer battle, even on a
-- landscape device. Called from layout.updated (on resize/rotate) and
-- from rival_trainer.updated (the instant a trainer battle starts/ends),
-- replaying the last known rects so neither caller needs its own copy of
-- this branching.
function AppController:_applyPartyLayout(rects)
    if not rects then return end
    self._lastLayoutRects = rects

    local showPartyTabs = rects.partyTabs ~= nil and self._hasRivalTrainer
    local enteringLandscapeParty = showPartyTabs and not self._isLandscapeParty
    self._isLandscapeParty = showPartyTabs

    if showPartyTabs then
        self.partyTabs:setLayout(rects.partyTabs)
        self.partyPan:setLayout(rects.partyContent)
        self.rivalPan:setLayout(rects.partyContent)
        self.partyTabs:setActive(true)
        if enteringLandscapeParty then
            self:_applyPartyTab(self.partyTabs.activeIdx)
        end
    else
        self.partyTabs:setActive(false)
        self.partyPan:setLayout(rects.party)
        self:_applyPartyTab(1)
    end
end

-- Mirrors the right column's currentTabDrawers/tab.changed pattern, kept
-- separate because the party column has its own Tabs instance and its
-- own EventBus event ("party_tab.changed") so the two strips don't fight
-- over "tab.changed". Called with idx=1 whenever the tab strip is hidden
-- (portrait, or landscape with no rival battle -- see _applyPartyLayout),
-- which is a no-op past the first call since rivalPan is never laid out
-- or shown there.
function AppController:_applyPartyTab(idx)
    idx = idx or 1
    if self.partyTabs.activeIdx ~= idx then
        self.partyTabs.activeIdx = idx
    end
    self.currentPartyDrawers = (idx == 2) and { self.rivalPan } or { self.partyPan }
    self.partyPan:setActive(idx == 1)
    self.rivalPan:setActive(idx == 2)
end

-- =======================================================================
-- Hook wrapping
-- =======================================================================
function AppController:_wrapHooks()
    local saveSvc = self.saveSvc

    self.mod.hooks:wrap("ui.options.rows", function(next, game, rows)
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

    local ok, err = pcall(function()
        self.mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
            local out = next(game, items)
            table.insert(out, {
                label = saveSvc:isVisible() and "Hide Companion" or "Show Companion",
                action = function() saveSvc:toggleVisible() end
            })
            return out
        end)
    end)
    if not ok then
        self.locator:resolve("LogService"):warning("ui.start_menu.items hook failed: %s", tostring(err))
    end
end

-- =======================================================================
-- Runtime hook installation
-- =======================================================================
function AppController:_installGameHooks()
    self._origUpdate = nil
    self._ourUpdate  = nil
    self._origDraw   = nil
    self._ourDraw    = nil
    self._wrappedGame = nil

    local function install()
        local g = self.gameSvc:getGame()
        if g and g.update then
            if self._wrappedGame ~= g then
                self._origUpdate = g.update
                self._ourUpdate = function(gameSelf, dt)
                    self._origUpdate(gameSelf, dt)
                    self.life:update(dt)
                end
                g.update = self._ourUpdate
                self._wrappedGame = g
            end
        end
        if love and love.draw and not self._ourDraw then
            self._origDraw = love.draw
            self._ourDraw = function(...)
                if self._origDraw then self._origDraw(...) end
                self.life:draw()
            end
            love.draw = self._ourDraw
        end
    end

    self.mod.events:on("game.ready", install)
    if self.gameSvc:getGame() and self.gameSvc:getGame().save and love then
        install()
    end
end

-- =======================================================================
-- Mod unload registration
-- =======================================================================
function AppController:_registerUnload()
    -- Store reference for external/manual cleanup
    self.mod._kantoCompanionApp = self
    -- Attempt to register an engine unload event if one exists
    local ok = pcall(function()
        self.mod.events:on("mod.unload", function()
            self:shutdown()
        end)
    end)
    if not ok then
        self.locator:resolve("LogService"):info("mod.unload event not available; manual cleanup required")
    end
end

return AppController
