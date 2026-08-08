local Portrait  = require("layouts.Portrait")
local Landscape = require("layouts.Landscape")

return function(W, H, cfg)
    local aspect = W / H
    if aspect < 1.0 then
        return Portrait(W, H, cfg)
    else
        return Landscape(W, H, cfg)
    end
end