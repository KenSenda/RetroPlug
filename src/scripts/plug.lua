require("component")
require("constants")
require("components.ButtonHandler")
require("components.GlobalButtonHandler")
local inspect = require("inspect")

local MAX_INSTANCES = 4

Active = nil
local _activeIdx = 0
local _instances = {}
local _keyState = {}

Action = {
	Lsdj = {
		Copy = function() print("Lsdj.Copy") end,
		Paste = function() print("Lsdj.Paste") end,
		DownTenRows = function() print("Lsdj.DownTenRows") end,
		UpTenRows = function() print("Lsdj.UpTenRows") end,
	},

}

local _globalComponents = {}

local _componentFactory = {
	instance = {},
	global = {}
}

local function componentInputRoute(target, key, down)
	local handled = false
	for _, v in ipairs(_globalComponents) do
		local found = v[target]
		if found ~= nil then
			found(v, key, down)
			handled = true
		end
	end

	if Active ~= nil then
		for _, v in ipairs(Active.components) do
			local found = v[target]
			if found ~= nil then
				found(v, key, down)
				handled = true
			end
		end
	end

	return handled
end

local function findInstancePlugins(rom)
	local components = {}
	for _, v in ipairs(_componentFactory.instance) do
		local d = v.__desc
		if d.romName == nil or rom.name:find(d.romName) ~= nil then
			print("Attaching component " .. d.name)
			table.insert(components, v.new())
		end
	end

	return components
end

local function initComponents(instance)
	local romName = instance.model:getRomName()
	for _, component in ipairs(instance.components) do
		if component.onRomLoaded ~= nil then component:onRomLoaded(romName) end
	end
end

function _loadComponent(name)
	local component = require("components/" .. name)
	if component ~= nil then
		print("Registered component: " .. component.__desc.name)
		if component.__desc.global == true then
			table.insert(_componentFactory.global, component)
		else
			table.insert(_componentFactory.instance, component)
		end
	else
		print("Failed to load " .. name .. ": Script does not return a component")
	end
end

function _init()
	for _, v in ipairs(_componentFactory.global) do
		table.insert(_globalComponents, v.new())
	end

	for i = 1, MAX_INSTANCES, 1 do
		local plug = _model:getPlug(i - 1)
		if plug ~= nil then
			table.insert(_instances, {
				model = plug,
				components = findInstancePlugins(plug)
			})

			if i == _model:activeInstanceIdx() + 1 then
				_activeIdx = i
				Active = _instances[i]
			end
		end
	end

	for _, instance in ipairs(_instances) do
		initComponents(instance)
	end
end

local function addInstance(emulatorType)
	if #_instances < MAX_INSTANCES then
		local instance = {
			model = _model:addInstance(emulatorType),
			components = {}
		}

		table.insert(_instances, instance)

		if #_instances == 1 then
			Active = _instances[1]
		end

		return instance
	end
end

function _addInstance(emulatorType)
	local instance = addInstance(emulatorType)
	if instance ~= nil then
		return instance.model
	end
end

function _removeInstance(index)
	if index + 1 == _activeIdx then
		_activeIdx = 0
		Active = nil
	end

	table.remove(_instances, index + 1)
	_model:removeInstance(index)
end

function _duplicateInstance(idx)
	if #_instances < MAX_INSTANCES then
		local source = _instances[idx + 1]

		local instance = {
			model = _model:duplicateInstance(idx),
			components = {}  -- TODO: Duplicate components
		}

		return instance.model
	end
end

function _loadRom(idx, path)
	local file = _model:fileManager():loadFile(path)
	if file == nil then
		return
	end

	local romData = {
		name = file.data:slice(0x0134, 15):toString(),
		path = path
	}

	local instance = _instances[idx + 1]
	if instance == nil then
		print("Failed to load " .. path .. ": Instance " .. idx .. " does not exist")
		return
	end

	instance.components = findInstancePlugins(romData)

	for _, v in ipairs(instance.components) do
		if v.onBeforeRomLoad ~= nil then
			v.onBeforeRomLoad(romData)
		end
	end

	if _model:loadRom(idx, path) == false then
		return
	end

	initComponents(instance)
end

function _setActive(idx)
	_activeIdx = idx + 1
	Active = _instances[_activeIdx]
	_model:setActiveInstance(idx)
end

function _frame(delta)

end

function _onKey(key, down)
	local vk = key.vk
	if down == true then
		if _keyState[vk] ~= nil then return end
		_keyState[vk] = true
	else
		_keyState[vk] = nil
	end

	return componentInputRoute("onKey", vk, down)
end

function _onPadButton(button, down)
	componentInputRoute("onPadButton", button, down)
end

function _onMidi(note, down)
	--pluginInputRoute("onMidi", note, down)
end

Action.RetroPlug = {
	NextInstance = function(down)
		if down == true then
			local nextIdx = _activeIdx
			if nextIdx == #_instances then
				nextIdx = 0
			end

			_setActive(nextIdx)
		end
	end
}