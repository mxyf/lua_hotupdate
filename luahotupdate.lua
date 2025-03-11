local HU = {}

function HU.FailNotify(...)
	if HU.NotifyFunc then HU.NotifyFunc(...) end
end
function HU.DebugNofity(...)
	if HU.DebugNofityFunc then HU.DebugNofityFunc(...) end
end

local function rawpairs(t)
    return next, t, nil
end

local function GetWorkingDir()
	if HU.WorkingDir == nil then
	    local p = io.popen("echo %cd%")
	    if p then
	        HU.WorkingDir = p:read("*l").."\\"
	        p:close()
	    end
	end
	return HU.WorkingDir
end

local function Normalize(path)
	path = path:gsub("/","\\") 
	if path:find(":") == nil then
		path = GetWorkingDir()..path 
	end
	local pathLen = #path 
	if path:sub(pathLen, pathLen) == "\\" then
		 path = path:sub(1, pathLen - 1)
	end
	 
    local parts = { }
    for w in path:gmatch("[^\\]+") do
        if     w == ".." and #parts ~=0 then table.remove(parts)
        elseif w ~= "."  then table.insert(parts, w)
        end
    end
    return table.concat(parts, "\\")
end

local prefixes = {"you", "lua", "file", "dir"}
local function remove_prefix(luapath)
	for _, prefix in ipairs(prefixes) do
		if luapath:sub(1, #prefix + 1) == prefix .. "." then
			return luapath:sub(#prefix + 2)
		end
	end
	return luapath
end

function HU.TryAddToFileMap(SysPath)
	local fileName = string.match(SysPath, "[^/]*$")
	SysPath = SysPath .. '.lua'
	if HU.FileMap[fileName] == nil then
		HU.FileMap[fileName] = {}
	end
	local rootpath = Normalize(HU.rootPath)

	local luapath = string.sub(SysPath, #rootpath+2, #SysPath-4)
	luapath = string.gsub(luapath, "/", ".")
	luapath = remove_prefix(luapath)
	table.insert(HU.FileMap[fileName], {SysPath = SysPath, LuaPath = luapath})
end

HU.BlackList = {
    ["Class"] = true,
    -- 无法热重载的模块路径
}

HU.SpecialData = {
	["common.event_const"] = true,
}

HU.MeGlobal = {
    --自己项目的全局变量
}

function HU.InitFakeTable()
	local meta = {}
	HU.Meta = meta
	local function FakeT() return setmetatable({}, meta) end
	local function EmptyFunc() end
	local function pairs() return EmptyFunc end  
	local function setmetatable(t, metaT)
		HU.MetaMap[t] = metaT 
		return t
	end
	local function getmetatable(t, metaT)
		return setmetatable({}, t)
	end
	function meta.__index(t, k)
		if k == "setmetatable" then
			return setmetatable
		elseif k == "pairs" or k == "ipairs" then
			return pairs
		elseif k == "next" then
			return EmptyFunc
		elseif k == "require" then
			return require
		elseif HU.MeGlobal[k] then
			return HU.MeGlobal[k]
		else
			local FakeTable = FakeT()
			rawset(t, k, FakeTable)
			return FakeTable 
		end
	end
	function meta.__newindex(t, k, v) rawset(t, k, v) end
	function meta.__call() return FakeT(), FakeT(), FakeT() end
	function meta.__add() return meta.__call() end
	function meta.__sub() return meta.__call() end
	function meta.__mul() return meta.__call() end
	function meta.__div() return meta.__call() end
	function meta.__mod() return meta.__call() end
	function meta.__pow() return meta.__call() end
	function meta.__unm() return meta.__call() end
	function meta.__concat() return meta.__call() end
	function meta.__eq() return meta.__call() end
	function meta.__lt() return meta.__call() end
	function meta.__le() return meta.__call() end
	function meta.__len() return meta.__call() end
	return FakeT
end

function HU.InitProtection()
	HU.Protection = {}
	HU.Protection[setmetatable] = true
	HU.Protection[pairs] = true
	HU.Protection[ipairs] = true
	HU.Protection[next] = true
	HU.Protection[require] = true
	HU.Protection[HU] = true
	HU.Protection[HU.Meta] = true
	HU.Protection[math] = true
	HU.Protection[string] = true
	HU.Protection[table] = true
end

function HU.AddFileFromHUList()
	package.loaded[HU.UpdateListFile] = nil
	local FileList = require (HU.UpdateListFile)
	HU.ALL = false
	HU.HUMap = {}
	for _, file in pairs(FileList) do
		local fileName = string.match(file, "[^/]*$") 
		if HU.FileMap[fileName] then
			for _, path in pairs(HU.FileMap[fileName]) do
				HU.HUMap[path.LuaPath] = path.SysPath  	
			end
		else
			HU.TryAddToFileMap(file)
			for _, path in pairs(HU.FileMap[fileName]) do
				HU.HUMap[path.LuaPath] = path.SysPath  	
			end
		end
	end
end

function HU.ErrorHandle(e)
	HU.FailNotify("HotUpdate Error\n"..tostring(e))
	HU.ErrorHappen = true
end

function HU.BuildNewCode(SysPath, LuaPath)
	if HU.BlackList[LuaPath] then
		HU.NotifyFunc(LuaPath..'脚本不允许更新，维持原状！')
		return false
	end
	io.input(SysPath)
	local NewCode = io.read("*all")
	if HU.ALL and HU.OldCode[SysPath] == nil then
		HU.OldCode[SysPath] = NewCode
		return
	end
	if HU.OldCode[SysPath] == NewCode then
		io.input():close()
		return false
	end
	HU.DebugNofity(SysPath)
	io.input(SysPath)  
	local chunk = "--[["..LuaPath.."]] "
	chunk = chunk..NewCode	
	io.input():close()
	local NewFunction = loadstring(chunk, LuaPath:gsub("%.", "/"))
	if not NewFunction then 
  		HU.FailNotify(SysPath.." has syntax error.")  	
  		collectgarbage("collect")
  		return false
	else
		HU.FakeENV = HU.FakeT()
		HU.MetaMap = {}
		HU.RequireMap = {}
		setfenv(NewFunction, HU.FakeENV)
		local NewObject
		HU.ErrorHappen = false
		xpcall(function () NewObject = NewFunction() end, HU.ErrorHandle)
		if not HU.ErrorHappen then 
			HU.OldCode[SysPath] = NewCode
			HU.NotifyFunc(LuaPath..'脚本更新！')
			return true, NewObject
		else
	  		collectgarbage("collect")
			return false
		end
	end
end


function HU.Travel_G()
	local visited = {}
	visited[HU] = true
	local function f(t)
		if (type(t) ~= "function" and type(t) ~= "table") or visited[t] or HU.Protection[t] then return end
		visited[t] = true
		if type(t) == "function" then
		  	for i = 1, math.huge do
				local name, value = debug.getupvalue(t, i)
				if not name then break end
				if type(value) == "function" then
					if HU.ChangedFuncListFastMap[value] then
						for _, index in ipairs(HU.ChangedFuncListFastMap[value]) do
							local funcs = HU.ChangedFuncList[index]
							debug.setupvalue(t, i, funcs[2])
						end
					end
				end
				f(value)
			end
		elseif type(t) == "table" then
			f(debug.getmetatable(t))
			local changeIndexs = nil
			for k,v in rawpairs(t) do
				f(k); 
				f(v);
				if type(v) == "function" then
					if HU.ChangedFuncListFastMap[v] then
						for _, index in ipairs(HU.ChangedFuncListFastMap[v]) do
							local funcs = HU.ChangedFuncList[index]
							t[k] = funcs[2] 
						end
					end
				end
				if type(k) == "function" then
					if HU.ChangedFuncListFastMap[k] then
						for _, index in ipairs(HU.ChangedFuncListFastMap[k]) do
							changeIndexs = changeIndexs or {}
							changeIndexs[#changeIndexs+1] = index 
						end
					end
				end
			end
			if changeIndexs ~= nil then
				for _, index in ipairs(changeIndexs) do
					local funcs = HU.ChangedFuncList[index]
					t[funcs[2]] = t[funcs[1]] 
					t[funcs[1]] = nil
				end
			end
		end
	end
	
	f(_G)
	local registryTable = debug.getregistry()
	f(registryTable)
	f(HU.MeGlobal)
	for _, funcs in ipairs(HU.ChangedFuncList) do
		if funcs[3] == "HUDebug" then funcs[4]:HUDebug() end
	end
end

function HU.ReplaceOld(OldObject, NewObject, LuaPath, From, Deepth)
	if type(OldObject) == type(NewObject) then
		if type(NewObject) == "table" then
			HU.UpdateAllFunction(OldObject, NewObject, LuaPath, From, "") 
		elseif type(NewObject) == "function" then
			HU.UpdateOneFunction(OldObject, NewObject, LuaPath, nil, From, "")
		end
	end
end

function HU.HotUpdateData(LuaPath, replace_old)
	local OldTable = package.loaded[LuaPath]
	if not OldTable then
		HU.NotifyFunc(LuaPath..'这个data没加载过，不做处理！')
		return
	end
	package.loaded[LuaPath] = nil
	local NewTable = require(LuaPath)

	if replace_old then
		for k, _ in pairs(OldTable) do
			OldTable[k] = nil
		end
		for k, v in pairs(NewTable) do 
			OldTable[k] = v
		end
		package.loaded[LuaPath] = OldTable
	end
	log.error("update data ",LuaPath)
end

function HU.check_is_data(str)
	if string.find(str, "^data%.") ~= nil or string.find(str, "^lua_shared%.") ~= nil then
		return true, false
	end
	if HU.SpecialData[str] then
		return true, true
	end
	return false, false
end

function HU.HotUpdateCode(LuaPath, SysPath)
	local is_data, is_need_replace_old = HU.check_is_data(LuaPath)
	if is_data then
		HU.HotUpdateData(LuaPath, is_need_replace_old)
		return
	end
	local OldObject = package.loaded[LuaPath]
	local component_reload_flag = false
	if OldObject ~= nil then
		HU.VisitedSig = {}
		HU.ChangedFuncList = {}
		HU.ChangedFuncListFastMap = {}
		--[[
			这里可能需要对class做一些处理，比如说有一些类的设定不容许重复初始化
		]]

		local Success, NewObject = HU.BuildNewCode(SysPath, LuaPath)
		if Success then
			HU.ReplaceOld(OldObject, NewObject, LuaPath, "Main", "")
			for LuaPath, NewObject in rawpairs(HU.RequireMap) do
				local OldObject = package.loaded[LuaPath]
				HU.ReplaceOld(OldObject, NewObject, LuaPath, "Main_require", "")
			end
			setmetatable(HU.FakeENV, nil)
			HU.UpdateAllFunction(HU.ENV, HU.FakeENV, " ENV ", "Main", "")
			if #HU.ChangedFuncList > 0 then
				HU.Travel_G()
			end
			collectgarbage("collect")
		end
	else
		HU.NotifyFunc(LuaPath..'脚本没加载过，不做处理！')
	end
	if component_reload_flag then
		--
	end
end

function HU.ResetENV(object, name, From, Deepth)
	local visited = {}
	local function f(object, name)
		if not object or visited[object] then return end
		visited[object] = true
		if type(object) == "function" then
			HU.DebugNofity(Deepth.."HU.ResetENV", name, "  from:"..From)
			xpcall(function () setfenv(object, HU.ENV) end, HU.FailNotify)
		elseif type(object) == "table" then
			HU.DebugNofity(Deepth.."HU.ResetENV", name, "  from:"..From)
			for k, v in rawpairs(object) do
				f(k, tostring(k).."__key", " HU.ResetENV ", Deepth.."    " )
				f(v, tostring(k), " HU.ResetENV ", Deepth.."    ")
			end
		end
	end
	f(object, name)
end

function HU.UpdateUpvalue(OldFunction, NewFunction, Name, From, Deepth)
	HU.DebugNofity(Deepth.."HU.UpdateUpvalue", Name, "  from:"..From)
	local OldUpvalueMap = {}
	local OldExistName = {}
	for i = 1, math.huge do
		local name, value = debug.getupvalue(OldFunction, i)
		if not name then break end
		OldUpvalueMap[name] = value
		OldExistName[name] = true
	end
	for i = 1, math.huge do
		local name, value = debug.getupvalue(NewFunction, i)
		if not name then break end
		if OldExistName[name] then
			local OldValue = OldUpvalueMap[name]
			if type(OldValue) ~= type(value) then
				debug.setupvalue(NewFunction, i, OldValue)
			elseif type(OldValue) == "function" then
				HU.UpdateOneFunction(OldValue, value, name, nil, "HU.UpdateUpvalue", Deepth.."    ")
			elseif type(OldValue) == "table" then
				HU.UpdateAllFunction(OldValue, value, name, "HU.UpdateUpvalue", Deepth.."    ")
				debug.setupvalue(NewFunction, i, OldValue)
			else
				debug.setupvalue(NewFunction, i, OldValue)
			end
		else
			HU.ResetENV(value, name, "HU.UpdateUpvalue", Deepth.."    ")
		end
	end
end 


function HU.UpdateOneFunction(OldObject, NewObject, FuncName, OldTable, From, Deepth)
	if HU.Protection[OldObject] or HU.Protection[NewObject] then return end
	if OldObject == NewObject then return end
	local signature = tostring(OldObject)..tostring(NewObject)
	if HU.VisitedSig[signature] then return end
	HU.VisitedSig[signature] = true
	HU.DebugNofity(Deepth.."HU.UpdateOneFunction "..FuncName.."  from:"..From)
	if pcall(debug.setfenv, NewObject, getfenv(OldObject)) then
		HU.UpdateUpvalue(OldObject, NewObject, FuncName, "HU.UpdateOneFunction", Deepth.."    ")
		HU.ChangedFuncList[#HU.ChangedFuncList + 1] = {OldObject, NewObject, FuncName, OldTable}
		if not HU.ChangedFuncListFastMap[OldObject] then
			HU.ChangedFuncListFastMap[OldObject] = {}
		end
		table.insert(HU.ChangedFuncListFastMap[OldObject], #HU.ChangedFuncList)
	end
end

function HU.UpdateAllFunction(OldTable, NewTable, Name, From, Deepth)
	if HU.Protection[OldTable] or HU.Protection[NewTable] then return end
	if OldTable == NewTable then return end
	local signature = tostring(OldTable)..tostring(NewTable)
	if HU.VisitedSig[signature] then return end
	HU.VisitedSig[signature] = true
	HU.DebugNofity(Deepth.."HU.UpdateAllFunction "..Name.."  from:"..From)
	for ElementName, Element in rawpairs(NewTable) do
		local OldElement = OldTable[ElementName]
		if type(Element) == type(OldElement) then
			if type(Element) == "function" then
				HU.UpdateOneFunction(OldElement, Element, ElementName, OldTable, "HU.UpdateAllFunction", Deepth.."    ")
			elseif type(Element) == "table" then
				HU.UpdateAllFunction(OldElement, Element, ElementName, "HU.UpdateAllFunction", Deepth.."    ")
			end
		elseif OldElement == nil and type(Element) == "function" then
			if pcall(setfenv, Element, HU.ENV) then
				OldTable[ElementName] = Element
			end
		end
	end
	local OldMeta = debug.getmetatable(OldTable)  
	local NewMeta = HU.MetaMap[NewTable]
	if --[[一些require之后返回的内容有元表的]] true then
		NewMeta = debug.getmetatable(NewTable) 
	end
	if type(OldMeta) == "table" and type(NewMeta) == "table" then
		HU.UpdateAllFunction(OldMeta, NewMeta, Name.."'s Meta", "HU.UpdateAllFunction", Deepth.."    ")
	end
end

function HU.Init(UpdateListFile, rootPath, FailNotify, ENV)
	HU.UpdateListFile = UpdateListFile
	HU.HUMap = {}
	HU.FileMap = {}
	HU.NotifyFunc = FailNotify
	HU.OldCode = {}
	HU.ChangedFuncList = {}
	HU.ChangedFuncListFastMap = {}
	HU.VisitedSig = {}
	HU.FakeENV = nil
	HU.ENV = ENV or _G
	HU.LuaPathToSysPath = {}
	HU.rootPath = rootPath
	HU.FakeT = HU.InitFakeTable()
	HU.InitProtection()
	HU.ALL = false
end

function HU.Update()
	--local start_time = os.clock()
	HU.AddFileFromHUList()
	for LuaPath, SysPath in pairs(HU.HUMap) do
		HU.HotUpdateCode(LuaPath, SysPath)
	end
	--local end_time = os.clock()
	--log.error("update耗时", end_time - start_time)
end

return HU
