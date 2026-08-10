return function(mod)
    -- ========================================================================
    -- BOOTSTRAP: gen1recomp loads a mod's main.lua as a standalone chunk;
    -- package.path is never repointed at the mod's own folder, so plain
    -- require() can't find this mod's other files on its own.
    --
    -- v2.0.20 and earlier hand-maintained a list of every module this mod
    -- ships (MOD_MODULES) and pre-registered each one individually. Adding a
    -- file meant remembering to add it here too -- forgetting to did ship
    -- once already (v2.0.19, "module 'util.ScrollableMixin' not found").
    --
    -- Instead: install ONE generic loader in package.searchers/loaders that
    -- answers any require("a.b.c") by reading "a/b/c.lua" straight out of
    -- this mod's own files via mod:read(). New files just work the first
    -- time they're required -- there is no second list to update.
    -- ========================================================================
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

    -- Only needed for this boot's first require() of each module; after
    -- that require() serves the cached result from package.loaded. Remove
    -- it now so it doesn't sit in the shared, engine-wide searchers list
    -- answering (or mis-answering) other mods' requires afterward.
    for i, fn in ipairs(searchers) do
        if fn == modLoader then table.remove(searchers, i) break end
    end
end
