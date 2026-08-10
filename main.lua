return function(mod)
    -- ========================================================================
    -- BOOTSTRAP: gen1recomp loads a mod's main.lua as a standalone chunk;
    -- package.path is never repointed at the mod's own folder. We populate
    -- package.preload so every existing require() keeps working unchanged.
    -- ========================================================================
    local MOD_MODULES = {
        "core.AppController", "core.Component", "core.EventBus", "core.Lifecycle",
        "core.Scheduler", "core.ServiceLocator", "core.System",
        "layouts.Adaptive", "layouts.Landscape", "layouts.Portrait",
        "services.BattleService", "services.ConfigService", "services.FontService",
        "services.GameService", "services.LogService", "services.PCService",
        "services.SaveService", "services.SpriteService",
        "systems.BattleSystem", "systems.GameDataSystem", "systems.InputSystem",
        "systems.LayoutSystem", "systems.RenderSystem", "systems.UISystem",
        "components.CatchRate", "components.EnemyPanel",
        "components.ExpBar", "components.ItemsPanel", "components.PCPopup",
        "components.PokemonPanel", "components.RoutePanel",
        "components.Tabs", "components.TopBar", "components.TypeEffectiveness",
        "util.Colors", "util.DrawContext", "util.Helpers", "util.Math",
        "util.ScrollableMixin", "util.TypeColors", "util.Viewport",
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
                    error(("kanto_companion_lite: could not read '%s' (%s)"):format(relPath, tostring(err)), 0)
                end
                local chunk, loadErr = load(src, "@" .. modBase .. "/" .. relPath)
                if not chunk then
                    error(("kanto_companion_lite: syntax error in '%s': %s"):format(relPath, loadErr), 0)
                end
                return chunk()
            end
        end
    end

    local AppController = require("core.AppController")
    local app = AppController.new(mod, registeredPreloads)
    app:init()

    -- package.preload entries are only needed for each module's first
    -- require(); after that, require() serves the cached instance
    -- straight out of package.loaded. Clearing our entries now avoids
    -- leaving this mod's module names sitting in the shared, engine-wide
    -- package.preload table indefinitely.
    for name in pairs(registeredPreloads) do
        package.preload[name] = nil
    end
end
