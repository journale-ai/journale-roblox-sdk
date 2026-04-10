--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Journale = require(ServerScriptService:WaitForChild("JournaleSDK"))

local REMOTE_EVENT_NAME = "JournaleChatEvent"
local MAX_MESSAGE_LENGTH = 500
local CHAT_COOLDOWN_SECONDS = 1.5

local chatEvent = ReplicatedStorage:FindFirstChild(REMOTE_EVENT_NAME) :: RemoteEvent?
if not chatEvent then
	chatEvent = Instance.new("RemoteEvent")
	chatEvent.Name = REMOTE_EVENT_NAME
	chatEvent.Parent = ReplicatedStorage
end

local lastRequestAtByPlayerId: { [number]: number } = {}
local characterDescriptions = {
	shopkeeper_01 = "A friendly village shopkeeper who knows every rumor in town.",
	guard_01 = "A stern castle guard who only respects brave adventurers.",
}

Journale.Init({
	projectId = "YOUR_PROJECT_ID",
	secretName = "JournaleAPIKey",
	-- apiKey = "sk_...", -- Studio testing only
	debug = true,
})

Players.PlayerAdded:Connect(function(player)
	-- Example custom data that persists for the lifetime of this server.
	Journale.SetPlayerData(player, "faction", "Knights of Dawn")
	Journale.SetPlayerData(player, "level", 12)
	Journale.SetPlayerData(player, "hasCompletedTutorial", true)
end)

local function validateRequest(player: Player, characterId: any, message: any): (boolean, string?)
	if type(characterId) ~= "string" or characterId == "" then
		return false, "[Journale] characterId must be a non-empty string."
	end

	if type(message) ~= "string" then
		return false, "[Journale] message must be a string."
	end

	if message == "" then
		return false, "[Journale] message cannot be empty."
	end

	if string.len(message) > MAX_MESSAGE_LENGTH then
		return false, string.format("[Journale] message cannot exceed %d characters.", MAX_MESSAGE_LENGTH)
	end

	local now = os.clock()
	local lastRequestAt = lastRequestAtByPlayerId[player.UserId] or 0
	if now - lastRequestAt < CHAT_COOLDOWN_SECONDS then
		return false, "[Journale] Please wait before sending another message."
	end

	lastRequestAtByPlayerId[player.UserId] = now
	return true, nil
end

chatEvent.OnServerEvent:Connect(function(player, characterId, message)
	local isValid, validationError = validateRequest(player, characterId, message)
	if not isValid then
		chatEvent:FireClient(player, {
			success = false,
			characterId = characterId,
			error = validationError,
		})
		return
	end

	local result = Journale.ChatToAi(player, characterId, message, {
		characterDescription = characterDescriptions[characterId],
		customPlayerData = {
			serverName = game.Name,
		},
	})

	-- The player could have left while the HTTP request was in flight.
	if Players:GetPlayerByUserId(player.UserId) == nil then
		return
	end

	if result.success then
		chatEvent:FireClient(player, {
			success = true,
			characterId = characterId,
			reply = result.reply,
			usage = result.usage,
		})
	else
		chatEvent:FireClient(player, {
			success = false,
			characterId = characterId,
			error = result.error,
			errorCode = result.errorCode,
		})
	end
end)
