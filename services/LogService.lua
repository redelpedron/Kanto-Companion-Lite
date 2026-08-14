local LogService = {}
LogService.__index = LogService

function LogService.new(locator)
    local self = setmetatable({}, LogService)
    self._locator = locator
    self._modLog = nil
    return self
end

function LogService:setModLog(modLog)
    self._modLog = modLog
end

function LogService:info(fmt, ...)
    if self._modLog then self._modLog:info(fmt, ...) end
end

function LogService:error(fmt, ...)
    if self._modLog then self._modLog:error(fmt, ...) end
end

return LogService
