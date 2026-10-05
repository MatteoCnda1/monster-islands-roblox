--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local isServer = RunService:IsServer()

local remotesFolder: Folder

if isServer then
	remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end
else
	remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10) :: Folder
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end
end

local eventCache: { [string]: RemoteEvent } = {}
local functionCache: { [string]: RemoteFunction } = {}

local function getOrCreateRemoteEvent(name: string): RemoteEvent
	if eventCache[name] then
		return eventCache[name]
	end

	local remote = remotesFolder:FindFirstChild(name)
	if not remote then
		if isServer then
			local newRemote = Instance.new("RemoteEvent")
			newRemote.Name = name
			newRemote.Parent = remotesFolder
			eventCache[name] = newRemote
			return newRemote
		else
			remote = remotesFolder:WaitForChild(name, 10) :: RemoteEvent
		end
	end

	eventCache[name] = remote :: RemoteEvent
	return remote :: RemoteEvent
end

local function getOrCreateRemoteFunction(name: string): RemoteFunction
	if functionCache[name] then
		return functionCache[name]
	end

	local remote = remotesFolder:FindFirstChild(name)
	if not remote then
		if isServer then
			local newRemote = Instance.new("RemoteFunction")
			newRemote.Name = name
			newRemote.Parent = remotesFolder
			functionCache[name] = newRemote
			return newRemote
		else
			remote = remotesFolder:WaitForChild(name, 10) :: RemoteFunction
		end
	end

	functionCache[name] = remote :: RemoteFunction
	return remote :: RemoteFunction
end

local Network = {}

-- Server APIs
function Network.HandleFunction(name: string, handler: (player: Player, ...any) -> any)
	assert(isServer, "HandleFunction can only be called on the Server")
	local remote = getOrCreateRemoteFunction(name)
	remote.OnServerInvoke = handler
end

function Network.HandleEvent(name: string, handler: (player: Player, ...any) -> ())
	assert(isServer, "HandleEvent can only be called on the Server")
	local remote = getOrCreateRemoteEvent(name)
	remote.OnServerEvent:Connect(handler)
end

function Network.FireClient(name: string, player: Player, ...: any)
	assert(isServer, "FireClient can only be called on the Server")
	local remote = getOrCreateRemoteEvent(name)
	remote:FireClient(player, ...)
end

function Network.FireAllClients(name: string, ...: any)
	assert(isServer, "FireAllClients can only be called on the Server")
	local remote = getOrCreateRemoteEvent(name)
	remote:FireAllClients(...)
end

-- Client APIs
function Network.InvokeServer(name: string, ...: any): any
	assert(not isServer, "InvokeServer can only be called on the Client")
	local remote = getOrCreateRemoteFunction(name)
	return remote:InvokeServer(...)
end

function Network.FireServer(name: string, ...: any)
	assert(not isServer, "FireServer can only be called on the Client")
	local remote = getOrCreateRemoteEvent(name)
	remote:FireServer(...)
end

function Network.OnClientEvent(name: string, handler: (...any) -> ())
	assert(not isServer, "OnClientEvent can only be called on the Client")
	local remote = getOrCreateRemoteEvent(name)
	return remote.OnClientEvent:Connect(handler)
end

return Network
