
--- Math: small utility functions.
local M = {}

function M.clamp(v, min, max)
    return math.max(min, math.min(max, v))
end

function M.countTrue(t)
    local n = 0
    if t then
        for _, v in pairs(t) do
            if v then n = n + 1 end
        end
    end
    return n
end

function M.round(v)
    return math.floor(v + 0.5)
end

function M.formatPlayTime(seconds)
    seconds = math.floor(seconds or 0)
    return string.format("%d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60)
end

return M
