--!strict

local HttpService = game:GetService("HttpService")

local HttpClient = require(script:WaitForChild("HttpClient"))
local History = require(script:WaitForChild("History"))
local PlayerData = require(script:WaitForChild("PlayerData"))

export type CustomValue = string | number | boolean

export type JournaleConfig = {
	projectId: string,
	secretName: string?,
	apiKey: string?,
	defaultPlayerDescription: string?,
	maxMessageLength: number?,
	maxContextSize: number?,
	maxRetries: number?,
	baseBackoffSeconds: number?,
	autoCollectPlayerData: boolean?,
	debug: boolean?,
}

export type ChatOptions = {
	characterDescription: string?,
	playerDescriptionOverride: string?,
	customPlayerData: { [string]: CustomValue }?,
}

export type ChatUsage = {
	prompt_tokens: number,
	completion_tokens: number,
	total_tokens: number,
}

export type ChatResult = {
	success: boolean,
	reply: string?,
	error: string?,
	errorCode: string?,
	usage: ChatUsage?,
}

export type PlayerDataRecord = {
	playerId: number,
	displayName: string,
	username: string,
	accountAgeDays: number,
	locale: string,
	isPremium: boolean,
	isVerified: boolean,
	teamName: string?,
	custom: { [string]: CustomValue },
}

type InternalPlayerDataRecord = PlayerDataRecord & {
	_autoCollected: boolean,
}

type ResolvedConfig = {
	projectId: string,
	secretName: string?,
	apiKey: string?,
	defaultPlayerDescription: string?,
	maxMessageLength: number,
	maxContextSize: number,
	maxRetries: number,
	baseBackoffSeconds: number,
	autoCollectPlayerData: boolean,
	debug: boolean,
}

type Module = {
	VERSION: string,
	Init: (config: JournaleConfig) -> (),
	ChatToAi: (player: Player, characterId: string, message: string, options: ChatOptions?) -> ChatResult,
	ChatWithCharacter: (player: Player, characterId: string, message: string, options: ChatOptions?) -> ChatResult,
	SetPlayerData: (player: Player, key: string, value: CustomValue) -> (),
	GetPlayerData: (player: Player) -> PlayerDataRecord,
	ClearHistory: (player: Player, characterId: string?) -> (),
}

local Journale: Module = {} :: Module

local VERSION = "1.1.0"
local initialized = false
local activeConfig: ResolvedConfig? = nil

local function warnLog(...)
	warn("[Journale]", ...)
end

local function debugLog(...)
	if activeConfig and activeConfig.debug then
		print("[Journale]", ...)
	end
end

local function fail(errorCode: string, message: string): ChatResult
	return {
		success = false,
		error = message,
		errorCode = errorCode,
	}
end

local function conversationKey(player: Player, characterId: string): string
	return tostring(player.UserId) .. "_" .. characterId
end

local function validateConfig(config: JournaleConfig): ResolvedConfig
	if type(config.projectId) ~= "string" or config.projectId == "" then
		error("[Journale] projectId is required")
	end

	if (not config.secretName or config.secretName == "") and (not config.apiKey or config.apiKey == "") then
		error("[Journale] No API key configured. Set config.secretName or config.apiKey")
	end

	local maxMessageLength = config.maxMessageLength or 500
	local maxContextSize = config.maxContextSize or 4000
	local maxRetries = config.maxRetries or 3
	local baseBackoffSeconds = config.baseBackoffSeconds or 1

	if maxMessageLength <= 0 then
		error("[Journale] maxMessageLength must be greater than 0")
	end
	if maxContextSize <= 0 then
		error("[Journale] maxContextSize must be greater than 0")
	end
	if maxRetries < 0 then
		error("[Journale] maxRetries must be greater than or equal to 0")
	end
	if baseBackoffSeconds <= 0 then
		error("[Journale] baseBackoffSeconds must be greater than 0")
	end

	return {
		projectId = config.projectId,
		secretName = config.secretName,
		apiKey = config.apiKey,
		defaultPlayerDescription = config.defaultPlayerDescription,
		maxMessageLength = maxMessageLength,
		maxContextSize = maxContextSize,
		maxRetries = maxRetries,
		baseBackoffSeconds = baseBackoffSeconds,
		autoCollectPlayerData = if config.autoCollectPlayerData == nil then true else config.autoCollectPlayerData,
		debug = if config.debug == nil then false else config.debug,
	}
end

local function mergeCustomFields(baseFields: { [string]: CustomValue }, extraFields: { [string]: CustomValue }?): { [string]: CustomValue }
	local merged: { [string]: CustomValue } = {}

	for key, value in pairs(baseFields) do
		merged[key] = value
	end

	if extraFields then
		for key, value in pairs(extraFields) do
			merged[key] = value
		end
	end

	return merged
end

local function enrichPlayerData(playerData: InternalPlayerDataRecord, extraFields: { [string]: CustomValue }?): InternalPlayerDataRecord
	local mergedCustom = mergeCustomFields(playerData.custom, extraFields)
	local enriched: InternalPlayerDataRecord = {
		playerId = playerData.playerId,
		displayName = playerData.displayName,
		username = playerData.username,
		accountAgeDays = playerData.accountAgeDays,
		locale = playerData.locale,
		isPremium = playerData.isPremium,
		isVerified = playerData.isVerified,
		teamName = playerData.teamName,
		custom = mergedCustom,
		_autoCollected = playerData._autoCollected,
	}

	return enriched
end

function Journale.Init(config: JournaleConfig)
	if initialized then
		warnLog("Init() called more than once. Existing configuration will be reused.")
		return
	end

	activeConfig = validateConfig(config)
	initialized = true

	History.SetDebug(activeConfig.debug)

	local httpEnabledOk, httpEnabled = pcall(function()
		return HttpService.HttpEnabled
	end)
	if httpEnabledOk and not httpEnabled then
		warnLog("HttpService is disabled. Enable Allow HTTP Requests in Experience Settings > Security.")
	end
end

local function sendChat(
	player: Player,
	characterId: string,
	message: string,
	options: ChatOptions?,
	path: string,
	sendCharacterID: boolean,
	sendStoredCharacterId: boolean,
	callerName: string
): ChatResult
	if not initialized or not activeConfig then
		return fail("NOT_INITIALIZED", string.format("[Journale] Init() must be called before %s().", callerName))
	end

	if type(characterId) ~= "string" or characterId == "" then
		return fail("BAD_REQUEST", "[Journale] characterId must be a non-empty string.")
	end

	if type(message) ~= "string" or message == "" then
		return fail("BAD_REQUEST", "[Journale] message must be a non-empty string.")
	end

	if string.len(message) > activeConfig.maxMessageLength then
		return fail(
			"MESSAGE_TOO_LONG",
			string.format("[Journale] Message exceeds maxMessageLength (%d characters).", activeConfig.maxMessageLength)
		)
	end

	local collectedPlayerData = PlayerData.Collect(player, activeConfig.autoCollectPlayerData) :: InternalPlayerDataRecord
	local playerData = enrichPlayerData(collectedPlayerData, if options then options.customPlayerData else nil)
	local playerDescription = PlayerData.Serialize(
		playerData,
		activeConfig.defaultPlayerDescription,
		if options then options.playerDescriptionOverride else nil
	)
	local reservedChars = string.len(message)
		+ string.len(playerDescription)
		+ string.len(if options and options.characterDescription then options.characterDescription else "")
	local historyKey = conversationKey(player, characterId)
	local context = History.BuildContext(historyKey, activeConfig.maxContextSize, reservedChars)
	local payload: { [string]: any } = {
		message = message,
		context = context,
		characterDescription = if sendStoredCharacterId then nil else if options then options.characterDescription else nil,
		playerDescription = if playerDescription ~= "" then playerDescription else nil,
		external_id = tostring(player.UserId),
		identifier_type = "roblox",
		player_data = PlayerData.ToPlayerDataPayload(playerData),
	}

	if sendStoredCharacterId then
		payload.characterId = characterId
	elseif sendCharacterID then
		payload.characterID = characterId
	end

	if activeConfig.debug then
		debugLog("Chat payload:", HttpService:JSONEncode(payload))
	end

	local httpResult = HttpClient.Post({
		secretName = activeConfig.secretName,
		apiKey = activeConfig.apiKey,
		maxRetries = activeConfig.maxRetries,
		baseBackoffSeconds = activeConfig.baseBackoffSeconds,
		debug = activeConfig.debug,
	}, payload, path)

	if not httpResult.success then
		return fail(httpResult.errorCode or "NETWORK_ERROR", httpResult.error or "[Journale] Chat request failed.")
	end

	local responseBody = httpResult.body
	local reply = if responseBody then responseBody.reply else nil
	if type(reply) ~= "string" or reply == "" then
		return fail("SERVER_ERROR", "[Journale] Journale API returned an invalid response.")
	end

	History.Add(historyKey, "user", message)
	History.Add(historyKey, "assistant", reply)

	local usageTable = if responseBody then responseBody.usage else nil
	local usage: ChatUsage? = nil
	if type(usageTable) == "table" then
		usage = {
			prompt_tokens = if type(usageTable.prompt_tokens) == "number" then usageTable.prompt_tokens else 0,
			completion_tokens = if type(usageTable.completion_tokens) == "number" then usageTable.completion_tokens else 0,
			total_tokens = if type(usageTable.total_tokens) == "number" then usageTable.total_tokens else 0,
		}
	end

	return {
		success = true,
		reply = reply,
		usage = usage,
	}
end

function Journale.ChatToAi(player: Player, characterId: string, message: string, options: ChatOptions?): ChatResult
	return sendChat(player, characterId, message, options, "/v1/chat", false, false, "ChatToAi")
end

function Journale.ChatWithCharacter(player: Player, characterId: string, message: string, options: ChatOptions?): ChatResult
	return sendChat(player, characterId, message, options, "/v1/chat/character", false, true, "ChatWithCharacter")
end

function Journale.SetPlayerData(player: Player, key: string, value: CustomValue)
	if type(key) ~= "string" or key == "" then
		error("[Journale] key must be a non-empty string")
	end

	PlayerData.SetCustom(player.UserId, key, value)
end

function Journale.GetPlayerData(player: Player): PlayerDataRecord
	local autoCollect = if activeConfig then activeConfig.autoCollectPlayerData else true
	local collected = PlayerData.Collect(player, autoCollect) :: InternalPlayerDataRecord

	return {
		playerId = collected.playerId,
		displayName = collected.displayName,
		username = collected.username,
		accountAgeDays = collected.accountAgeDays,
		locale = collected.locale,
		isPremium = collected.isPremium,
		isVerified = collected.isVerified,
		teamName = collected.teamName,
		custom = collected.custom,
	}
end

function Journale.ClearHistory(player: Player, characterId: string?)
	if characterId and characterId ~= "" then
		History.Clear(conversationKey(player, characterId))
		return
	end

	History.ClearAllForPlayer(player.UserId)
end

Journale.VERSION = VERSION

return Journale
