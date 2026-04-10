--!strict

export type CustomValue = string | number | boolean

export type PlayerData = {
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

type CollectedPlayerData = PlayerData & {
	_autoCollected: boolean,
}

local PlayerDataModule = {}

local customFieldsByPlayerId: { [number]: { [string]: CustomValue } } = {}

local function cloneCustomFields(fields: { [string]: CustomValue }?): { [string]: CustomValue }
	local copy: { [string]: CustomValue } = {}

	if not fields then
		return copy
	end

	for key, value in pairs(fields) do
		copy[key] = value
	end

	return copy
end

local function addText(parts: { string }, label: string, value: string?)
	if value and value ~= "" then
		table.insert(parts, string.format("%s: %s", label, value))
	end
end

function PlayerDataModule.SetCustom(playerId: number, key: string, value: CustomValue)
	if customFieldsByPlayerId[playerId] == nil then
		customFieldsByPlayerId[playerId] = {}
	end

	customFieldsByPlayerId[playerId][key] = value
end

function PlayerDataModule.GetCustom(playerId: number): { [string]: CustomValue }
	return cloneCustomFields(customFieldsByPlayerId[playerId])
end

function PlayerDataModule.Collect(player: Player, autoCollect: boolean): CollectedPlayerData
	local customFields = PlayerDataModule.GetCustom(player.UserId)

	if not autoCollect then
		return {
			playerId = player.UserId,
			displayName = "",
			username = "",
			accountAgeDays = 0,
			locale = "",
			isPremium = false,
			isVerified = false,
			teamName = nil,
			custom = customFields,
			_autoCollected = false,
		}
	end

	local isVerified = false
	local okVerified, verified = pcall(function()
		return player:IsVerified()
	end)
	if okVerified and verified == true then
		isVerified = true
	end

	return {
		playerId = player.UserId,
		displayName = player.DisplayName,
		username = player.Name,
		accountAgeDays = player.AccountAge,
		locale = player.LocaleId,
		isPremium = player.MembershipType == Enum.MembershipType.Premium,
		isVerified = isVerified,
		teamName = if player.Team then player.Team.Name else nil,
		custom = customFields,
		_autoCollected = true,
	}
end

function PlayerDataModule.Serialize(playerData: CollectedPlayerData, defaultDescription: string?, override: string?): string
	if override and override ~= "" then
		return override
	end

	local parts: { string } = {}

	if playerData._autoCollected then
		if playerData.displayName ~= "" then
			local intro = playerData.displayName
			if playerData.username ~= "" and playerData.username ~= playerData.displayName then
				intro ..= string.format(" (username: %s)", playerData.username)
			end
			table.insert(parts, intro)
		elseif playerData.username ~= "" then
			table.insert(parts, playerData.username)
		end

		if playerData.accountAgeDays > 0 then
			table.insert(parts, string.format("account age: %d days", playerData.accountAgeDays))
		end

		addText(parts, "locale", playerData.locale)
		table.insert(parts, "premium: " .. tostring(playerData.isPremium))
		table.insert(parts, "verified: " .. tostring(playerData.isVerified))
		addText(parts, "team", playerData.teamName)
	else
		table.insert(parts, string.format("playerId: %d", playerData.playerId))
	end

	for key, value in pairs(playerData.custom) do
		table.insert(parts, string.format("%s: %s", key, tostring(value)))
	end

	local serialized = table.concat(parts, ", ")
	if defaultDescription and defaultDescription ~= "" then
		if serialized ~= "" then
			return defaultDescription .. " " .. serialized
		end
		return defaultDescription
	end

	return serialized
end

function PlayerDataModule.ToPlayerDataPayload(playerData: CollectedPlayerData): { [string]: CustomValue }
	local payload: { [string]: CustomValue } = {
		playerId = playerData.playerId,
	}

	if playerData._autoCollected then
		if playerData.displayName ~= "" then
			payload.displayName = playerData.displayName
		end
		if playerData.username ~= "" then
			payload.username = playerData.username
		end
		if playerData.accountAgeDays > 0 then
			payload.accountAgeDays = playerData.accountAgeDays
		end
		if playerData.locale ~= "" then
			payload.locale = playerData.locale
		end
		payload.isPremium = playerData.isPremium
		payload.isVerified = playerData.isVerified
		if playerData.teamName and playerData.teamName ~= "" then
			payload.teamName = playerData.teamName
		end
	end

	for key, value in pairs(playerData.custom) do
		payload[key] = value
	end

	return payload
end

return PlayerDataModule
