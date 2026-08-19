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

function AppController:shutdown()
    self.mod.log:info("Kanto Companion Lite shutting down...")

    if self._wrappedGame and self._ourUpdate then
        if self._wrappedGame.update == self._ourUpdate then
            self._wrappedGame.update = self._origUpdate
        end
    end

    if love and love.draw and self._ourDraw and love.draw == self._ourDraw then
        love.draw = self._origDraw
    end

    self.life:shutdown()
end

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
end

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

function AppController:_createUtilityComponents()
    local TypeEffectiveness = require("components.TypeEffectiveness")
    local CatchRate         = require("components.CatchRate")
    self.locator:register("TypeEffectiveness", TypeEffectiveness.new(self.locator, {}))
    self.locator:register("CatchRate", CatchRate.new(self.locator, {}))
end

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
    self.layoutSys:setLayout(require("layouts.Adaptive"))
end

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

    self.partyTabs = self.life:createComponent(Tabs, self.locator, {
        x=0, y=0, w=100, tabs={ "Party" }, activeIdx=1,
        changeEvent = "party_tab.changed",
    })

    self.pcPopup  = self.life:createComponent(PCPopup, self.locator, {})
    self.pcPopup:setActive(false)

    self.rivalPan:setActive(false)
    self.partyTabs:setActive(false)
    self.currentPartyDrawers = { self.partyPan }
    self._partyTabsShowing = false

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

    self.renderSys:registerComponent(self.pcPopup)
end

function AppController:_wireUISystem()
    self.uiSys:registerComponent("topBar", self.topBar)

    self.uiSys:registerComponent("party", self.partyPan, true)
    self.uiSys:registerComponent("rival", self.rivalPan, true)
    self.uiSys:registerComponent("partyTabs", self.partyTabs, true)
    self.uiSys:registerComponent("enemy", self.enemyPan, true)
    self.uiSys:registerComponent("route", self.routePan, true)
    self.uiSys:registerComponent("items", self.itemsPan, true)
    self.uiSys:registerComponent("tabs", self.tabs)
end

function AppController:_subscribeEvents()
    local locator = self.locator
    local bus     = self.bus

    bus:subscribe("layout.updated", function(rects)

        self.topBar:setLayout(rects.topBar)

        self:_applyPartyLayout(rects)

        local inBattle = locator:resolve("BattleService"):isInBattle()
        if inBattle and rects.isPortrait then
            self.enemyPan:setLayout({
                x = rects.rightContent.x, y = rects.rightContent.y,
                w = rects.rightContent.w, h = rects.rightContent.h,
                twoColumn = true,
            })
        else

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

    self.currentTabDrawers = {}

    bus:subscribe("hud.restored", function()
        for i, comp in ipairs(self.currentTabDrawers) do
            comp:setActive(i == self.tabs.activeIdx)
        end

        for _, comp in ipairs(self.currentPartyDrawers or {}) do
            comp:setActive(true)
        end
        if self._partyTabsShowing then
            self.partyTabs:setActive(true)
        end
    end)

    bus:subscribe("tab.changed", function(idx)
        for i, comp in ipairs(self.currentTabDrawers) do
            comp:setActive(i == idx)
        end
    end)

    bus:subscribe("party_tab.changed", function(idx)
        self:_applyPartyTab(idx)
    end)

    bus:subscribe("rival_trainer.updated", function(name)
        local hasTrainer = name ~= nil
        self.partyTabs:setTabs(hasTrainer and { "Party", name or "Rival" } or { "Party" })
        self.rivalPan._props.label = name or "Rival"

        self:_applyPartyTab(self.partyTabs.activeIdx)
    end)

    bus:subscribe("battle.started", function()
        local drawers = { self.enemyPan }
        local labels  = { "Battle Info" }
        table.insert(drawers, self.itemsPan)
        table.insert(labels, "Items")
        self.currentTabDrawers = drawers
        self.tabs:setTabs(labels)
        self.tabs.activeIdx = 1

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

        if self._lastLayoutRects then
            self.topBar:setLayout(self._lastLayoutRects.topBar)
        else
            local W, H = love.graphics.getDimensions()
            self.topBar:setLayout({ x=0, y=0, w=W, h=locator:resolve("ConfigService").TOP_BAR_H })
        end
    end)

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

    bus:subscribe("party.updated", function(party)
        local dPoke = locator:resolve("GameService"):getPokemonData()
        local dMove = locator:resolve("GameService"):getMoveData()
        self.partyPan._props.pokemonData = dPoke
        self.enemyPan._props.pokemonData = dPoke
        self.enemyPan._props.moveData    = dMove
        self.routePan._props.pokemonData = dPoke
    end)

    self.mod.events:on("game.ready", function(p)
        self.gameSvc:setGame((p and p.game) or self.gameSvc:getGame())
        self.battleSvc:setBattleStateClass(self.gameSvc:getBattleStateClass())
    end)
end

function AppController:_applyPartyLayout(rects)
    if not rects then return end
    self._lastLayoutRects = rects

    local showPartyTabs = rects.partyTabs ~= nil
    local enteringTabbedParty = showPartyTabs and not self._partyTabsShowing
    self._partyTabsShowing = showPartyTabs

    if showPartyTabs then
        self.partyTabs:setLayout(rects.partyTabs)
        self.partyPan:setLayout(rects.partyContent)
        self.rivalPan:setLayout(rects.partyContent)
        self.partyTabs:setActive(true)
        if enteringTabbedParty then
            self:_applyPartyTab(self.partyTabs.activeIdx)
        end
    else
        self.partyTabs:setActive(false)
        self.partyPan:setLayout(rects.party)
        self:_applyPartyTab(1)
    end
end

function AppController:_applyPartyTab(idx)
    idx = idx or 1
    if self.partyTabs.activeIdx ~= idx then
        self.partyTabs.activeIdx = idx
    end
    self.currentPartyDrawers = (idx == 2) and { self.rivalPan } or { self.partyPan }
    self.partyPan:setActive(idx == 1)
    self.rivalPan:setActive(idx == 2)
end

function AppController:_wrapHooks()
    local mod = self.mod
    local saveSvc = self.saveSvc

    local SettingsScreen = require("core.SettingsScreen")
    SettingsScreen.install(mod, saveSvc, self.locator)

    self.mod.hooks:wrap("ui.options.rows", function(next, game, rows)
        local out = next(game, rows)
        if type(out) ~= "table" then return out end
        out[#out+1] = {
            id = "kanto_companion_lite",
            label = "KANTO COMPANION LITE",
            value = function(g)
                return "SETTINGS"
            end,
            activate = function(g)
                mod.ui.push(g, SettingsScreen.SCREEN_ID)
            end,
        }
        return out
    end)
end

function AppController:_installGameHooks()
    self._origUpdate = nil
    self._ourUpdate  = nil
    self._origDraw   = nil
    self._ourDraw    = nil
    self._wrappedGame = nil
    self._overlayDisabled = false
    self._renderHudFired = false

    local function reportAndDisable(kind, err)
        if self._overlayDisabled then return end
        self._overlayDisabled = true
        self.mod.log:error(("Kanto Companion Lite: overlay %s failed and has been disabled for this session (%s). This can happen on a generation/screen combination the overlay hasn't been verified against yet."):format(kind, tostring(err)))
    end

    local function tick(dt)
        if self._overlayDisabled then return end
        local ok, err = pcall(function() self.life:update(dt) end)
        if not ok then reportAndDisable("update", err); return end
        local ok2, err2 = pcall(function() self.life:draw() end)
        if not ok2 then reportAndDisable("draw", err2) end
    end

    pcall(function()
        self.mod.hooks:wrap("render.hud", function(orig, ...)
            local result = orig(...)
            self._renderHudFired = true
            tick(love.timer and love.timer.getDelta() or 0)
            return result
        end)
    end)

    local function install()
        local g = self.gameSvc:getGame()
        if g and g.update then
            if self._wrappedGame ~= g then
                self._origUpdate = g.update
                self._ourUpdate = function(gameSelf, dt)
                    self._origUpdate(gameSelf, dt)
                end
                g.update = self._ourUpdate
                self._wrappedGame = g
            end
        end
        if love and love.draw and not self._ourDraw then
            self._origDraw = love.draw
            self._ourDraw = function(...)
                if self._origDraw then self._origDraw(...) end
                if self._renderHudFired then return end
                tick(love.timer and love.timer.getDelta() or 0)
            end
            love.draw = self._ourDraw
        end
    end

    self.mod.events:on("game.ready", function()
        local ok, err = pcall(install)
        if not ok then reportAndDisable("install", err) end
    end)
end

function AppController:_registerUnload()

    self.mod._kantoCompanionApp = self

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
