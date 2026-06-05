// -------------------------------------------------------------------------
// mod_location_scouting_5_menu.nut
// -------------------------------------------------------------------------

::ModLocationScouting.getLocationDescription <- function(_locType)
{
    local desc = "";

    if (_locType in this.LocationTerrainTypes)
    {
        local terrains = this.LocationTerrainTypes[_locType];
        local terrainText = "";
        for (local i = 0; i < terrains.len(); i++)
        {
            if (i > 0) terrainText += ", ";
            terrainText += this.TerrainNames[terrains[i]];
        }
        desc += "Spawns on:\n" + terrainText + ".";
    }

    if (_locType in this.LocationDistances)
    {
        local d = this.LocationDistances[_locType];
        desc += "\n\nDistance to Civilization:\n";
        if (d.Max >= 1000)
            desc += "At least " + d.Min + " tiles to closest City.";
        else
            desc += d.Min + " to " + d.Max + " tiles to closest City.";
    }

    if (_locType == "artifact_reliquary")
    {
        desc += "\n\nWill automatically be revealed after Abandoned Village is cleared.";
    }
    else if (_locType == "tundra_elk_location")
    {
        desc += "\n\nCan only be found after Icy Cave is cleared.";
    }

    return desc;
};

::ModLocationScouting.setupMenu <- function(_infoPage)
{
    local iceCaveSetting = _infoPage.addBooleanSetting("IcyCaveCleared", false, "Icy Cave Cleared?");
    iceCaveSetting.setDescription("The Tundra Elk only spawns after the Icy Cave is cleared. Until then, Tundra tiles are scouted without accounting for the Elk. Once the Icy Cave is cleared, all Tundra tiles are reset and must be scouted again.");
    iceCaveSetting.lock("Marked after you cleared Icy Cave. If you added this Mod mid-campaign, then visit Icy Cave again to mark it.");

    local noteSetting = _infoPage.addBooleanSetting("PresentFromStart", false, "Mod at Campaign Start?");
    noteSetting.setDescription("Automatically set the first time this save is loaded with the mod active.");
    noteSetting.lock("Set when you first open a save file with this mod active.");

    _infoPage.addDivider("divider_legendary");

    foreach (loc in this.LocationLabels)
    {
        local settingID = this.getSettingID(loc.key);
        local s = _infoPage.addBooleanSetting(settingID, false, loc.label);
        s.setDescription(this.getLocationDescription(loc.key));
        s.lock("Checked automatically when you discover this location.");
    }
};


// MSU setting IDs cannot contain dots. Location type keys like
// "holy_site.meteorite" are converted by replacing dots with underscores
// and adding the "loc_" prefix. All other keys pass through unchanged.
::ModLocationScouting.getSettingID <- function(_locType)
{
    local result = "";
    for (local i = 0; i < _locType.len(); i++)
    {
        result += (_locType[i] == '.') ? "_" : _locType[i].tochar();
    }
    return "loc_" + result;
};

// Updates all location checkboxes in the Info tab.
::ModLocationScouting.updateLocationSettings <- function()
{
    foreach (loc in this.LocationLabels)
    {
        local s = this.Mod.ModSettings.getSetting(this.getSettingID(loc.key));
        s.unlock();
        // Skip JS update (first false) and persistence write (second false).
        // These settings are updated from code during world load, not from
        // player interaction. Pushing 20 JS updates simultaneously corrupts
        // the MSU settings UI.
        s.set((loc.key in this.DiscoveredLocationTypes), false, false);
        s.lock("Checked automatically when you discover this location.");
    }
};

// ---- Settings page (user-configurable) ----

::ModLocationScouting.setupSettings <- function(_settingsPage)
{
    _settingsPage.addRangeSetting("ButtonPosition", 72, 10, 90, 1, "Button Position (%)",
        "Horizontal position of the scouting buttons on screen. Higher values move buttons further to the right. Default 72 places them between the center and the top-right icons.");

    _settingsPage.addBooleanSetting("CompactButtons", false, "Compact Buttons",
        "Show single-letter labels (L, C) instead of full text (Legends, Camps). Saves space on smaller screens.");
};

::ModLocationScouting.setupFilter <- function(_filterPage)
{
    foreach (choice in this.FilterChoices)
    {
        local s = _filterPage.addBooleanSetting("Filter_" + choice.key, true, choice.label);
        s.setPersistence(false);
        s.addAfterChangeCallback(function(_oldValue) {
            // Defer-only. Calling refreshOverlays (or any code that
            // mass-mutates TileOverlays) from inside an MSU AfterChange
            // callback corrupts BB's world-map render. See FilterDirty
            // declaration in 1_config.nut for the full mechanism and
            // why the drain lives in world_screen.onScreenShown.
            ::ModLocationScouting.FilterDirty = true;
        });
    }
};

// Updates the IcyCaveCleared and PresentFromStart checkboxes in the Settings tab.
::ModLocationScouting.updateStatusSettings <- function()
{
    local s = this.Mod.ModSettings.getSetting("IcyCaveCleared");
    s.unlock();
    s.set(this.IcyCaveCleared, false, false);
    s.lock("Marked after you cleared Icy Cave. If you added this Mod mid-campaign, then visit Icy Cave again to mark it.");

    local p = this.Mod.ModSettings.getSetting("PresentFromStart");
    p.unlock();
    p.set(this.PresentFromStart, false, false);
    p.lock("Set when you first open a save file with this mod active.");
};

