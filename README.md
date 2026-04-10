# Journale AI Roblox SDK

![Version](https://img.shields.io/badge/version-1.0.0-blue)

Server-side Luau SDK for adding Journale AI dialogue to Roblox experiences.

## Prerequisites

- A Journale AI account with a project and API key: <https://journale.ai/dashboard>
- Roblox Studio
- `HttpService` enabled in `Experience Settings > Security > Allow HTTP Requests`

## Installation

### Option A: GitHub `.rbxm`

1. Download `JournaleSDK.rbxm` from the latest GitHub release.
2. In Roblox Studio, go to `File > Insert from File`.
3. Move the imported `JournaleSDK` module into `ServerScriptService`.

Build the release artifact locally with Rojo:

```bash
rojo build default.project.json -o JournaleSDK.rbxm
```

### Option B: Creator Store (in progress)

1. Open the Toolbox in Roblox Studio.
2. Search for `Journale AI SDK`.
3. Insert the model and move `JournaleSDK` into `ServerScriptService`.

### Option C: Wally

Add the package to your `wally.toml`:

```toml
[server-dependencies]
JournaleSDK = "journale/journale-sdk@^1.0"
```

Then run:

```bash
wally install
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

- Repository quickstart: [`specs/003-roblox-sdk/quickstart.md`](../../specs/003-roblox-sdk/quickstart.md)
- Website SDK docs: <https://journale.ai/docs/sdks>
