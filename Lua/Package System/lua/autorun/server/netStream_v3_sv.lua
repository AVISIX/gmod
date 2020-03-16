// Config // 
local timeout = 10
local sendDelay = 0.25
local streamingPort = "V7EKDIJOGR3XLQCXIE2R"

local streamQueue = {}
util.AddNetworkString(streamingPort)

/*
 _   _      _                     
| | | |    | |                   
| |_| | ___| |_ __   ___ _ __ ___ 
|  _  |/ _ \ | '_ \ / _ \ '__/ __|
| | | |  __/ | |_) |  __/ |  \__ \
\_| |_/\___|_| .__/ \___|_|  |___/
             | |                  
             |_|                  */

local function keyForIndex(data, index)
	local result = nil 
	local i = 1
	for k, v in pairs(data) do 
		if(i == index)then
			result = k
			break 
		end
		i=i+1
	end 
	return result 
end

local function newPackage(data, index, size)
	if(data == nil)then return {} end
	local result = {}	
	local keys = table.GetKeys(data) 
	if(keys == nil)then return {} end
	local limit = index + size - 1 
	limit = math.min(limit, table.Count(data))
	for i = index, limit, 1 do
		local k = keyForIndex(data, i)
		result[k] = data[k]
	end
	return result 
end  
 
local function wrapPkg(pkg, index, target, total, code)
	local result = {}
	result["header"] = {["id"] = code, ["index"] = index, ["target"] = target, ["total"] = total}
	result["data"] = pkg 
	return result 
end

local function mergeValues(data)
	if(data == nil)then return {} end

	local result = {}

	for k, v in pairs(data) do
		for k2, v2 in pairs(v) do
			if(isnumber(k2))then
				table.insert(result, v2)
			else
				if(result[k2] == nil)then
					result[k2] = v2
				else
					print("Error trying to merge packages, a key with the value: " ..  k2 .. " already exists in the given context")
				end
			end
		end
	end

	return result
end

/*  
___  ___      _       
|  \/  |     (_)      
| .  . | __ _ _ _ __  
| |\/| |/ _` | | '_ \ 
| |  | | (_| | | | | |
\_|  |_/\__,_|_|_| |_| */
  
function streamReceive(id, onSuccess, sorted, onFailure)
	sorted = sorted or false 
	onFailure = onFailure or function() end

	local collection = {}

	local t_id = ("__" .. id .. "_timeout_timer")

	net.Receive(streamingPort, function(len, ply)
		local pkg = net.ReadTable()

		local header = pkg["header"]

		local uid = header["id"]

		if(uid == id)then		
			if(timer.Exists(t_id) == false)then // Start timeout when pkg for this ID arrives
				timer.Create(t_id, timeout, 0, function()
					onFailure(ply, collection)
					timer.Remove(t_id)
					collection = {}
				end)
			end

			local data = pkg["data"]

			table.insert(collection, data)

			local supposedCount = header["total"]

			if(table.Count(collection) >= supposedCount)then
				timer.Remove(t_id)
				onSuccess(ply, mergeValues(collection)) // Add result table
				collection = {}
			end
		end
	end)
end

function streamCatchPackage(id, callback)
	net.Receive(streamingPort, function(len, ply)
		local pkg = net.ReadTable()

		local header = pkg["header"]
		local uid = header["id"]

		if(uid == id)then		
			local data = pkg["data"]
			callback(ply, data)
		end
	end)
end

function streamSend(identifier, target, data, size, onFailure)
	if data == nil then
		onFailure("Nil Data")
		return false
	end

	if IsValid(target) == false then
		onFailure("Nil Target")
		return false
	end

	local status, err = pcall(function()
		local constructor = coroutine.create(function()
			local dpkgc = math.ceil(#data / size)
			for i = 1, dpkgc, 1 do
				local calc = math.max((i - 1) * size, 1) + math.min(i - 1, 1)
				local pkg = newPackage(data, calc, size)
				local final = wrapPkg(pkg, i, target, dpkgc, identifier)
				table.insert(streamQueue, final)
			end
		end)

		coroutine.resume(constructor)
	end)

	if(status == false)then
		onFailure(err)
		return false 
	end

	return true  
end

  /* 
  _   _             _          
 | | | |           | |       
 | |_| | ___   ___ | | _____ 
 |  _  |/ _ \ / _ \| |/ / __| 
 | | | | (_) | (_) |   <\__ \ 
 \_| |_/\___/ \___/|_|\_\___/*/

local pIndex = 1
timer.Create("__netStream_Queue_Executioner_", sendDelay, 0, function()
	pcall(function()
		local queuer = coroutine.create(function()
			if(#streamQueue > 0)then

				if(pIndex > #streamQueue)then
					pIndex = 1  
				end

				local key = keyForIndex(streamQueue, pIndex)
				local v = streamQueue[key]
				local tar = v["header"]["target"]

				if(IsValid(tar) == false) then // If the Player isnt valid, just remove the entry and skip to the next
					table.remove(streamQueue, pIndex) 
				else
					local stripped = v
					stripped["header"]["target"] = nil // Remove target, we dont need it anymore.

					net.Start(streamingPort)
					net.WriteTable(stripped)
					net.Send(tar)

					table.remove(streamQueue, pIndex) 
				end

				pIndex = pIndex + 1
			end
		end)

		coroutine.resume(queuer)
	end)
end) // No think hook, to avoid lag

