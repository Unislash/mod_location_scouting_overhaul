// -------------------------------------------------------------------------
// mod_location_scouting_3_logic_legendary.nut
// -------------------------------------------------------------------------


// Called when a legendary location is discovered or entered.
::ModLocationScouting.onLocationDiscovered <- function(_locationType)
{
    if (_locationType in this.DiscoveredLocationTypes)
        return;

    this.DiscoveredLocationTypes[_locationType] <- true;
    this.updateLocationSettings();
};

// Returns true if the player has been close enough to rule out all legendary
// locations that could spawn on this terrain type. Caller filters by
// (terrainType in TerrainLocationTypes) before calling.
::ModLocationScouting.isTileFullyScouted <- function(_terrainType, _ratio)
{
    local terrainVisMult = this.getTerrainVisibilityMult(_terrainType);
    local locationTypes = this.TerrainLocationTypes[_terrainType];

    for (local i = 0; i < locationTypes.len(); i++)
    {
        local locType = locationTypes[i];

        // Elk is not yet active. Skip it so tundra tiles can still be fully scouted.
        if (locType == "tundra_elk_location" && !this.IcyCaveCleared)
            continue;

        local effective = this.LocationVisibilityMults[locType].tofloat() * terrainVisMult;

        // ratio * effective >= 1.0 means the player was close enough to discover any location on this tile.
        if (_ratio * effective < 1.0)
            return false;
    }
    return true;
};

// When the Icy Cave is cleared, all tundra tiles must be rescouted because
// the Tundra Elk can now spawn there.
::ModLocationScouting.onIcyCaveCleared <- function()
{
    local toReset = [];
    foreach (tileID, _ in this.LegendaryScoutedTiles)
    {
        local coords = this.TileCoords[tileID];
        local tile = ::World.getTileSquare(coords.X, coords.Y);
        if (tile.Type == 14)
            toReset.push(tileID);
    }
    for (local i = 0; i < toReset.len(); i++)
        delete this.LegendaryScoutedTiles[toReset[i]];

    ::logInfo("[LocationScouting] onIcyCaveCleared: reset " + toReset.len() + " tundra tiles");
    this.updateStatusSettings();
    this.refreshOverlays();
};

::ModLocationScouting.isIcyCaveCleared <- function()
{
    // BB does not pre-create IjirokStage; it appears the first time the
    // player progresses the Ijirok quest. The has() check is the real
    // "quest not started yet" state, not a fence against bad data.
    return ::World.Flags.has("IjirokStage") && ::World.Flags.get("IjirokStage").tointeger() >= 4;
};

// Detects when the icy cave is cleared and triggers the tundra tile reset.
// Safe to call multiple times - the IcyCaveCleared guard prevents duplicate work.
::ModLocationScouting.checkIcyCaveCleared <- function()
{
    if (!this.IcyCaveCleared && this.isIcyCaveCleared())
    {
        this.IcyCaveCleared = true;
        this.onIcyCaveCleared();
    }
};

// Writes TileDistToCiv with the min hex distance from each registered
// tile to the nearest discovered settlement. Read by matchesFilter.
::ModLocationScouting.recalculateDistanceToCivilization <- function()
{
    local discoveredTiles = [];
    foreach (s in ::World.EntityManager.getSettlements())
        if (s.isDiscovered())
            discoveredTiles.push(s.getTile());

    ::logInfo("[LocationScouting] recalculateDistanceToCivilization: " + discoveredTiles.len() + " discovered settlements, " + this.TileCoords.len() + " tiles");

    this.TileDistToCiv = {};
    foreach (tileID, coords in this.TileCoords)
    {
        local tile = ::World.getTileSquare(coords.X, coords.Y);
        local minDist = 1000;
        foreach (sTile in discoveredTiles)
        {
            local d = sTile.getDistanceTo(tile);
            if (d < minDist)
                minDist = d;
        }
        this.TileDistToCiv[tileID] <- minDist;
    }
};