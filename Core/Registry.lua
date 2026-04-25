-- /GuildCore/Core/Registry.lua
local addonName, ns = ...
local GC = ns.GuildCore

function GC:RegisterModule(name, module)
    self.Modules[name] = module
end

function GC:RegisterService(name, service)
    self.Services[name] = service
end

function GC:GetService(name)
    return self.Services[name]
end
