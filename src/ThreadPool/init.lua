--[[
    Multithreadpool-luau
    Author: XxprofessgamerxX (github: michlbro)
    09/06/2023
]]

local RunService = game:GetService("RunService")
local environment = RunService:IsServer() and "Server" or "Client"
local environmentPath = (function()
    if environment == "Server" then
        return game:GetService("ServerScriptService")
    else
        return game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts")
    end
end)()

-- Keep track of all threadPoolIds
local threadPoolId = 0
local threadPool = {}

--[[
    Queue tasks for actors to run.
    @params tuple, parameters for your bound modulescript
]]--
function threadPool:QueueTask(...)
    table.insert(self._taskQueue, {params = {...}})
end

-- Yields current thread until all actors are free and there are no tasks
function threadPool:Join()
    if #self._taskQueue == 0 and #self._freeActors == self._actorHighestId then
        return
    end
    table.insert(self._joinThreads, coroutine.running())
    coroutine.yield()
end

-- Actor Creation
local function CreateActor(parent, id)
    local actor = script[environment]:Clone()
    actor.Name = id
    actor.Parent = parent
    actor.ActorScript.Enabled = true
    return actor
end

--[[
    Create ThreadPool Object
    @params threads: number, number of actors created
    @params module: modulescript, modulescript that will run under actors
    @params sharedTable: sharedTable, optional table to store states global to all actors
    @params callbackFund: function, values returned from each actor after execution
]]
local function CreateThreadPool(threads, module, sharedTable, callbackFunc)
    local self = {}
    self.id = threadPoolId
    threadPoolId += 1

    -- ThreadPool path
    self.threadPool = Instance.new("Folder")
    self.threadPool.Name = `ThreadPool{self.id}`
    self.threadPool.Parent = environmentPath

    self.freeActor = Instance.new("BindableEvent")
    self.freeActor.Name = "FreeActor"
    self.freeActor.Parent = self.threadPool

    self._actors = {}
    self._freeActors = {}
    self._actorHighestId = 0
    for _ = 0, threads do
        local id = self._actorHighestId
        self._actorHighestId += 1
        local actor = CreateActor(self.threadPool, id)
        actor:SendMessage("Setup", module, sharedTable, id, self.freeActor)
        self._actors[id] = actor
        table.insert(self._freeActors, id)
    end

    self._taskQueue = {}
    self._joinThreads = {}

    self.freeActor.Event:Connect(function(id, params)
        table.insert(self._freeActors, id)
        task.spawn(callbackFunc, params)
        if #self._taskQueue == 0 and #self._freeActors == self._actorHighestId then
            for _, threads in self._joinThreads do
                task.spawn(threads)
            end
        end
    end)

    RunService.Heartbeat:Connect(function()
        if self._taskQueue[1] and self._freeActors[1] then
            local actorId = table.remove(self._freeActors, 1)
            local actor = self._actors[actorId]
            local taskConfig = table.remove(self._taskQueue, 1)
            actor:SendMessage("RunThread", taskConfig.params)
        end
    end)

    setmetatable(self, {
        __index = threadPool
    })
    return self
end

return setmetatable({
    CreateThreadPool = CreateThreadPool
}, {})