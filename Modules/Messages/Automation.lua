local addonName, ns = ...
local GC = ns.GuildCore

local H = ns.MessagesHelpers
local I = ns.MessagesImpl

local DEFAULT_AUTO_SEND_DELAY = H.DEFAULT_AUTO_SEND_DELAY
local DEFAULT_MAX_QUEUE_SIZE  = H.DEFAULT_MAX_QUEUE_SIZE
local SEND_COOLDOWN_SECONDS   = H.SEND_COOLDOWN_SECONDS
local trim = H.trim

function I:GetAutomationEnabled()
    local storage = self:GetStorage()
    return storage and storage.meta.automationEnabled == true or false
end

function I:SetAutomationEnabled(enabled)
    local storage = self:GetStorage()
    if not storage then return false, "Storage not available." end
    storage.meta.automationEnabled = enabled == true
    if not storage.meta.automationEnabled then
        self:StopAutoSend("manual")
    end
    return true
end

function I:GetAutoSendDelaySeconds()
    local storage = self:GetStorage()
    return storage and storage.meta.autoSendDelaySeconds or DEFAULT_AUTO_SEND_DELAY
end

function I:SetAutoSendDelaySeconds(seconds)
    local storage = self:GetStorage()
    if not storage then return false, "Storage not available." end
    seconds = tonumber(seconds)
    if not seconds or seconds < 0.5 then
        return false, "Auto-send delay must be at least 0.5 seconds."
    end
    storage.meta.autoSendDelaySeconds = seconds
    return true
end

function I:GetMaxQueueSize()
    local storage = self:GetStorage()
    return storage and storage.meta.maxQueueSize or DEFAULT_MAX_QUEUE_SIZE
end

function I:GetPreviewTargetName()
    local storage = self:GetStorage()
    return storage and storage.meta.previewTargetName or ""
end

function I:SetPreviewTargetName(name)
    local storage = self:GetStorage()
    if not storage then return false, "Storage not available." end
    storage.meta.previewTargetName = trim(name)
    return true
end

function I:GetDailyTargetTime()
    local storage = self:GetStorage()
    return {
        hour   = storage and storage.meta.dailyTargetHour   or 18,
        minute = storage and storage.meta.dailyTargetMinute or 0,
    }
end

function I:SetDailyTargetTime(hour, minute)
    local storage = self:GetStorage()
    if not storage then return false, "Storage not available." end

    if type(hour) == "string" and minute == nil then
        local parsedHour, parsedMinute = hour:match("^(%d%d?):(%d%d)$")
        hour   = tonumber(parsedHour)
        minute = tonumber(parsedMinute)
    end

    hour   = tonumber(hour)
    minute = tonumber(minute)
    if not hour or not minute or hour < 0 or hour > 23 or minute < 0 or minute > 59 then
        return false, "Time must use HH:MM in 24-hour format."
    end

    storage.meta.dailyTargetHour   = hour
    storage.meta.dailyTargetMinute = minute
    return true
end

function I:IsAutoSending()
    return self._autoSendActive == true
end

function I:GetAutoSendStatus()
    local queueSize = self:GetQueueSize()
    if self:IsAutoSending() then
        local remaining = self:GetSendCooldownRemaining()
        if remaining > 0 then
            return string.format("Auto running - waiting %.1fs - %d queued", remaining, queueSize)
        end
        return string.format("Auto running - %d queued", queueSize)
    end
    if self:GetAutomationEnabled() then
        return string.format("Auto Mode enabled - %d queued", queueSize)
    end
    return string.format("Manual Mode - %d queued", queueSize)
end

function I:GetSendCooldownRemaining()
    local currentTime = GetTime and GetTime() or 0
    if not self._lastSendAt or currentTime <= 0 then return 0 end
    return math.max(0, SEND_COOLDOWN_SECONDS - (currentTime - self._lastSendAt))
end

function I:_ScheduleAutoSendTick(delay)
    local token = self._autoSendToken
    if self._autoSendTimer and self._autoSendTimer.Cancel then
        self._autoSendTimer:Cancel()
    end

    self._autoSendTimer = C_Timer.NewTimer(delay, function()
        if not self._autoSendActive or self._autoSendToken ~= token then
            return
        end

        if not self:IsEnabled() then
            self:StopAutoSend("disabled")
            return
        end

        local ok, err = self:SendNextQueuedMessage()
        if ok then
            if self:GetQueueSize() == 0 then
                self:StopAutoSend("complete")
            else
                self:_ScheduleAutoSendTick(self:GetAutoSendDelaySeconds())
            end
            return
        end

        if err == "Queue is empty." then
            self:StopAutoSend("complete")
            return
        end

        if err and err:find("Please wait", 1, true) then
            self:_ScheduleAutoSendTick(math.max(self:GetAutoSendDelaySeconds(), SEND_COOLDOWN_SECONDS))
            return
        end

        self:StopAutoSend("error")
    end)
end

function I:StartAutoSend()
    if not self:IsEnabled() then return false, "Messaging module is disabled." end
    if not self:GetAutomationEnabled() then return false, "Auto Mode is disabled." end
    if self:GetQueueSize() == 0 then return false, "Queue is empty." end
    if self:IsAutoSending() then return false, "Auto-send is already running." end

    self._autoSendToken  = (self._autoSendToken or 0) + 1
    self._autoSendActive = true
    self:_ScheduleAutoSendTick(0)
    return true
end

function I:StopAutoSend(reason)
    if self._autoSendTimer and self._autoSendTimer.Cancel then
        self._autoSendTimer:Cancel()
    end
    self._autoSendTimer      = nil
    self._autoSendActive     = false
    self._autoSendStopReason = reason or "manual"
    return true
end
