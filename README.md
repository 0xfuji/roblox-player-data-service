# Roblox Player Data Service

A small, dependency-free Luau player data service for Roblox.

I built this as a clean starting point for projects where player data starts spreading across too many scripts. The service keeps reads and writes behind a server-side API, validates changes against a simple template, and avoids handing out the live profile table.

> **Status:** early but usable. The API is intentionally small while the project is still being tested and improved.

## Why this exists

Player data is easy to keep simple at the beginning of a game. It gets harder once currency, progression, settings, inventories, and other systems all need to read or change the same profile.

This project keeps those operations in one place and tries to make unsafe patterns harder to write by accident.

## Features

- Server-owned player profiles
- DataStore loading and saving
- Retry handling for temporary DataStore failures
- Fail-closed loading to reduce accidental overwrites
- Autosave and shutdown saves
- Default-data reconciliation
- Template-based type validation
- Deep-copy reads so callers cannot mutate live data
- Dot-path reads and writes
- Atomic-style server updates against a validated draft
- No external dependencies

## Project structure

```text
roblox-player-data-service/
├── src/
│   ├── server/
│   │   ├── DataService.luau
│   │   └── DataValidator.luau
│   └── shared/
│       └── DataTemplate.luau
├── examples/
│   └── Example.server.luau
├── docs/
│   └── API.md
├── default.project.json
├── LICENSE
└── README.md
```

## Studio setup

Create this structure in `ServerScriptService`:

```text
ServerScriptService
└── PlayerData
    ├── Server
    │   ├── DataService
    │   └── DataValidator
    └── Shared
        └── DataTemplate
```

Copy the matching `.luau` files into those ModuleScripts.

Then require and initialize the service from a normal server Script:

```lua
local ServerScriptService = game:GetService("ServerScriptService")

local DataService = require(
    ServerScriptService.PlayerData.Server.DataService
)

DataService.Init()
```

If you are testing DataStores in Studio, enable:

**Game Settings → Security → Enable Studio Access to API Services**

Use a separate test place when possible. Studio API access can touch real DataStores.

## Quick usage

Read a value:

```lua
local coins = DataService.GetValue(player, "Coins")
```

Set a value:

```lua
local success, err = DataService.SetValue(player, "Level", 2)

if not success then
    warn(err)
end
```

Increment a number:

```lua
local success, newBalance = DataService.Increment(player, "Coins", 25)
```

Update multiple values together:

```lua
local success, err = DataService.Update(player, function(data)
    data.Coins -= 100
    data.Level += 1
end)
```

## Server authority

The service is designed to be called from the server.

A client should request an action, not tell the server what trusted data should become.

For example, don't let a client send its own new coin balance. Let it request a purchase, validate the item and price on the server, then update the balance there.

That distinction matters more than the data module itself.

## Data template

Edit `src/shared/DataTemplate.luau` to define your defaults:

```lua
return {
    Coins = 0,
    Level = 1,

    Settings = {
        MusicEnabled = true,
        SfxEnabled = true,
    },
}
```

Existing saved profiles are reconciled with new default fields when they load.

## Current limitations

This is deliberately not advertised as a drop-in replacement for mature profile libraries.

Current limitations include:

- No cross-server session locking
- No schema migration/version framework yet
- No built-in RemoteEvent layer
- No inventory-specific schema helpers
- No automated test suite yet

For large live games with valuable economies, cross-server session locking and stronger operational tooling are worth adding before treating the service as production infrastructure.

## Roadmap

Things I want to explore next:

- Session locking
- Schema/version migrations
- Better development logging
- Automated tests
- More examples
- Optional nested-schema helpers

## Documentation

See [`docs/API.md`](docs/API.md) for the public API and security examples.

## Contributing

Bug reports and small focused pull requests are welcome.

If you are changing behavior, please explain the reason for the change and include a short example when possible.

## License

MIT
