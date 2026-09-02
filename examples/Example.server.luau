local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local DataService = require(
    ServerScriptService:WaitForChild("PlayerData")
        :WaitForChild("Server")
        :WaitForChild("DataService")
)

DataService.Init()

Players.PlayerAdded:Connect(function(player)
    if not DataService.WaitForData(player, 10) then
        return
    end

    local coins = DataService.GetValue(player, "Coins")
    print(string.format("%s joined with %d coins", player.Name, coins or 0))

    local success, newBalance = DataService.Increment(player, "Coins", 25)

    if success then
        print(string.format(
            "Awarded 25 coins to %s. New balance: %d",
            player.Name,
            newBalance
        ))
    end
end)
