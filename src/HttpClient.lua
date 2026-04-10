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

local API_URL = "https://api.journale.ai/chat"

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

local function extractServerMessage(statusCode: number, body: { [string]: any }?, rawBody: string?): string?
	if body then
		local details = body.details
		if type(details) == "string" and details ~= "" then
			return details
		end

		local errorMessage = body.error
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

function HttpClient.Post(config: RequestConfig, payload: { [string]: any }): HttpResponse
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
		debugLog(config.debug, string.format("POST %s (attempt %d)", API_URL, attempt))

		local ok, responseOrError = pcall(function()
			return HttpService:RequestAsync({
				Url = API_URL,
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
