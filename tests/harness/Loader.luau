--[[
	Loads Roblox-style ModuleScripts (which use `require(script.Parent.X)`) inside Lune by
	emulating the Rojo instance tree over the filesystem. Only for pure modules: anything that
	touches game services is out of scope for the offline runner.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Loader = {}

local cache: { [string]: any } = {}
-- Filesystem index built eagerly: Lune's fs calls yield, which is not allowed inside metamethods.
local files: { [string]: boolean } = {}
local dirs: { [string]: boolean } = {}
local indexed = false

local function indexTree(root: string)
	dirs[root] = true
	for _, entry in fs.readDir(root) do
		local path = root .. "/" .. entry
		if fs.isDir(path) then
			indexTree(path)
		elseif string.match(entry, "%.luau$") then
			files[path] = true
		end
	end
end

local function ensureIndexed()
	if not indexed then
		indexed = true
		indexTree("src")
	end
end
local loading: { [string]: boolean } = {}

local function stripSlash(path: string): string
	return (string.gsub(path, "/+$", ""))
end

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]+$") or "."
end

local function basename(path: string): string
	return string.match(path, "([^/]+)$") or path
end

local nodeMeta = {}

local function makeNode(path: string, isModuleFile: boolean): any
	-- `path` is a directory (folder or init module) or a .luau file.
	return setmetatable({ __path = path, __file = isModuleFile }, nodeMeta)
end

local function resolveChild(node: any, name: string): any?
	local base = node.__path
	if node.__file then
		-- A plain module file has no children.
		return nil
	end
	local dirPath = base .. "/" .. name
	if files[dirPath .. ".luau"] then
		return makeNode(dirPath .. ".luau", true)
	end
	if dirs[dirPath] then
		return makeNode(dirPath, false)
	end
	return nil
end

nodeMeta.__index = function(node: any, key: string)
	if key == "Parent" then
		local path = node.__path
		if node.__file then
			local parentDir = dirname(path)
			if basename(path) == "init.luau" then
				parentDir = dirname(parentDir)
			end
			return makeNode(parentDir, false)
		end
		return makeNode(dirname(path), false)
	elseif key == "Name" then
		return (string.gsub(basename(node.__path), "%.luau$", ""))
	elseif key == "FindFirstChild" then
		return function(self: any, name: string)
			return resolveChild(self, name)
		end
	elseif key == "WaitForChild" then
		return function(self: any, name: string)
			local child = resolveChild(self, name)
			assert(child, "WaitForChild: missing " .. name .. " in " .. self.__path)
			return child
		end
	end
	local child = resolveChild(node, key)
	if child == nil then
		error(`{key} is not a valid member of {node.__path}`, 2)
	end
	return child
end

local function sourcePathOf(node: any): string
	if node.__file then
		return node.__path
	end
	local initPath = node.__path .. "/init.luau"
	assert(files[initPath], "not a module: " .. node.__path)
	return initPath
end

local globals = {
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
	task = task,
	warn = function(...)
		print("[warn]", ...)
	end,
}

function Loader.requireNode(node: any): any
	local path = sourcePathOf(node)
	if cache[path] ~= nil then
		return cache[path]
	end
	assert(not loading[path], "circular require: " .. path)
	loading[path] = true
	local source = fs.readFile(path)
	local moduleNode = makeNode(path, true)
	if basename(path) == "init.luau" then
		moduleNode = makeNode(dirname(path), false)
	end
	local env = setmetatable({
		script = moduleNode,
		require = function(target: any)
			if type(target) == "table" and target.__path then
				return Loader.requireNode(target)
			end
			return require(target)
		end,
	}, { __index = function(_, key)
		local value = globals[key]
		if value ~= nil then
			return value
		end
		return (getfenv :: any)(0)[key]
	end })
	local chunk = luau.load(source, { debugName = path, environment = env })
	local result = chunk()
	loading[path] = nil
	cache[path] = if result == nil then false else result
	return result
end

-- Load a module by repository-relative path, e.g. "src/shared/Logic/SignalModel".
function Loader.load(relativePath: string): any
	ensureIndexed()
	local path = stripSlash(relativePath)
	if files[path .. ".luau"] then
		return Loader.requireNode(makeNode(path .. ".luau", true))
	end
	return Loader.requireNode(makeNode(path, false))
end

return Loader
