// -------------------------------------------------------------------------
// mod_location_scouting_4_logic_camp.nut
// -------------------------------------------------------------------------

// Returns true if the player has been close enough to rule out all enemy camps
// that could spawn on this terrain type.
::ModLocationScouting.isTileCampScouted <- function(_terrainType, _ratio)
{
    local terrainVisMult = this.getTerrainVisibilityMult(_terrainType);

    // Most camps use VisibilityMult 1.0. Only nomad_hidden_camp and nomad_tents
    // use 0.8, spawning exclusively on Hills, Steppe, Desert, and Oasis.
    local campVisMult = 1.0;
    if (_terrainType in this.CampVisibilityMultsbyTerrain)
        campVisMult = this.CampVisibilityMultsbyTerrain[_terrainType];

    local effective = campVisMult * terrainVisMult;

    // ratio * effective >= 1.0 means the player was close enough to discover any camp on this tile.
    return _ratio * effective >= 1.0;
};

// Resets camp scouting for all tiles, forcing the player to rescout.
// refreshOverlays handles teardown and respawn for the current mode.
::ModLocationScouting.resetCampScouting <- function()
{
    this.CampScoutedTiles = {};
    this.initAllTiles();
};