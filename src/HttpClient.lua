--!strict

local HttpService = game:GetService("HttpService")

export type JsonValue = string | number | boolean

export type RequestConfig = {
	secretName: string?,
	apiKey: string?,
	maxRetries: number,
	baseBackoffSeconds: number,
	debug: boolean,
}

export type HttpResponse = {
	success: boolean,
	statusCode: number,
	body: { [string]: any }?,
	rawBody: string?,
	error: string?,
	errorCode: string?,
}

local HttpClient = {}

local API_BASE_URL = "https://api.journale.ai"
local DEFAULT_PATH = "/v1/chat"

local function debugLog(enabled: boolean, ...)
	if enabled then
		print("[Journale]", ...)
	end
end

local function safeDecode(rawBody: string?): { [string]: any }?
	if not rawBody or rawBody == "" then
		return nil
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(rawBody)
	end)

	if ok and type(decoded) == "table" then
		return decoded :: { [string]: any }
	end

	return nil
end

local function isHttpEnabled(): boolean
	local ok, enabled = pcall(function()
		return HttpService.HttpEnabled
	end)

	if ok then
		return enabled
	end

	return true
end

local function resolveAuthorizationHeader(config: RequestConfig): (any, string?, string?)
	if config.secretName and config.secretName ~= "" then
		local okSecret, secret = pcall(function()
			return HttpService:GetSecret(config.secretName :: string)
		end)

		if okSecret and secret then
			local okPrefixed, prefixed = pcall(function()
				return secret:AddPrefix("Bearer ")
			end)

			if okPrefixed then
				return prefixed
			end
		else
			debugLog(config.debug, "Secrets Store unavailable, falling back to config.apiKey if provided")
		end
	end

	if config.apiKey and config.apiKey ~= "" then
		return "Bearer " .. config.apiKey
	end

	return nil, "[Journale] No API key configured. Set config.secretName or config.apiKey", "NETWORK_ERROR"
end

local function collectZodFieldErrors(node: any, path: string, collected: { string })
	if type(node) ~= "table" then
		return
	end

	local errors = node._errors
	if type(errors) == "table" then
		for _, message in ipairs(errors) do
			if type(message) == "string" and message ~= "" then
				if path == "" then
					table.insert(collected, message)
				else
					table.insert(collected, string.format("%s: %s", path, message))
				end
			end
		end
	end

	for key, value in pairs(node) do
		if key ~= "_errors" and type(value) == "table" then
			local childPath = if path == "" then tostring(key) else path .. "." .. tostring(key)
			collectZodFieldErrors(value, childPath, collected)
		end
	end
end

local function stringifyDetails(details: any): string?
	if type(details) == "string" then
		return if details ~= "" then details else nil
	end

	if type(details) ~= "table" then
		return nil
	end

	local collected: { string } = {}
	collectZodFieldErrors(details, "", collected)
	if #collected > 0 then
		return table.concat(collected, "; ")
	end

	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(details)
	end)
	if ok and type(encoded) == "string" and encoded ~= "" and encoded ~= "{}" and encoded ~= "[]" then
		return encoded
	end

	return nil
end

local function extractServerMessage(statusCode: number, body: { [string]: any }?, rawBody: string?): string?
	if body then
		local detailsMessage = stringifyDetails(body.details)
		local errorMessage = body.error

		if detailsMessage and type(errorMessage) == "string" and errorMessage ~= "" then
			return string.format("%s (%s)", errorMessage, detailsMessage)
		end
		if detailsMessage then
			return detailsMessage
		end
		if type(errorMessage) == "string" and errorMessage ~= "" then
			return errorMessage
		end
	end

	if rawBody and rawBody ~= "" and not string.find(string.lower(rawBody), "<html", 1, true) then
		return rawBody
	end

	if statusCode == 400 then
		return "Invalid request."
	end

	return nil
end

local function mapError(statusCode: number, body: { [string]: any }?, rawBody: string?): (string, string)
	local serverMessage = extractServerMessage(statusCode, body, rawBody)

	if statusCode == 402 then
		return "INSUFFICIENT_CREDITS", "[Journale] Not enough credits. Top up at journale.ai/dashboard."
	elseif statusCode == 429 then
		return "RATE_LIMITED", "[Journale] Journale API rate limit reached. Please try again shortly."
	elseif statusCode == 400 then
		if serverMessage then
			return "BAD_REQUEST", "[Journale] Invalid request: " .. serverMessage
		end
		return "BAD_REQUEST", "[Journale] Invalid request. Check your payload and try again."
	elseif statusCode == 500 or statusCode == 502 then
		return "SERVER_ERROR", "[Journale] Journale API error. Try again later."
	end

	if serverMessage then
		return "NETWORK_ERROR", "[Journale] Request failed: " .. serverMessage
	end

	return "NETWORK_ERROR", "[Journale] Could not reach Journale API. Check HttpService is enabled."
end

function HttpClient.Post(config: RequestConfig, payload: { [string]: any }, path: string?): HttpResponse
	local requestPath = path or DEFAULT_PATH
	local requestUrl = API_BASE_URL .. requestPath
	if not isHttpEnabled() then
		return {
			success = false,
			statusCode = 0,
			error = "[Journale] HttpService is disabled. Enable Allow HTTP Requests in Experience Settings > Security.",
			errorCode = "NETWORK_ERROR",
		}
	end

	local authorizationHeader, authError, authErrorCode = resolveAuthorizationHeader(config)
	if not authorizationHeader then
		return {
			success = false,
			statusCode = 0,
			error = authError,
			errorCode = authErrorCode,
		}
	end

	local encodedBody = HttpService:JSONEncode(payload)
	local attempt = 0

	while true do
		attempt += 1
		debugLog(config.debug, string.format("POST %s (attempt %d)", requestUrl, attempt))

		local ok, responseOrError = pcall(function()
			return HttpService:RequestAsync({
				Url = requestUrl,
				Method = "POST",
				Headers = {
					["Content-Type"] = "application/json",
					["Authorization"] = authorizationHeader,
				},
				Body = encodedBody,
			})
		end)

		if not ok then
			local rawError = tostring(responseOrError)
			if string.find(string.lower(rawError), "http requests are not enabled", 1, true) then
				return {
					success = false,
					statusCode = 0,
					error = "[Journale] HttpService is disabled. Enable Allow HTTP Requests in Experience Settings > Security.",
					errorCode = "NETWORK_ERROR",
				}
			end

			return {
				success = false,
				statusCode = 0,
				error = "[Journale] Could not reach Journale API. Check HttpService is enabled.",
				errorCode = "NETWORK_ERROR",
				rawBody = rawError,
			}
		end

		local response = responseOrError
		local statusCode = response.StatusCode
		local rawBody = response.Body
		local decodedBody = safeDecode(rawBody)

		debugLog(config.debug, string.format("Received HTTP %d", statusCode))
		if config.debug and (not response.Success or statusCode >= 300) then
			debugLog(config.debug, "Error response body:", rawBody)
		end

		if response.Success and statusCode >= 200 and statusCode < 300 then
			return {
				success = true,
				statusCode = statusCode,
				body = decodedBody,
				rawBody = rawBody,
			}
		end

		if statusCode == 429 and attempt <= config.maxRetries then
			local delaySeconds = config.baseBackoffSeconds * (2 ^ (attempt - 1))
			debugLog(config.debug, string.format("Rate limited. Retrying in %.2fs", delaySeconds))
			task.wait(delaySeconds)
		else
			local errorCode, errorMessage = mapError(statusCode, decodedBody, rawBody)
			return {
				success = false,
				statusCode = statusCode,
				body = decodedBody,
				rawBody = rawBody,
				error = errorMessage,
				errorCode = errorCode,
			}
		end
	end
end

return HttpClient
