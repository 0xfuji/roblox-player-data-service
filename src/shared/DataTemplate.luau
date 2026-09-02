--[[
    DataTemplate
    ------------
    This table defines the default shape of a player's saved data.

    Keep values DataStore-safe:
    strings, booleans, finite numbers, and tables containing those types.
]]

return {
    Coins = 0,
    Level = 1,

    Settings = {
        MusicEnabled = true,
        SfxEnabled = true,
    },
}
