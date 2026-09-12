-- Lazily creates/finds RemoteEvents and RemoteFunctions under
-- ReplicatedStorage.Remotes so server and client never need to agree on
-- where instances are pre-placed in Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}
local remotesFolder

local function getFolder()
	if remotesFolder then
		return remotesFolder
	end
	if RunService:IsServer() then
		remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
		if not remotesFolder then
			remotesFolder = Instance.new("Folder")
			remotesFolder.Name = "Remotes"
			remotesFolder.Parent = ReplicatedStorage
		end
	else
		remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	end
	return remotesFolder
end

function Net.GetEvent(name)
	local folder = getFolder()
	local inst = folder:FindFirstChild(name)
	if inst then
		return inst
	end
	if RunService:IsServer() then
		inst = Instance.new("RemoteEvent")
		inst.Name = name
		inst.Parent = folder
		return inst
	end
	return folder:WaitForChild(name)
end

function Net.GetFunction(name)
	local folder = getFolder()
	local inst = folder:FindFirstChild(name)
	if inst then
		return inst
	end
	if RunService:IsServer() then
		inst = Instance.new("RemoteFunction")
		inst.Name = name
		inst.Parent = folder
		return inst
	end
	return folder:WaitForChild(name)
end

return Net
