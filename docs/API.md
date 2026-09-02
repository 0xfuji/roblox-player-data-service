# API

The service is intended to be required from **server scripts only**.

## `DataService.Init()`

Starts loading, autosaving, player-removal saves, and shutdown saves.

Call it once from a server script.

```lua
local DataService = require(path.to.DataService)
DataService.Init()
```

---

## `DataService.IsLoaded(player) -> boolean`

Returns `true` when the player's profile is available in memory.

---

## `DataService.WaitForData(player, timeoutSeconds?) -> boolean`

Waits until a profile is loaded or the timeout is reached.

Default timeout: `10` seconds.

---

## `DataService.GetSnapshot(player) -> table?, string?`

Returns a deep copy of the player's complete data table.

The copy can be inspected safely without mutating the live profile.

---

## `DataService.GetValue(player, path) -> any?, string?`

Reads one value.

Paths can be dot-separated strings:

```lua
local coins = DataService.GetValue(player, "Coins")
local music = DataService.GetValue(player, "Settings.MusicEnabled")
```

Or arrays:

```lua
local music = DataService.GetValue(player, {"Settings", "MusicEnabled"})
```

---

## `DataService.SetValue(player, path, value) -> boolean, string?`

Sets a value defined in `DataTemplate`.

The new value must match the template type.

```lua
local success, err = DataService.SetValue(player, "Level", 5)
```

---

## `DataService.Increment(player, path, amount) -> boolean, number|string`

Adds a finite number to an existing numeric field.

```lua
local success, newBalance = DataService.Increment(player, "Coins", 50)
```

---

## `DataService.Update(player, callback) -> boolean, string?`

Runs a server-side transaction against a cloned draft.

The draft is validated before it replaces the live profile.

```lua
local success, err = DataService.Update(player, function(data)
    data.Coins -= 100
    data.Level += 1
end)
```

Use this when multiple values should change together.

---

## `DataService.SavePlayer(player) -> boolean, string?`

Requests an immediate save.

Normal games should usually rely on autosave and player-removal saves, but this can be useful before important transitions.

---

# Important security note

This module does not make RemoteEvents safe automatically.

Do not let the client decide trusted values such as currency amounts, item prices, rewards, or progression.

Bad:

```lua
RemoteEvent.OnServerEvent:Connect(function(player, newCoins)
    DataService.SetValue(player, "Coins", newCoins)
end)
```

Better:

```lua
PurchaseRemote.OnServerEvent:Connect(function(player, itemId)
    local item = ServerCatalog[itemId]

    if not item then
        return
    end

    local coins = DataService.GetValue(player, "Coins")

    if coins and coins >= item.Price then
        DataService.Increment(player, "Coins", -item.Price)
        -- Grant the item on the server.
    end
end)
```
