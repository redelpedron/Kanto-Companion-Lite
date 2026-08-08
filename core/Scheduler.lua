
--- Scheduler: throttled task runner and frame accumulator.
-- Replaces the manual `C.acc` pattern in the original code.
local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new()
    local self = setmetatable({}, Scheduler)
    self._tasks = {}
    self._acc = 0
    return self
end

--- Register a task that fires every `interval` seconds.
-- Returns a cancel function.
function Scheduler:every(interval, fn)
    local task = {
        interval = interval,
        fn = fn,
        acc = 0,
        active = true,
    }
    table.insert(self._tasks, task)
    return function() task.active = false end
end

--- Tick all tasks with dt.
function Scheduler:update(dt)
    self._acc = self._acc + dt
    for _, task in ipairs(self._tasks) do
        if task.active then
            task.acc = task.acc + dt
            if task.acc >= task.interval then
                task.acc = task.acc - task.interval
                local ok, err = pcall(task.fn)
                if not ok and self._log then
                    self._log:error("Scheduler: %s", tostring(err))
                end
            end
        end
    end
end

--- Reset the global accumulator.
function Scheduler:reset()
    self._acc = 0
end

function Scheduler:setLogger(log)
    self._log = log
end

return Scheduler
