local GuiService = game:GetService("GuiService")
local LocalizationService = game:GetService("LocalizationService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UplinkedInspect = require(script.Parent.UplinkedInspect)

local REMOTE_EVENT_NAME = "UplinkedEvent"

local MESSAGE_TYPE_TO_LEVEL = {
	[Enum.MessageType.MessageWarning] = "Warn",
	[Enum.MessageType.MessageError] = "Error",
}

local Uplinked = {}

local remoteEvent = ReplicatedStorage:WaitForChild(REMOTE_EVENT_NAME, 5)
local options = nil
local sessionStarted = false
local sessionActive = false

local function getInputs()
	local inputs = {}
	if UserInputService.TouchEnabled then table.insert(inputs, "Touchscreen") end
	if UserInputService.KeyboardEnabled then table.insert(inputs, "Keyboard") end
	if UserInputService.GamepadEnabled then table.insert(inputs, "Gamepad") end
	if UserInputService.VREnabled then table.insert(inputs, "VR") end
	if GuiService:IsTenFootInterface() then table.insert(inputs, "Console") end
	return inputs
end

local function getPlayerInfo()
	local camera = workspace.CurrentCamera
	local viewportSize = camera and camera.ViewportSize or Vector2.new(0, 0)
	local guiInset = GuiService:GetGuiInset()

	local qualityLevel = UserSettings().GameSettings.SavedQualityLevel
	local qualityStr = qualityLevel == Enum.SavedQualitySetting.Automatic
		and "Auto"
		or tostring(qualityLevel.Value)

	return {
		Locale = LocalizationService.RobloxLocaleId,
		Resolution = string.format("%dx%d", math.round(viewportSize.X), math.round(viewportSize.Y)),
		GraphicsQuality = qualityStr,
		SafeArea = string.format("%d,%d", math.round(guiInset.X), math.round(guiInset.Y)),
		Inputs = getInputs(),
	}
end

local function sendPlayerInfo()
	if not sessionActive or not remoteEvent then return end
	remoteEvent:FireServer({
		Type = "PlayerInfo",
		Data = getPlayerInfo(),
	})
end

local function createButton()
	local GuiService = game:GetService("GuiService")
	local guiInset = GuiService:GetGuiInset()

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "UplinkedGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.Parent = Players.LocalPlayer.PlayerGui

	local button = Instance.new("TextButton")
	button.Name = "UplinkedButton"
	button.Size = UDim2.new(0, 36, 0, 36)
	button.Position = UDim2.new(0, 10, 0, 10)
	button.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	button.BackgroundTransparency = 0.2
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = true
	button.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = button

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = button

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 20, 0, 20)
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://84210556018239"
	icon.ImageColor3 = Color3.fromRGB(200, 200, 200)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.LayoutOrder = 1
	icon.Parent = button

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(0, 0, 1, 0)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextColor3 = Color3.fromRGB(200, 200, 200)
	label.TextSize = 14
	label.Font = Enum.Font.GothamMedium
	label.Visible = false
	label.LayoutOrder = 2
	label.Parent = button

	button.AutomaticSize = Enum.AutomaticSize.X

	return button, icon, label
end

local function startLogging()
	LogService.MessageOut:Connect(function(message, messageType)
		local level = MESSAGE_TYPE_TO_LEVEL[messageType] or "Info"
		remoteEvent:FireServer({
			Type = "Log",
			Data = {
				Message = message,
				Level = level,
				Timestamp = os.time(),
			},
		})
	end)
end

function Uplinked.RequestSession()
	if not remoteEvent then
		warn("Uplinked: RemoteEvent not found, cannot request session.")
		return
	end
	if not sessionStarted then
		sessionStarted = true
		startLogging()
	end
	if options and options.OnConnecting then
		options.OnConnecting()
	end
	remoteEvent:FireServer({ Type = "RequestSession" })
end

function Uplinked.Start(opts)
	options = opts or {}
	local showUI = options.ShowDefaultUI ~= false

	if not remoteEvent then
		warn("Uplinked: RemoteEvent not found, client logging disabled.")
		return
	end

	local button, icon, label = nil, nil, nil
	if showUI then
		button, icon, label = createButton()
	end

	-- Resend player info when input device availability changes
	UserInputService.GamepadConnected:Connect(sendPlayerInfo)
	UserInputService.GamepadDisconnected:Connect(sendPlayerInfo)

	remoteEvent.OnClientEvent:Connect(function(payload)
		if payload.Type == "SessionCode" then
			sessionActive = true
			sendPlayerInfo()
			if button then
				icon.ImageColor3 = Color3.fromHex("#37FF7D")
				label.Text = payload.Code
				label.Visible = true
			end
			if options.OnSessionCode then
				options.OnSessionCode(payload.Code)
			end
		elseif payload.Type == "SessionEnded" then
			sessionActive = false
			if button then
				icon.ImageColor3 = Color3.fromRGB(200, 200, 200)
				label.Text = ""
				label.Visible = false
			end
			if options.OnSessionEnded then
				options.OnSessionEnded()
			end
		elseif payload.Type == "SessionError" then
			sessionActive = false
			if button then
				icon.ImageColor3 = Color3.fromRGB(200, 200, 200)
				label.Text = ""
				label.Visible = false
			end
			if options.OnError then
				options.OnError(payload.Message)
			end
		elseif payload.Type == "InspectRequest" then
			local result = UplinkedInspect.HandleRequest(payload.Data)
			remoteEvent:FireServer({
				Type = "InspectResult",
				Data = result,
			})
		end
	end)

	if button then
		button.MouseButton1Click:Connect(function()
			if sessionActive then
				remoteEvent:FireServer({ Type = "EndSession" })
			else
				Uplinked.RequestSession()
			end
		end)
	end
end

return Uplinked
