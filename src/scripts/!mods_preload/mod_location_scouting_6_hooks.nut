// -------------------------------------------------------------------------
// mod_location_scouting_6_hooks.nut
// -------------------------------------------------------------------------

::Hooks.registerLateJS("ui/screens/world/modules/world_screen_topbar/mod_location_scouting_topbar.js");
::Hooks.registerCSS("ui/screens/world/modules/world_screen_topbar/mod_location_scouting_topbar.css");

::ModLocationScouting.WorldScreen <- null;

// Reads MSU settings and sends them to the JS topbar.
::ModLocationScouting.sendUISettings <- function()
{
    local pos = this.Mod.ModSettings.getSetting("ButtonPosition").getValue();
    local compact = this.Mod.ModSettings.getSetting("CompactButtons").getValue();
    ::logInfo("[LocationScouting] sendUISettings pos=" + pos + " compact=" + compact);
    this.WorldScreen.m.JSHandle.asyncCall("applyScoutingUISettings", [pos, compact]);
};

// Sets the scouting mode, refreshes overlays, and updates the JS button state.
// Does NOT contain toggle logic - callers decide what mode to pass.
::ModLocationScouting.setScoutingMode <- function(_mode)
{
    ::logInfo("[LocationScouting] setScoutingMode: " + _mode);
    this.ScoutingMode = _mode;
    this.refreshOverlays();
    this.WorldScreen.m.JSHandle.asyncCall("setScoutingButtonState", [this.ScoutingMode]);
};

::ModLocationScouting.HooksMod <- ::Hooks.register(::ModLocationScouting.ID, ::ModLocationScouting.Version, ::ModLocationScouting.Name);
::ModLocationScouting.HooksMod.queue(">mod_msu", function()
{
    ::ModLocationScouting.Mod <- ::MSU.Class.Mod(::ModLocationScouting.ID, ::ModLocationScouting.Version, ::ModLocationScouting.Name);

    local filterPage = ::ModLocationScouting.Mod.ModSettings.addPage("Filter");
    ::ModLocationScouting.setupFilter(filterPage);

    local infoPage = ::ModLocationScouting.Mod.ModSettings.addPage("Info");
    ::ModLocationScouting.setupMenu(infoPage);

    local settingsPage = ::ModLocationScouting.Mod.ModSettings.addPage("Settings");
    ::ModLocationScouting.setupSettings(settingsPage);

    ::ModLocationScouting.Mod.Keybinds.addSQKeybind("ToggleLegendary", "ctrl+l", ::MSU.Key.State.World, function()
    {
        local newMode = (::ModLocationScouting.ScoutingMode == ::ModLocationScouting.ScoutingModes.Legendary)
            ? ::ModLocationScouting.ScoutingModes.Off
            : ::ModLocationScouting.ScoutingModes.Legendary;
        ::ModLocationScouting.setScoutingMode(newMode);
        return true;
    }, "Toggle Legendary Scouting");

    ::ModLocationScouting.Mod.Keybinds.addSQKeybind("ToggleCamp", "ctrl+e", ::MSU.Key.State.World, function()
    {
        local newMode = (::ModLocationScouting.ScoutingMode == ::ModLocationScouting.ScoutingModes.Camp)
            ? ::ModLocationScouting.ScoutingModes.Off
            : ::ModLocationScouting.ScoutingModes.Camp;
        ::ModLocationScouting.setScoutingMode(newMode);
        return true;
    }, "Toggle Camp Scouting");


    ::ModLocationScouting.Mod.Keybinds.addSQKeybind("ToggleFilter", "ctrl+f", ::MSU.Key.State.World, function()
    {
        local newMode = (::ModLocationScouting.ScoutingMode == ::ModLocationScouting.ScoutingModes.Filter)
            ? ::ModLocationScouting.ScoutingModes.Off
            : ::ModLocationScouting.ScoutingModes.Filter;
        ::ModLocationScouting.setScoutingMode(newMode);
        return true;
    }, "Toggle Filter Scouting");

    ::ModLocationScouting.Mod.Keybinds.addSQKeybind("ResetCampScouting", "ctrl+r", ::MSU.Key.State.World, function()
    {
        ::ModLocationScouting.resetCampScouting();
        ::ModLocationScouting.setScoutingMode(::ModLocationScouting.ScoutingModes.Camp);
        ::ModLocationScouting.LastTileID = null;
        ::ModLocationScouting.LastPos = null;
        return true;
    }, "Reset Camp Scouting");

    ::Hooks.__rawHook(::ModLocationScouting.HooksMod, "scripts/entity/world/player_party", function(o)
    {
        ::logInfo("[LocationScouting] onUpdate hook");
        local onUpdate = o.onUpdate;
        o.onUpdate = function()
        {
            onUpdate();

            local tile = this.getTile();

            local playerPos = this.getPos();
            local tileID = tile.ID;

            local tileMoved = tileID != ::ModLocationScouting.LastTileID;
            local lastPos = ::ModLocationScouting.LastPos;

            // First tick after resetSession has lastPos == null (real
            // initial state, not a fence). Otherwise trigger when the
            // player has moved at least ~50px from the recorded position.
            local distMoved = lastPos == null || (playerPos.X - lastPos.X) * (playerPos.X - lastPos.X) + (playerPos.Y - lastPos.Y) * (playerPos.Y - lastPos.Y) > 2500;

            if (tileMoved || distMoved)
            {
                ::ModLocationScouting.LastTileID = tileID;
                ::ModLocationScouting.LastPos = playerPos;
                ::ModLocationScouting.onPlayerMoved(this);
            }
        }
    });

    ::Hooks.__rawHook(::ModLocationScouting.HooksMod, "scripts/entity/world/location", function(o)
    {
        local onDiscovered = o.onDiscovered;
        o.onDiscovered = function()
        {
            onDiscovered();
            local fullID = this.getTypeID();
            // mirror of the approved guard in onEnter below; same reason
            if (fullID.len() <= 9) return;
            local locType = fullID.slice(9);
            ::ModLocationScouting.onLocationDiscovered(locType);
        }

        local onEnter = o.onEnter;
        o.onEnter = function()
        {
            local result = onEnter();
            local fullID = this.getTypeID();

            // this guard is necessary, otherwise errors are thrown [Approved by User Pascal]
            if (fullID.len() <= 9) return result;

            local locType = fullID.slice(9);
            ::ModLocationScouting.onLocationDiscovered(locType);
            if (locType == "icy_cave_location")
                ::ModLocationScouting.checkIcyCaveCleared();

            // remember to return result so game knows 
            // whether camp should be attacked
            return result;
        }

        local onCombatLost = o.onCombatLost;
        o.onCombatLost = function()
        {
            // Temporary battlefield locations clear most world detail types
            // from their tile when they expire. Our overlay lives in
            // DetailType.Lighting, so battle-site cleanup punches a visible
            // hole unless we restore the tile immediately afterward.
            local repairTileID = null;
            if (this.m.IsBattlesite)
            {
                local tile = this.getTile();
                repairTileID = tile.SquareCoords.X + "_" + tile.SquareCoords.Y;
            }

            local result = onCombatLost();

            if (repairTileID != null && repairTileID in ::ModLocationScouting.TileCoords)
                ::ModLocationScouting.respawnOverlay(repairTileID, ::ModLocationScouting.ScoutingMode);

            return result;
        }

    });

    ::Hooks.__rawHook(::ModLocationScouting.HooksMod, "scripts/events/events/dlc4/location/icy_cave_enter_event", function(o)
    {
        local onClear = o.onClear;
        o.onClear = function()
        {
            onClear();
            ::ModLocationScouting.checkIcyCaveCleared();
        }
    });

    ::Hooks.__rawHook(::ModLocationScouting.HooksMod, "scripts/ui/screens/world/world_screen", function(o)
    {
        local onScreenConnected = o.onScreenConnected;
        o.onScreenConnected = function()
        {
            onScreenConnected();
            ::ModLocationScouting.WorldScreen = this;
            ::ModLocationScouting.sendUISettings();
            this.m.JSHandle.asyncCall("setScoutingButtonState", [::ModLocationScouting.ScoutingMode]);
        };

        local onScreenShown = o.onScreenShown;
        o.onScreenShown = function()
        {
            onScreenShown();
            ::ModLocationScouting.sendUISettings();

            // Drain Filter mode's deferred refresh. onScreenShown fires
            // when the world screen becomes the active screen — after
            // initial connect, after MSU dialog close (MSU's MenuStack
            // pop calls WorldScreen.show()), and after returning from
            // tactical. All are safe contexts for refreshOverlays.
            // See FilterDirty declaration in 1_config.nut.
            if (::ModLocationScouting.FilterDirty)
            {
                ::ModLocationScouting.FilterDirty = false;
                ::logInfo("[LocationScouting] draining FilterDirty — recomputing distances and refreshing overlays");
                ::ModLocationScouting.recalculateDistanceToCivilization();
                ::ModLocationScouting.rebuildFilterPickedSet();
                ::ModLocationScouting.refreshOverlays();
            }
        };

        local onScreenDisconnected = o.onScreenDisconnected;
        o.onScreenDisconnected = function()
        {
            onScreenDisconnected();
            ::ModLocationScouting.WorldScreen = null;
        };

        // Toggle: if the clicked mode is already active, turn off. Otherwise activate it.
        o.onScoutingButtonClicked <- function(_mode)
        {
            local newMode = (_mode == ::ModLocationScouting.ScoutingMode)
                ? ::ModLocationScouting.ScoutingModes.Off
                : _mode;
            ::ModLocationScouting.setScoutingMode(newMode);
        };

        // Reset camp data, then always activate camp mode.
        o.onResetCampScoutingClicked <- function()
        {
            ::ModLocationScouting.resetCampScouting();
            ::ModLocationScouting.setScoutingMode(::ModLocationScouting.ScoutingModes.Camp);
            ::ModLocationScouting.LastTileID = null;
            ::ModLocationScouting.LastPos = null;
        };
    });

    ::Hooks.__rawHook(::ModLocationScouting.HooksMod, "scripts/states/world_state", function(o)
    {
        local onSerialize = o.onSerialize;
        o.onSerialize = function(_out)
        {
            // Per-campaign scouting state via MSU flag serialization.
            // flagSerialize MUST run before __original(_out): MSU's
            // wrapper calls clearFlags() at the end of its onSerialize
            // and that walks our pushed emulators. Calls placed AFTER
            // __original leave emulators stranded and crash the next
            // deserialize ("the index 'remove' does not exist").
            //
            // Tile sets are encoded as comma-separated ID strings rather
            // than table-of-bools so each tile set is ~3 World.Flags
            // entries instead of 4N+5. ScoutingMode is intentionally
            // not persisted; every load forces it back to Off.
            local Mod = ::ModLocationScouting.Mod;

            local legendaryStr = "";
            foreach (id, _ in ::ModLocationScouting.LegendaryScoutedTiles)
                legendaryStr += (legendaryStr.len() == 0 ? "" : ",") + id;
            local campStr = "";
            foreach (id, _ in ::ModLocationScouting.CampScoutedTiles)
                campStr += (campStr.len() == 0 ? "" : ",") + id;

            Mod.Serialization.flagSerialize("LegendaryScoutedIDs",     legendaryStr);
            Mod.Serialization.flagSerialize("CampScoutedIDs",          campStr);
            Mod.Serialization.flagSerialize("DiscoveredLocationTypes", ::ModLocationScouting.DiscoveredLocationTypes);
            Mod.Serialization.flagSerialize("IcyCaveCleared",          ::ModLocationScouting.IcyCaveCleared);
            Mod.Serialization.flagSerialize("PresentFromStart",        ::ModLocationScouting.PresentFromStart);

            ::logInfo("[LocationScouting] onSerialize: LegendaryScoutedTiles=" + ::ModLocationScouting.LegendaryScoutedTiles.len() + " CampScoutedTiles=" + ::ModLocationScouting.CampScoutedTiles.len() + " ScoutingMode=" + ::ModLocationScouting.ScoutingMode);

            onSerialize(_out);
        }

        local onDeserialize = o.onDeserialize;
        o.onDeserialize = function(_in)
        {
            onDeserialize(_in);

            local Mod = ::ModLocationScouting.Mod;

            // Tile sets: read the comma-separated string and rebuild the
            // table-of-bools the rest of the code uses for `tileID in
            // this.X` lookups. Empty string => fresh campaign.
            local legendaryStr = Mod.Serialization.flagDeserialize("LegendaryScoutedIDs", "");
            ::ModLocationScouting.LegendaryScoutedTiles = {};
            if (legendaryStr.len() > 0)
                foreach (id in split(legendaryStr, ","))
                    ::ModLocationScouting.LegendaryScoutedTiles[id] <- true;

            local campStr = Mod.Serialization.flagDeserialize("CampScoutedIDs", "");
            ::ModLocationScouting.CampScoutedTiles = {};
            if (campStr.len() > 0)
                foreach (id in split(campStr, ","))
                    ::ModLocationScouting.CampScoutedTiles[id] <- true;

            ::ModLocationScouting.DiscoveredLocationTypes = Mod.Serialization.flagDeserialize("DiscoveredLocationTypes", {}, {});
            ::ModLocationScouting.IcyCaveCleared          = Mod.Serialization.flagDeserialize("IcyCaveCleared",          false);
            ::ModLocationScouting.PresentFromStart        = Mod.Serialization.flagDeserialize("PresentFromStart",        false);

            // ScoutingMode is intentionally NOT persisted; force Off so
            // no overlay shows without re-enabling.
            ::ModLocationScouting.ScoutingMode = ::ModLocationScouting.ScoutingModes.Off;

            ::logInfo("[LocationScouting] onDeserialize: LegendaryScoutedTiles=" + ::ModLocationScouting.LegendaryScoutedTiles.len() + " CampScoutedTiles=" + ::ModLocationScouting.CampScoutedTiles.len() + " ScoutingMode=" + ::ModLocationScouting.ScoutingMode);

            ::ModLocationScouting.resetSession();

            // Force the JS button state to Off on reload. Squirrel side
            // is already Off (above), but the JS topbar keeps whatever
            // active class was last set unless we push the new state. On
            // in-session reload paths onScreenConnected may not fire,
            // and the user sees Legendary/Camp button still highlighted.
            // WorldScreen is null on a fresh-BB-session load (screen
            // not yet connected); in that case onScreenConnected will
            // run shortly after and push Off itself.
            if (::ModLocationScouting.WorldScreen != null)
                ::ModLocationScouting.WorldScreen.m.JSHandle.asyncCall("setScoutingButtonState", [::ModLocationScouting.ScoutingMode]);
        }

        local startNewCampaign = o.startNewCampaign;
        o.startNewCampaign = function()
        {
            startNewCampaign();

            ::ModLocationScouting.TileCoords              = {};
            ::ModLocationScouting.LegendaryScoutedTiles   = {};
            ::ModLocationScouting.CampScoutedTiles        = {};
            ::ModLocationScouting.DiscoveredLocationTypes = {};
            ::ModLocationScouting.IcyCaveCleared          = false;
            ::ModLocationScouting.PresentFromStart        = true;
            ::ModLocationScouting.ScoutingMode            = ::ModLocationScouting.ScoutingModes.Off;

            ::ModLocationScouting.resetSession();
        }
    });
});
