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

::ModLocationScouting.getOverlayVariantCount <- function(_mask)
{
    if (_mask == 0)
        // Fully enclosed fog occasionally disappears in-world on the
        // alternate mask-00 variants, so keep that case on one stable brush.
        return 1;

    return this.Const.getNumDirectionBits(_mask) == 1 ? 2 : 1;
};

::ModLocationScouting.rotateOverlayMask <- function(_mask, _steps)
{
    local steps = _steps % this.Const.Direction.COUNT;
    if (steps < 0)
        steps = steps + this.Const.Direction.COUNT;

    local rotated = _mask;
    for (local i = 0; i < steps; i++)
        rotated = ((rotated << 1) & 63) | ((rotated >> (this.Const.Direction.COUNT - 1)) & 1);

    return rotated;
};

::ModLocationScouting.remapOverlayMaskForBrush <- function(_mask)
{
    local rotatedMask = this.rotateOverlayMask(_mask, this.OverlayBrushRotationSteps);
    local remapped = 0;

    for (local dir = 0; dir < this.Const.Direction.COUNT; dir++)
    {
        if ((rotatedMask & this.Const.DirectionBit[dir]) == 0)
            continue;

        remapped = remapped | this.Const.DirectionBit[this.OverlayBrushDirectionMap[dir]];
    }

    return remapped;
};

::ModLocationScouting.getOverlayBrushName <- function(_tileID, _mask)
{
    local brushMask = this.remapOverlayMaskForBrush(_mask);
    local variants = this.getOverlayVariantCount(brushMask);
    local variant = 0;

    if (variants > 1)
    {
        local coords = this.TileCoords[_tileID];
        local seed = coords.X * 73856093 + coords.Y * 19349663 + _mask * 83492791;
        if (seed < 0)
            seed = -seed;
        variant = seed % variants;
    }

    return "world_tile_fog_" + (brushMask < 10 ? "0" : "") + brushMask + "_v" + variant;
};

::ModLocationScouting.isTileFoggedInMode <- function(_tileID, _mode)
{
    if (!(_tileID in this.TileCoords))
        return false;

    if (_mode == this.ScoutingModes.Legendary)
        return !(_tileID in this.LegendaryScoutedTiles);

    if (_mode == this.ScoutingModes.Camp)
        return !(_tileID in this.CampScoutedTiles);

    if (_mode == this.ScoutingModes.Filter)
        return !(_tileID in this.LegendaryScoutedTiles) && this.matchesFilter(_tileID);

    return false;
};

::ModLocationScouting.getOverlayMaskForMode <- function(_tileID, _mode)
{
    local coords = this.TileCoords[_tileID];
    local tile = ::World.getTileSquare(coords.X, coords.Y);
    local mask = 0;

    for (local dir = 0; dir < this.Const.Direction.COUNT; dir++)
    {
        local neighborFogged = false;

        if (tile.hasNextTile(dir))
        {
            local nextTile = tile.getNextTile(dir);
            local nextID = nextTile.SquareCoords.X + "_" + nextTile.SquareCoords.Y;
            neighborFogged = this.isTileFoggedInMode(nextID, _mode);
        }

        if (!neighborFogged)
            mask = mask | this.Const.DirectionBit[dir];
    }

    return mask;
};

::ModLocationScouting.spawnOverlay <- function(_tileID, _brushName)
{
    local coords = this.TileCoords[_tileID];
    local tile = ::World.getTileSquare(coords.X, coords.Y);
    local detail = tile.spawnDetail(_brushName, this.Const.World.ZLevel.Particles - 200, this.Const.World.DetailType.Lighting, false);
    detail.Visible = false;
    this.TileOverlays[_tileID] <- detail;
    return detail;
};

::ModLocationScouting.respawnOverlay <- function(_tileID, _mode)
{
    local coords = this.TileCoords[_tileID];
    local tile = ::World.getTileSquare(coords.X, coords.Y);
    local brush = this.DefaultOverlayBrush;
    local visible = false;

    if (_mode != this.ScoutingModes.Off && this.isTileFoggedInMode(_tileID, _mode))
    {
        local mask = this.getOverlayMaskForMode(_tileID, _mode);
        brush = this.getOverlayBrushName(_tileID, mask);
        visible = true;
    }

    tile.clear(this.Const.World.DetailType.Lighting);
    local detail = this.spawnOverlay(_tileID, brush);
    detail.Visible = visible;
};

::ModLocationScouting.rebuildOverlaysForMode <- function(_mode)
{
    foreach (tileID, _ in this.TileCoords)
        this.respawnOverlay(tileID, _mode);
};

::ModLocationScouting.refreshOverlayNeighborhoods <- function(_changedTiles, _mode)
{
    local toRefresh = {};

    foreach (tileID, _ in _changedTiles)
    {
        if (!(tileID in this.TileCoords))
            continue;

        toRefresh[tileID] <- true;

        local coords = this.TileCoords[tileID];
        local tile = ::World.getTileSquare(coords.X, coords.Y);
        for (local dir = 0; dir < this.Const.Direction.COUNT; dir++)
        {
            if (!tile.hasNextTile(dir))
                continue;

            local nextTile = tile.getNextTile(dir);
            local nextID = nextTile.SquareCoords.X + "_" + nextTile.SquareCoords.Y;
            if (nextID in this.TileCoords)
                toRefresh[nextID] <- true;
        }
    }

    foreach (tileID, _ in toRefresh)
        this.respawnOverlay(tileID, _mode);
};

::ModLocationScouting.refreshOverlays <- function()
{
    if (this.ScoutingMode == this.ScoutingModes.Off)
    {
        foreach (tileID, detail in this.TileOverlays)
            detail.Visible = false;
        return;
    }

    this.rebuildOverlaysForMode(this.ScoutingMode);
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
        this.spawnOverlay(tileID, this.DefaultOverlayBrush);
    }

    ::logInfo("[LocationScouting] initAllTiles: spawned " + this.TileOverlays.len() + " overlay details");
};

::ModLocationScouting.onPlayerMoved <- function(_player)
{
    local playerTile = _player.getTile();
    local visionRadius = _player.getVisionRadius().tofloat();
    local playerPos = _player.getPos();
    local changedLegendary = {};
    local changedCamp = {};

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
                    changedLegendary[tileID] <- true;
                }
            }

            // Camp layer
            if (!(tileID in this.CampScoutedTiles) && (tileID in this.TileCoords))
            {
                if (this.isTileCampScouted(terrainType, ratio))
                {
                    this.CampScoutedTiles[tileID] <- true;
                    changedCamp[tileID] <- true;
                }
            }
        }
    }

    if ((this.ScoutingMode == this.ScoutingModes.Legendary || this.ScoutingMode == this.ScoutingModes.Filter) && changedLegendary.len() > 0)
        this.refreshOverlayNeighborhoods(changedLegendary, this.ScoutingMode);

    if (this.ScoutingMode == this.ScoutingModes.Camp && changedCamp.len() > 0)
        this.refreshOverlayNeighborhoods(changedCamp, this.ScoutingMode);
};
