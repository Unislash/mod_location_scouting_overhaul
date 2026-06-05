// -------------------------------------------------------------------------
// mod_location_scouting_1_config.nut
// -------------------------------------------------------------------------

::ModLocationScouting <- {
    ID = "mod_location_scouting",
    Name = "Location Scouting",
    Version = "2.0.0",

    // --- Runtime state ---
    LastTileID = null,
    LastPos = null,
    TileCoords = {},
    ScoutingMode = "off",
    PresentFromStart = false,

    // Per-campaign scouting state. Persisted via MSU flagSerialize in
    // hooks.nut onSerialize, not via MSU's setting persistence.
    LegendaryScoutedTiles = {},
    DiscoveredLocationTypes = {},
    IcyCaveCleared = false,
    CampScoutedTiles = {},

    // Filter-mode working sets. TileDistToCiv is rebuilt in
    // recalculateDistanceToCivilization; FilterPickedSet in
    // rebuildFilterPickedSet. Both read by matchesFilter.
    TileDistToCiv = {},
    FilterPickedSet = {},

    // FilterDirty — deferred-refresh flag for Filter mode. Transient
    // runtime state, never persisted.
    //
    // Lifecycle:
    //   SET   — Filter checkbox addAfterChangeCallback (5_menu.nut)
    //   DRAIN — world_screen.onScreenShown             (6_hooks.nut)
    //   CLEAR — resetSession                           (2_logic_shared.nut)
    //
    // Why we defer instead of refreshing in the checkbox callback:
    //
    //   MSU fires AfterChangeCallback during the Apply tick while the
    //   world screen is hidden — see external/bb-reference-mods/
    //   mod_msu/msu/hooks/states/world_state.nut, where opening MSU
    //   settings calls WorldScreen.hide() before SettingsScreen.show().
    //   Iterating ~20k TileOverlays and flipping detail.Visible from
    //   that context corrupts BB's world-map render: streets vanish
    //   and stray overlays appear on tiles OUTSIDE TerrainLocationTypes
    //   (initAllTiles only carpet-clears Lighting on tiles inside it,
    //   so the corruption persists across reloads).
    //
    //   Deferring also collapses MSU's per-changed-setting fan-out:
    //   toggle 3 boxes -> 3 callbacks set the flag -> 1 drain runs.
    //
    // Why we CLEAR in resetSession:
    //
    //   MSU's __setFromSerializationTable calls set(value, ..., _force=true)
    //   for each saved setting on load. _force bypasses the value-equal
    //   skip and fires AfterChangeCallback even when nothing changed,
    //   raising FilterDirty during onDeserialize. resetSession itself
    //   already does the full refresh (recalc + rebuild + refreshOverlays),
    //   so clearing here satisfies and discards the spurious load-time
    //   drain that would otherwise duplicate the work seconds later
    //   when world_screen.onScreenShown fires.
    FilterDirty = false,

    // Black fog layer: one detail per tile, mode-driven.
    // Spawned once at load time with Visible=false; refresh only toggles.
    TileOverlays = {},

    // Scouting mode constants
    ScoutingModes = {
        Off       = "off",
        Legendary = "legendary",
        Camp      = "camp",
        Filter    = "filter"
    },

    // Human readable terrain names
    TerrainNames = {
        [2]  = "Plains",
        [3]  = "Swamp",
        [4]  = "Hills",
        [5]  = "Forest",
        [6]  = "Snowy Forest",
        [7]  = "Leaf Forest",
        [8]  = "Autumn Forest",
        [9]  = "Mountains",
        [12] = "Snow",
        [13] = "Badlands",
        [14] = "Tundra",
        [15] = "Steppe",
        [17] = "Desert",
        [18] = "Oasis"
    },

    TerrainVisibilityMults = {
        [5]  = 0.5,
        [6]  = 0.5,
        [7]  = 0.5,
        [8]  = 0.5,
        [9]  = 0.5,
        [3]  = 0.9,
        [4]  = 0.9,
        [18] = 0.9
    },

    TerrainLocationTypes = {
        [2]  = ["black_monolith", "waterwheel", "holy_site.meteorite", "land_ship", "ancient_statue", "ancient_temple", "abandoned_village"],
        [3]  = ["unhold_graveyard", "kraken_cult", "land_ship", "ancient_statue", "ancient_temple"],
        [4]  = ["black_monolith", "goblin_city", "ancient_watchtower", "land_ship", "ancient_statue", "ancient_temple"],
        [5]  = ["fountain_of_youth", "witch_hut", "land_ship"],
        [6]  = ["icy_cave_location", "land_ship"],
        [7]  = ["fountain_of_youth", "witch_hut", "land_ship"],
        [8]  = ["fountain_of_youth", "witch_hut", "land_ship"],
        [9]  = ["goblin_city", "ancient_watchtower"],
        [12] = ["unhold_graveyard", "icy_cave_location", "land_ship"],
        [13] = ["unhold_graveyard", "land_ship", "ancient_statue", "ancient_temple"],
        [14] = ["black_monolith", "unhold_graveyard", "land_ship", "ancient_statue", "ancient_temple", "abandoned_village", "tundra_elk_location"],
        [15] = ["black_monolith", "holy_site.meteorite", "land_ship", "ancient_statue", "ancient_temple", "holy_site.oracle"],
        [17] = ["sunken_library", "holy_site.oracle", "holy_site.vulcano", "land_ship"],
        [18] = ["land_ship", "ancient_statue", "ancient_temple"]
    },

    LocationTerrainTypes = {
        ancient_watchtower      = [4, 9],
        abandoned_village       = [2, 14],
        ancient_statue          = [2, 3, 4, 13, 14, 15, 18],
        ancient_temple          = [2, 3, 4, 13, 14, 15, 18],
        black_monolith          = [2, 4, 14, 15],
        fountain_of_youth       = [5, 7, 8],
        goblin_city             = [4, 9],
        ["holy_site.meteorite"] = [2, 15],
        ["holy_site.oracle"]    = [15, 17],
        ["holy_site.vulcano"]   = [17],
        icy_cave_location       = [6, 12],
        kraken_cult             = [3],
        land_ship               = [2, 3, 4, 5, 6, 7, 8, 12, 13, 14, 15, 17, 18],
        sunken_library          = [17],
        tundra_elk_location     = [14],
        unhold_graveyard        = [3, 12, 13, 14],
        waterwheel              = [2],
        witch_hut               = [5, 7, 8],
        artifact_reliquary      = [2, 15, 14],
    },

    LocationVisibilityMults = {
        ancient_watchtower      = 1.1,
        abandoned_village       = 1.0,
        ancient_statue          = 1.0,
        black_monolith          = 1.0,
        ancient_temple          = 0.9,
        fountain_of_youth       = 0.9,
        kraken_cult             = 0.9,
        land_ship               = 0.9,
        unhold_graveyard        = 0.9,
        goblin_city             = 0.9,
        waterwheel              = 0.9,
        witch_hut               = 0.9,
        icy_cave_location       = 0.8,
        tundra_elk_location     = 0.8,
        ["holy_site.meteorite"] = 0.8,
        ["holy_site.oracle"]    = 0.8,
        sunken_library          = 0.8,
        ["holy_site.vulcano"]   = 0.8
    },

    LocationDistances = {
        ancient_watchtower      = { Min = 25,  Max = 60   },
        abandoned_village       = { Min = 6,   Max = 21   },
        ancient_statue          = { Min = 20,  Max = 35   },
        ancient_temple          = { Min = 25,  Max = 40   },
        black_monolith          = { Min = 45,  Max = 1000 },
        fountain_of_youth       = { Min = 40,  Max = 1000 },
        goblin_city             = { Min = 30,  Max = 1000 },
        ["holy_site.meteorite"] = { Min = 8,   Max = 25   },
        ["holy_site.oracle"]    = { Min = 8,   Max = 25   },
        ["holy_site.vulcano"]   = { Min = 8,   Max = 25   },
        icy_cave_location       = { Min = 10,  Max = 35   },
        kraken_cult             = { Min = 25,  Max = 1000 },
        land_ship               = { Min = 15,  Max = 30   },
        sunken_library          = { Min = 18,  Max = 50   },
        tundra_elk_location     = { Min = 15,  Max = 99   },
        unhold_graveyard        = { Min = 25,  Max = 1000 },
        waterwheel              = { Min = 15,  Max = 30   },
        witch_hut               = { Min = 15,  Max = 25   },
        artifact_reliquary      = { Min = 12,  Max = 25   }
    },

    LocationLabels = [
        { key = "icy_cave_location",   label = "Icy Cave (Mad Men)" },
        { key = "tundra_elk_location", label = "Hunting Ground (Ijirok)" },
        { key = "abandoned_village",   label = "Abandoned Village" },
        { key = "artifact_reliquary",  label = "Artifact Reliquary" },
        { key = "kraken_cult",         label = "Stone Pillars (Kraken)" },
        { key = "waterwheel",          label = "Water Mill" },
        { key = "sunken_library",      label = "Sunken Library" },
        { key = "witch_hut",           label = "Witch Hut" },
        { key = "goblin_city",         label = "Goblin City" },
        { key = "black_monolith",      label = "Black Monolith" },
        { key = "ancient_watchtower",  label = "Ancient Spire (Watchtower)" },
        { key = "ancient_statue",      label = "Ancient Statue" },
        { key = "ancient_temple",      label = "Ancient Temple" },
        { key = "fountain_of_youth",   label = "Grotesque Tree (Fountain of Youth)" },
        { key = "unhold_graveyard",    label = "Unhold Graveyard" },
        { key = "land_ship",           label = "Curious Ship Wreck (Golden Goose)" },
        { key = "holy_site.meteorite", label = "Holy Site: Meteorite" },
        { key = "holy_site.oracle",    label = "Holy Site: Oracle" },
        { key = "holy_site.vulcano",   label = "Holy Site: Volcano" }
    ],

    // setupFilter builds one checkbox per entry. matchesFilter reads the
    // resulting FilterPickedSet to decide which tiles stay fogged.
    FilterChoices = [
        { key = "icy_cave_location",   label = "Icy Cave (Mad Men)" },
        { key = "tundra_elk_location", label = "Hunting Ground (Ijirok)" },
        { key = "witch_hut",           label = "Witch Hut" },
        { key = "sunken_library",      label = "Sunken Library" },
        { key = "black_monolith",      label = "Black Monolith" },
        { key = "goblin_city",         label = "Goblin City" }
    ],

    CampVisibilityMultsbyTerrain = {
        [4]  = 0.8,
        [15] = 0.8,
        [17] = 0.8,
        [18] = 0.8
    },

};

::ModLocationScouting.getTerrainVisibilityMult <- function(_terrainType)
{
    if (_terrainType in this.TerrainVisibilityMults)
        return this.TerrainVisibilityMults[_terrainType].tofloat();
    return 1.0;
};
