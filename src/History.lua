--!strict

export type ConversationRole = "user" | "assistant"

export type ConversationEntry = {
	role: ConversationRole,
	content: string,
}

local History = {}

local historyByKey: { [string]: { ConversationEntry } } = {}
local debugEnabled = false

local function serializeEntry(entry: ConversationEntry): string
	local speaker = if entry.role == "user" then "User" else "Assistant"
	return string.format("%s: %s\n", speaker, entry.content)
end

local function serializedLength(entries: { ConversationEntry }): number
	local total = 0

	for _, entry in ipairs(entries) do
		total += string.len(serializeEntry(entry))
	end

	return total
end

local function debugLog(...)
	if debugEnabled then
		print("[Journale]", ...)
	end
end

function History.SetDebug(enabled: boolean)
	debugEnabled = enabled
end

function History.Add(key: string, role: ConversationRole, content: string)
	if historyByKey[key] == nil then
		historyByKey[key] = {}
	end

	table.insert(historyByKey[key], {
		role = role,
		content = content,
	})
end

function History.BuildContext(key: string, maxContextSize: number, reservedChars: number?): string
	local entries = historyByKey[key]
	if not entries or #entries == 0 then
		return ""
	end

	local reserved = reservedChars or 0
	local beforeChars = serializedLength(entries)
	local currentChars = beforeChars
	local prunedEntries = 0
	local minimumEntries = math.min(#entries, 2)

	while #entries > minimumEntries and currentChars + reserved > maxContextSize do
		local removed = table.remove(entries, 1)
		if removed then
			currentChars -= string.len(serializeEntry(removed))
			prunedEntries += 1
		end
	end

	local contextParts = table.create(#entries)
	for index, entry in ipairs(entries) do
		contextParts[index] = serializeEntry(entry)
	end

	local context = table.concat(contextParts)
	local afterChars = string.len(context)

	if prunedEntries > 0 then
		debugLog(
			string.format(
				"History pruned for %s: before=%d after=%d reserved=%d removed=%d",
				key,
				beforeChars,
				afterChars,
				reserved,
				prunedEntries
			)
		)
	else
		debugLog(string.format("History size for %s: context=%d reserved=%d", key, afterChars, reserved))
	end

	debugLog("Context payload:\n" .. context)

	return context
end

function History.Clear(key: string)
	historyByKey[key] = nil
end

function History.ClearAllForPlayer(playerId: number)
	local prefix = tostring(playerId) .. "_"

	for key in pairs(historyByKey) do
		if string.sub(key, 1, string.len(prefix)) == prefix then
			historyByKey[key] = nil
		end
	end
end

return History
