
**Summary**  
This mod makes it easier for you to find Legendary Locations and Camps without Cheating. If you've ever wandered the whole map looking for the Witch Hut or a Camp from a Tavern Rumor and felt like you were going in circles, this is why:  
Battle Brothers clears fog of war at a greater distance than it actually scouts for Locations. A tile can have the Fog of war completely cleared and still was not scouted close enough to reveal its location. The game never tells you this.  
This mod has the solution. It tracks every tile and only marks it as fully scouted once you've been close enough to rule out all possible location spawns. Toggle a dark overlay on the world map and you can see exactly where you still need to travel. The gaps are usually obvious once you see them.  
  
**Three Overlays**  
The mod offers three different overlays, that can be used independently of each other:  

-   A permanent overlay for Legendary Locations.
-   An overlay that shows possible locations of filtered Legendary Locations.
-   A temporary overlay for Camps. It can be reset, since new Camps can spawn at any time.  
    

The temporary one is especially useful for "Find a Location" contracts and tavern rumors. The overlays can be activated via newly added buttons on the World Map or via Keybinds.  
  
**Smart Logic**  
The mod is also somewhat smart:  

-   It knows the different Terrain Visibility Multipliers (e.g. 0.5 for Forest Tiles)
-   It knows the different Location Visibility Multipliers (e.g. 0.8 for Witch Hut)
-   It knows what kind of locations can spawn on what kind of terrain (e.g. Witch Hut only on Forests)
-   It also knows your exact Vision radius, that depends on time of day as well as Hill or Mountain positioning  
    

It uses all of this information combined to calculate how close you have to move towards a certain tile to properly scout it for any location it might contain.  
  
It also correctly marks all Tundra tiles as unscouted after you cleared Icy Cave, since you have to scout them again for Hunting Ground.  
  
**Bonus**  
For each Legendary Locations, it also tells you the terrain it can spawn on as well as distance to Civilization (minimum and maximum Tiles to closest city). This might help you to scout more efficiently.  
  
**No Cheating**  
This mod is not Cheating. The mod never gives you any hidden information. The mod only shows you the result of your own past movement, which vanilla just doesn't surface. Technically you could gather and calculate all the information yourself while you are traveling on the map. It would just be super tedious and unpractical without this mod.  
  
**A Visual Quirk: Camps Peeking Through the Overlay**  
Sometimes you will see a camp appear on a tile that the mod still considers unscouted. The black overlay on that one specific tile disappears, while all surrounding tiles stay dark. This looks like the mod is cheating by revealing a camp it should not show. It is not.  
Here is what actually happens. Battle Brothers decides on its own when a camp becomes visible, using its own vanilla visibility math. The mod has no influence on that decision. When vanilla code reveals a location, it wipes all lighting effects off that one tile to make room for the location's own visuals. The mod's overlay uses the same lighting slot, so it gets wiped along with everything else. The camp was going to be revealed either way. The mod just loses its visual cover on that single tile as a side effect.  
Only the tile directly underneath the revealed camp is affected. Neighbouring tiles stay correctly covered. No hidden information leaks through: if you played without the mod, you would see the same camp at the same moment.  
  
**Technical Background**  
It was surprisingly difficult to implement the overlays that indicate, whether a tile is scouted or not. Even support libraries such as MSU or Modern Hooks offer no real way to interact with the World Map. In the end, I had to rely on Tile Details and a Layer Type that is normally occupied by Town Lighting. The scouting is persistent and saved via MSU. It saves all scouted tiles for both the Legendary and Camp scouting layer.  
  
**Possible Problems**  

-   It might be a little bit too conservative. Certain tiles might be properly scouted, but the mod does not register it immediately.
-   It occupies the same overlay slots that the game uses for Lighting effects. This may cause Settlement Lighting to not display correctly on the world map.
-   It might cause performance issues, since it does some calculation every time you move 50px.
-   It can also significantly increase time to start a new campaign, since the mods needs to initialize a lot of tile overlays at start.
-   It was only tested on brand-new campaigns. Adding this mid-campaign was not properly tested. So use at your own risk.
-   If Deserialization and Saving does not properly work, this Mod could in theory ruin your whole run. It has the potential to overlay all map tiles with Black Overlays, making it impossible for you to see anything anymore. So again, use at your own risk.
-   Cross-testing with other mods was not tested. But the author knows of no other mods, that also manipulate the World Map with overlays. So in theory, there should be no cross-mod incompatibilities.
-   The author greatly appreciates feedback as well as bug reports, that include the log file (e.g. in C:\Users\<USER>\Documents\Battle Brothers\log.html). But no personal support can be given.  
    

**Requires**  

-   Modern Hooks
-   MSU  
    

**Controls**  

-   Ctrl+L for Legendary Locations scouting overlay
-   Ctrl+E for Enemy Camps scouting overlay
-   Ctrl+R for Resetting Enemy Camps overlay  
    

All controls rely on MSU keybind, so the keybinds can be changed. And all controls are available as Buttons on the world map.  
  
  
**How to install and use**  

-   Drop mod_location_scouting.zip into your Battle Brothers data/ folder (e.g. "C:\Program Files (x86)\Steam\steamapps\common\Battle Brothers\data")
-   Do the same for the Mods MSU (https://www.nexusmods.com/battlebrothers/mods/479) and Modern Hooks (https://www.nexusmods.com/battlebrothers/mods/685)
-   Launch the game and load your campaign
-   Press Ctrl+L on the world map to see the overlay

**Building a release zip**

-   Run `yarn build`
-   This calls `package.sh` and writes `dist/mod_location_scouting.zip`
-   The zip contains the contents of `src/` at archive root, which is the layout Battle Brothers expects inside `data/`
