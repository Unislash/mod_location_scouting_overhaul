// -------------------------------------------------------------------------
// mod_location_scouting_2_logic_shared.nut
// -------------------------------------------------------------------------

::ModLocationScouting.resetSession <- function()
{
    this.LastTileID = null;
    this.LastPos    = null;
    this.TileOverlays = {};
    this.updateStatusSettings();
    this.updateLocationSettings();
    this.initAllTiles();
    this.checkIcyCaveCleared();
    this.refreshOverlays();

    this.recalculateDistanceToCivilization();
    this.rebuildFilterPickedSet();

    // Discard any FilterDirty raised by MSU's deserialize-time force-set
    // of Filter_* settings. resetSession just did the full refresh, so
    // the spurious flag would only cause world_screen.onScreenShown
    // to duplicate that work. See FilterDirty declaration in 1_config.nut.
    this.FilterDirty = false;
};

::ModLocationScouting.rebuildFilterPickedSet <- function()
{
    local picked = {};
    foreach (choice in this.FilterChoices)
    {
        local s = this.Mod.ModSettings.getSetting("Filter_" + choice.key);
        if (s.getValue())
            picked[choice.key] <- true;
    }
    this.FilterPickedSet = picked;
};

::ModLocationScouting.spawnOverlay <- function(_tileID)
{
    local coords = this.TileCoords[_tileID];
    local tile = ::World.getTileSquare(coords.X, coords.Y);
    local detail = tile.spawnDetail("world_tile_black_overlay", this.Const.World.ZLevel.Particles - 200, this.Const.World.DetailType.Lighting, false);
    detail.Visible = false;
    this.TileOverlays[_tileID] <- detail;
};

::ModLocationScouting.refreshOverlays <- function()
{
    if (this.ScoutingMode == this.ScoutingModes.Legendary)
    {
        foreach (tileID, detail in this.TileOverlays)
            detail.Visible = !(tileID in this.LegendaryScoutedTiles);
    }
    else if (this.ScoutingMode == this.ScoutingModes.Camp)
    {
        foreach (tileID, detail in this.TileOverlays)
            detail.Visible = !(tileID in this.CampScoutedTiles);
    }
    else if (this.ScoutingMode == this.ScoutingModes.Filter)
    {
        foreach (tileID, detail in this.TileOverlays)
            detail.Visible = !(tileID in this.LegendaryScoutedTiles) && this.matchesFilter(tileID);
    }
    else
    {
        foreach (tileID, detail in this.TileOverlays)
            detail.Visible = false;
    }
};

// Filter-mode visibility predicate: true if the tile matches at least one
// picked legendary by terrain and hex-distance-to-nearest-settlement.
::ModLocationScouting.matchesFilter <- function(_tileID)
{
    if (this.FilterPickedSet.len() == 0)
        return false;

    local terrain = this.TileCoords[_tileID].Terrain;
    local dist = this.TileDistToCiv[_tileID];

    foreach (locKey, _ in this.FilterPickedSet)
    {
        local terrains = this.LocationTerrainTypes[locKey];
        if (terrains.find(terrain) == null)
            continue;
        local distRange = this.LocationDistances[locKey];
        if (dist >= distRange.Min - 1 && dist <= distRange.Max + 1)
            return true;
    }
    return false;
};

::ModLocationScouting.initAllTiles <- function()
{
    this.TileCoords = {};

    local mapSize = ::World.getMapSize();

    for (local tx = 0; tx < mapSize.X; tx++)
    {
        for (local ty = 0; ty < mapSize.Y; ty++)
        {
            local t = ::World.getTileSquare(tx, ty);
            local terrainType = t.Type;
            if (!(terrainType in this.TerrainLocationTypes))
                continue;
            local tileID = tx + "_" + ty;
            this.TileCoords[tileID] <- { X = tx, Y = ty, Terrain = terrainType };
        }
    }

    ::logInfo("[LocationScouting] initAllTiles: registered " + this.TileCoords.len() + " tiles");

    this.TileOverlays = {};
    foreach (tileID, coords in this.TileCoords)
    {
        local tile = ::World.getTileSquare(coords.X, coords.Y);
        tile.clear(this.Const.World.DetailType.Lighting);
        this.spawnOverlay(tileID);
    }

    ::logInfo("[LocationScouting] initAllTiles: spawned " + this.TileOverlays.len() + " overlay details");
};

::ModLocationScouting.onPlayerMoved <- function(_player)
{
    local playerTile = _player.getTile();
    local visionRadius = _player.getVisionRadius().tofloat();
    local playerPos = _player.getPos();

    local xRadius = ::Math.ceil(visionRadius / 180.0).tointeger() + 1;
    local yRadius = ::Math.ceil(visionRadius / 120.0).tointeger() + 1;
    local mapSize = ::World.getMapSize();
    local cx = playerTile.SquareCoords.X;
    local cy = playerTile.SquareCoords.Y;

    local xMin = ::Math.max(0, cx - xRadius);
    local xMax = ::Math.min(mapSize.X - 1, cx + xRadius);
    local yMin = ::Math.max(0, cy - yRadius);
    local yMax = ::Math.min(mapSize.Y - 1, cy + yRadius);

    for (local tx = xMin; tx <= xMax; tx++)
    {
        for (local ty = yMin; ty <= yMax; ty++)
        {
            local t = ::World.getTileSquare(tx, ty);
            local tileID = tx + "_" + ty;
            local terrainType = t.Type;

            local tPos = t.Pos;
            local dx = (playerPos.X - tPos.X).tofloat();
            local dy = (playerPos.Y - tPos.Y).tofloat();
            local dist = ::sqrt(dx * dx + dy * dy);
            local ratio = dist < 1.0 ? 9999.0 : visionRadius / dist;

            // Legendary layer. Filter mode reads from LegendaryScoutedTiles
            // too, so a newly-scouted tile must clear its fog in either mode.
            if (!(tileID in this.LegendaryScoutedTiles) && (terrainType in this.TerrainLocationTypes))
            {
                if (this.isTileFullyScouted(terrainType, ratio))
                {
                    this.LegendaryScoutedTiles[tileID] <- true;
                    if (this.ScoutingMode == this.ScoutingModes.Legendary
                        || this.ScoutingMode == this.ScoutingModes.Filter)
                        this.TileOverlays[tileID].Visible = false;
                }
            }

            // Camp layer
            if (!(tileID in this.CampScoutedTiles) && (tileID in this.TileCoords))
            {
                if (this.isTileCampScouted(terrainType, ratio))
                {
                    this.CampScoutedTiles[tileID] <- true;
                    if (this.ScoutingMode == this.ScoutingModes.Camp)
                        this.TileOverlays[tileID].Visible = false;
                }
            }
        }
    }
};