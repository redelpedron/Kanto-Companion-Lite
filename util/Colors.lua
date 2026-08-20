local Colors = {}

function Colors.set(c, a)
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

function Colors.hpColor(frac)
    if frac > 0.5 then return {0.3, 0.9, 0.4}
    elseif frac > 0.2 then return {0.95, 0.8, 0.2}
    else return {0.95, 0.3, 0.3} end
end

function Colors.hpBarColor(frac)
    if frac <= 0 then return {0.45, 0.45, 0.48} end
    return Colors.hpColor(frac)
end

function Colors.fpsColor(fps)
    if fps >= 55 then return {0.3, 0.9, 0.4}
    elseif fps >= 30 then return {0.95, 0.8, 0.2}
    else return {0.95, 0.3, 0.3} end
end

function Colors.batteryColor(percent, charging)
    if charging then return {0.3, 0.9, 0.4} end
    if percent > 50 then return {0.3, 0.9, 0.4}
    elseif percent > 20 then return {0.95, 0.8, 0.2}
    else return {0.95, 0.3, 0.3} end
end

function Colors.timeOfDayColor(hour)
    local isDay = hour >= 6 and hour < 18
    if isDay then
        return {1, 0.8, 0.3}, "Day", true
    else
        return {0.4, 0.7, 1}, "Night", false
    end
end

return Colors
