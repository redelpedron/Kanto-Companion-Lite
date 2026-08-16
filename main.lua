return function(mod)

    local engineRequire = require
    local cache = {}

    local function modRequire(name)
        local cached = cache[name]
        if cached ~= nil then
            if cached == false then return nil end
            return cached
        end

        local relPath = name:gsub("%.", "/") .. ".lua"
        local src = mod:read(relPath)
        if not src then
            return engineRequire(name)
        end

        local chunk, loadErr = load(src, "@" .. mod.id .. "/" .. relPath)
        if not chunk then
            error(("kanto_companion_lite: syntax error in '%s': %s"):format(relPath, loadErr), 0)
        end

        local result = chunk(name)
        cache[name] = (result == nil) and false or result
        return result
    end

    require = modRequire

    local AppController = require("core.AppController")
    local app = AppController.new(mod)
    app:init()
end
