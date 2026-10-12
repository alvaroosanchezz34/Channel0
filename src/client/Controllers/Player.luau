--!strict
--[[
	Local player feel: flashlight toggle (F / touch), sprint (Shift / touch) and a subtle head bob
	when walking (off with "reduce motion"). The server owns the actual flashlight light and walk
	speed; this only sends the intent.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local HUD = require(script.Parent.HUD)
local Net = require(script.Parent.Net)
local Store = require(script.Parent.Store)

local Player = {}

local player = Players.LocalPlayer
local flashlightOn = false
local sprinting = false
local bobTime = 0

local function canAct(): boolean
	local me = Store.me()
	return Net.state(Net.Attr.Session) == "Running" and me ~= nil and me.status == "Active"
end

local function setFlashlight(on: boolean)
	flashlightOn = on
	Net.send("Flashlight", on)
end

local function setSprint(on: boolean)
	if sprinting == on then
		return
	end
	sprinting = on
	Net.send("Sprint", on)
end

local function toggleFlashlight()
	if canAct() then
		setFlashlight(not flashlightOn)
	end
end

local function update(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local running = canAct()
	if not running and sprinting then
		setSprint(false)
	end
	local moving = humanoid.MoveDirection.Magnitude > 0.1 and humanoid.FloorMaterial ~= Enum.Material.Air
	if Store.settings.reduceMotion or not running or not moving then
		bobTime = 0
		humanoid.CameraOffset = humanoid.CameraOffset:Lerp(Vector3.zero, math.min(1, dt * 8))
		return
	end
	local speed = humanoid.WalkSpeed
	bobTime += dt * speed * 0.55
	local amount = if sprinting then 0.12 else 0.06
	local target = Vector3.new(math.cos(bobTime * 0.5) * amount * 0.6, math.abs(math.sin(bobTime)) * amount, 0)
	humanoid.CameraOffset = humanoid.CameraOffset:Lerp(target, math.min(1, dt * 10))
end

function Player.init()
	ContextActionService:BindAction("CH0Flashlight", function(_, state)
		if state == Enum.UserInputState.Begin then
			toggleFlashlight()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
	ContextActionService:BindAction("CH0Sprint", function(_, state)
		if state == Enum.UserInputState.Begin then
			setSprint(canAct())
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			setSprint(false)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	HUD.onFlashlight = toggleFlashlight
	HUD.onSprint = function(on: boolean)
		setSprint(on and canAct())
	end
	-- The server recreates the light with each character; keep it in sync after respawns.
	player.CharacterAdded:Connect(function()
		sprinting = false
		task.delay(1, function()
			if flashlightOn then
				Net.send("Flashlight", true)
			end
		end)
	end)
	Store.Changed:Connect(function(kind, payload)
		if kind == "session" and payload == "Lobby" then
			flashlightOn = false
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return Player
