return function(mod)

    local modBase = (mod.path or ("mods/" .. mod.id)):gsub("/+$", "")

    local function modLoader(name)
        local relPath = name:gsub("%.", "/") .. ".lua"
        local src = mod:read(relPath)
        if not src then
            return ("\n\tno file '%s' in kanto_companion_lite"):format(relPath)
        end
        local chunk, loadErr = load(src, "@" .. modBase .. "/" .. relPath)
        if not chunk then
            error(("kanto_companion_lite: syntax error in '%s': %s"):format(relPath, loadErr), 0)
        end
        return chunk
    end

    local searchers = package.searchers or package.loaders
    table.insert(searchers, 1, modLoader)

    local AppController = require("core.AppController")
    local app = AppController.new(mod)
    app:init()

    for i, fn in ipairs(searchers) do
        if fn == modLoader then table.remove(searchers, i) break end
    end
end
