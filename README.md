# Journale AI Roblox SDK

![Version](https://img.shields.io/badge/version-1.0.0-blue)

Server-side Luau SDK for adding Journale AI dialogue to Roblox experiences.

**GitHub**: <https://github.com/journale-ai/journale-roblox-sdk>

## Prerequisites

- A Journale AI account with a project and API key: <https://journale.ai/dashboard>
- Roblox Studio
- `HttpService` enabled in `Experience Settings > Security > Allow HTTP Requests`

## Installation

1. Download `JournaleSDK.rbxm` from the [latest GitHub release](https://github.com/journale-ai/journale-roblox-sdk/releases).
2. In Roblox Studio, go to `File > Insert from File` and select the `.rbxm`.
3. Move the imported `JournaleSDK` module into `ServerScriptService`.

Maintainers can rebuild the release artifact locally with Rojo:

```bash
rojo build default.project.json -o JournaleSDK.rbxm
```

## Setup

### 1. Store your API key

For published experiences, store your API key in Roblox Secrets as `JournaleAPIKey` and allow the `api.journale.ai` domain.

For local Studio testing, you can pass `apiKey` directly to `Init()`. Do not commit real keys to source control.

### 2. Create a server Script

```lua
local Journale = require(game.ServerScriptService.JournaleSDK)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

Journale.Init({
    projectId = "YOUR_PROJECT_ID",
    secretName = "JournaleAPIKey",
    -- apiKey = "sk_...", -- Studio testing only
})

local chatEvent = Instance.new("RemoteEvent")
chatEvent.Name = "JournaleChatEvent"
chatEvent.Parent = ReplicatedStorage

chatEvent.OnServerEvent:Connect(function(player, characterId, message)
    if type(characterId) ~= "string" or type(message) ~= "string" then
        return
    end

    -- `characterId` is a local string you choose (e.g., "shopkeeper_01").
    -- It scopes conversation history per player + character on this server.
    -- It is not sent to the Journale API — the character's personality comes
    -- from `characterDescription` below.
    local result = Journale.ChatToAi(player, characterId, message, {
        characterDescription = "A friendly village shopkeeper",
    })

    if result.success then
        chatEvent:FireClient(player, {
            success = true,
            characterId = characterId,
            reply = result.reply,
        })
    else
        chatEvent:FireClient(player, {
            success = false,
            characterId = characterId,
            error = result.error,
        })
    end
end)
```

### 3. Create a client LocalScript

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local chatEvent = ReplicatedStorage:WaitForChild("JournaleChatEvent")

local function sendMessage(characterId, message)
    chatEvent:FireServer(characterId, message)
end

chatEvent.OnClientEvent:Connect(function(payload)
    if payload.success then
        print(payload.characterId .. " says: " .. payload.reply)
    else
        warn(payload.error)
    end
end)

sendMessage("shopkeeper_01", "What do you sell?")
```

## Player Context

The SDK automatically collects Roblox player context and includes it in both `player_data` and the serialized `playerDescription`.

Add your own fields with `SetPlayerData`:

```lua
Journale.SetPlayerData(player, "faction", "Knights of Dawn")
Journale.SetPlayerData(player, "level", 42)
Journale.SetPlayerData(player, "currentQuest", "Retrieve the Lost Sword")
```

## Character IDs

`characterId` is a **local** developer-chosen string. Use it to tell the SDK which on-server conversation a message belongs to — e.g., `"shopkeeper_01"`, `"guard_captain"`, `"old_merchant"`. You don't need to register these anywhere; pick whatever strings make sense for your game. The SDK keys conversation history by `{playerId}_{characterId}` so each player has an independent memory per character. Personality is defined entirely by the `characterDescription` option you pass to `ChatToAi`.

## Public API

```lua
Journale.Init(config)
Journale.ChatToAi(player, characterId, message, options?)
Journale.SetPlayerData(player, key, value)
Journale.GetPlayerData(player)
Journale.ClearHistory(player, characterId?)
```

## Template

Reference scripts live in:

- `template/server/JournaleServer.server.lua`
- `template/client/JournaleChatUI.client.lua`

They demonstrate RemoteEvent validation, per-player cooldowns, NPC proximity checks, a basic chat UI, and custom player data wiring.

## Full Documentation

- GitHub repository: <https://github.com/journale-ai/journale-roblox-sdk>
- Website SDK docs: <https://journale.ai/docs/sdks>
