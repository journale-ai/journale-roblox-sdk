--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local chatEvent = ReplicatedStorage:WaitForChild("JournaleChatEvent") :: RemoteEvent

local PROXIMITY_DISTANCE = 12

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "JournaleChatUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local rootFrame = Instance.new("Frame")
rootFrame.Name = "ChatRoot"
rootFrame.Size = UDim2.fromOffset(360, 300)
rootFrame.Position = UDim2.new(0.5, -180, 1, -340)
rootFrame.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
rootFrame.BorderSizePixel = 0
rootFrame.Visible = false
rootFrame.Parent = screenGui

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -24, 0, 28)
titleLabel.Position = UDim2.fromOffset(12, 12)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 18
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "Journale NPC Chat"
titleLabel.Parent = rootFrame

local messagesFrame = Instance.new("ScrollingFrame")
messagesFrame.Size = UDim2.new(1, -24, 1, -112)
messagesFrame.Position = UDim2.fromOffset(12, 48)
messagesFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 22)
messagesFrame.BorderSizePixel = 0
messagesFrame.CanvasSize = UDim2.new()
messagesFrame.ScrollBarThickness = 6
messagesFrame.Parent = rootFrame

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.Parent = messagesFrame

local typingLabel = Instance.new("TextLabel")
typingLabel.Size = UDim2.new(1, -24, 0, 18)
typingLabel.Position = UDim2.new(0, 12, 1, -56)
typingLabel.BackgroundTransparency = 1
typingLabel.Font = Enum.Font.Gotham
typingLabel.TextSize = 14
typingLabel.TextColor3 = Color3.fromRGB(148, 163, 184)
typingLabel.TextXAlignment = Enum.TextXAlignment.Left
typingLabel.Text = ""
typingLabel.Parent = rootFrame

local inputBox = Instance.new("TextBox")
inputBox.Size = UDim2.new(1, -108, 0, 36)
inputBox.Position = UDim2.new(0, 12, 1, -40)
inputBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
inputBox.BorderSizePixel = 0
inputBox.ClearTextOnFocus = false
inputBox.Font = Enum.Font.Gotham
inputBox.PlaceholderText = "Type your message..."
inputBox.Text = ""
inputBox.TextSize = 14
inputBox.Parent = rootFrame

local sendButton = Instance.new("TextButton")
sendButton.Size = UDim2.fromOffset(84, 36)
sendButton.Position = UDim2.new(1, -96, 1, -40)
sendButton.BackgroundColor3 = Color3.fromRGB(99, 102, 241)
sendButton.BorderSizePixel = 0
sendButton.Font = Enum.Font.GothamBold
sendButton.Text = "Send"
sendButton.TextColor3 = Color3.fromRGB(255, 255, 255)
sendButton.TextSize = 14
sendButton.Parent = rootFrame

local activeCharacterId: string? = nil
local waitingForReply = false

local function updateCanvas()
	messagesFrame.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 12)
	messagesFrame.CanvasPosition = Vector2.new(0, math.max(0, layout.AbsoluteContentSize.Y))
end

layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)

local function addMessage(author: string, text: string)
	local label = Instance.new("TextLabel")
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, -12, 0, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextWrapped = true
	label.TextSize = 14
	label.TextColor3 = Color3.fromRGB(230, 232, 236)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = string.format("%s: %s", author, text)
	label.Parent = messagesFrame

	updateCanvas()
end

local function findNearestNpcCharacterId(): string?
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return nil
	end

	local nearestId: string? = nil
	local nearestDistance = PROXIMITY_DISTANCE

	for _, tagged in ipairs(CollectionService:GetTagged("JournaleNPC")) do
		if tagged:IsA("BasePart") then
			local distance = (tagged.Position - rootPart.Position).Magnitude
			if distance <= nearestDistance then
				nearestDistance = distance
				nearestId = tagged:GetAttribute("CharacterId") or tagged.Name
			end
		end
	end

	return nearestId
end

local function refreshNpcProximity()
	activeCharacterId = findNearestNpcCharacterId()
	rootFrame.Visible = activeCharacterId ~= nil
	if activeCharacterId then
		titleLabel.Text = "Talking to " .. activeCharacterId
	elseif not waitingForReply then
		typingLabel.Text = ""
	end
end

local function sendCurrentMessage()
	if waitingForReply or not activeCharacterId then
		return
	end

	local message = string.gsub(inputBox.Text, "^%s+", "")
	message = string.gsub(message, "%s+$", "")
	if message == "" then
		return
	end

	waitingForReply = true
	typingLabel.Text = "NPC is typing..."
	addMessage("You", message)
	chatEvent:FireServer(activeCharacterId, message)
	inputBox.Text = ""
end

sendButton.Activated:Connect(sendCurrentMessage)
inputBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		sendCurrentMessage()
	end
end)

chatEvent.OnClientEvent:Connect(function(payload)
	waitingForReply = false
	typingLabel.Text = ""

	if payload.success then
		addMessage(payload.characterId or "NPC", payload.reply or "")
	else
		addMessage("System", payload.error or "The NPC could not respond.")
	end
end)

RunService.RenderStepped:Connect(refreshNpcProximity)
