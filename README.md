# EasyThreat

**Threat bars and a combat journal for OctoWoW.**

See who has aggro and how close you or your pet are to taking it. EasyThreat adds compact bars to your existing interface and helps your group review fights together.

**Build:** `20261018-colors1` (development build) · **Author:** VanCleef

## Installation

### OctoWoW Launcher

Add this Git URL in the launcher's addon manager:

`https://github.com/edwinvancleef577/EasyThreat.git`

Use the capitalization shown above, especially on case-sensitive systems. The repository root contains `EasyThreat.toc`, Lua files and `Media/`, so the launcher can clone and update it directly.

If an earlier attempt shows **Failed to install**, close the game, back up your existing addon folder outside `Interface/AddOns`, remove the failed entry in the launcher and add the URL again. Keep the game's `WTF` folder / SavedVariables; they contain your settings. A manually installed copy may need the same one-time replacement before the launcher can manage it.

### Manual ZIP installation

1. Choose **Code → Download ZIP** and extract the archive.
2. Rename the extracted repository folder (for example `easythreat-main`) to **EasyThreat**.
3. Copy that folder into your game's `Interface/AddOns` directory.
4. Check that the resulting path is `Interface/AddOns/EasyThreat/EasyThreat.toc`, with no extra nested `EasyThreat` folder.
5. Enable EasyThreat on the character-selection screen, then open settings with **`/et`** or the minimap icon.

When updating manually, close the game and replace the addon folder. Keep your SavedVariables to retain settings. Recording is built in; a separate `EasyThreat_Recorder` addon is unnecessary.

## Group-value fix

Update all group members to this build together. Missing observations on another client no longer hide independently calculated local threat. Explicitly invalidated calculations remain unavailable. Diagnostics distinguishes those cases; replies also use matching unit tokens when raw GUID combat queries are unsupported. Older builds cannot read the extended value replies.

## Quick start

1. **Assign roles.** Choose Tank, Damage or Healer for each player, and assign pet roles separately. Your own role is marked in the display table.
2. **Choose displays.** Under **Displays**, enable the mouse tooltip, target frame, nameplates and/or enemy list for your role. These choices apply to your character's view.
3. **Choose extra bars.** **Other players/pets** allows 1–4 additional participants, with a default of **3**. Your own character and your own pet do not count toward this limit. Existing saved choices are preserved when updating.
4. **Check filters.** Under **Enemy filters**, choose solo, party or raid play, enemy difficulty and enemy type. Enable Solo if you want filtered displays while playing alone.
5. **Position the UI.** Use **Positions → Preview** outside combat. Enable **Allow dragging** and drag the gold handles to move the enemy list or target bars.

The initial threat threshold is **0%**. A higher threshold reduces clutter on filtered displays; the combat target frame has its own always-visible behavior.

## Reading the bars

- Your bar stays at the top, with your own living pet directly below it. Other participants appear underneath, ordered by their available threat values.
- During initial build-up, a number shows the known threat accumulated by the sole participating actor. Your own build-up bar is blue; other players and pets keep their identity colors. Once another player or pet generates threat, the display changes to the combat view.
- The combat view shows proximity to taking aggro when sufficient data is available. A full challenger bar means the estimated takeover threshold has been reached; it is not a damage ranking.
- A colored border identifies the reported or observed aggro holder: green for an assigned tank, red for another role. The holder and the actor with the largest raw threat total can differ.
- Only your own bar changes its fill color with threat state. Other players keep their configured player colors, including during build-up and fleeing. Pets automatically get a distinct hue instead of copying their owner; a saved pet color takes priority. Under **Player colors**, use the group-member button to select a pet and customize its color. These identities also apply to the enemy list and journal. **Always use player colors** additionally keeps your own bar in its identity color.
- Missing measurements are not measured zeroes. Where possible, the last value remains faded until current data is available. An enemy's observed target can also be a temporary spell target.

## Tooltips and spacing

Under **Positions → Mouse tooltip**:

- **Always show** keeps eligible enemy tooltip bars visible outside combat with empty fills and a quiet "No aggro" label.
- **Dynamic width** follows the tooltip's final width, including changes made by EasyCast. The pet icon stays inside the tooltip beside a shorter, right-aligned pet bar.
- **Spacing → Pet gap** adjusts the space above your pet.
- **Spacing → Gap to other players** separates your player/pet block from other participants. The default is 6; further comparison rows remain compact.

**Positions → Target frame → Spacing** provides separate pet and other-player gaps, plus X/Y positioning. Tooltip and target-frame spacing are independent. Nameplate bars require a visible, identifiable enemy nameplate.

## Combat journal

Click the book icon, or right-click the minimap icon, to open the journal. It offers enemy threat tracks, resource availability and consumption, healing and damage, with a shared time cursor and a readable event log.

**Group** is the default view. This update switches existing journals to Group once; subsequent choices are remembered. Use the filter buttons to select tracks, switch between the group and yourself with your pets, and drag the time-range handles to inspect part of a fight. You can save one reference fight and compare it with the latest fight. Detailed journal appearance belongs in the main configuration menu.

The journal is intended for understanding group play, not assigning a performance score. Its data-quality indicator explains missing observations and estimates. Resource loss can be affected by regeneration; observed enemy targets and healing estimates are not complete server records.

## Compatibility and data quality

EasyThreat targets OctoWoW's Vanilla-style interface (`11200`). It is designed to fit alongside DragonForgeUI and EasyCast. **SuperWoW and ClassicAPI are optional**, detected when available. No additional DLL is required to load the addon.

Threat data may come from supported client APIs, server replies, local combat-event calculations and other EasyThreat users. Available sources depend on the client and server. Local formulas cannot guarantee exact results for every spell, talent or custom balance change. No server response does not prevent local calculation.

For group exchange, use the same build on every player's client. Exchange and recording sharing are enabled by default; their controls are in **Diagnostics**. Recorded coverage can be incomplete when another player is offline, out of observation range or using a different build. The journal does not turn received recordings into a guaranteed complete group combat log.

This is a development build. Automated checks cover display rules, pets, settings, source handling and tooltip layouts; compatibility with every client modification and addon combination is not guaranteed.

## Diagnostics

Open **Diagnostics** in the configuration menu for source status, compatibility information, recording controls and settings export/import.

For a short source test:

1. Enter **`/et test start`**, select an enemy before attacking and play normally for about two minutes.
2. Enter **`/et test show`** after completion and copy the report. **`/et test stop`** ends the test early.
3. Report the build, client version, relevant addons, expected behavior and what actually happened.

The source test reports actual requests and replies separately and does not change your roles or display settings. Zero shield events are normal without an active damage shield. A numeric difference between local and server observations can reflect timing rather than a faulty formula.

**Review exports before sharing.** Settings and journal data can contain character names and other group information. Do not upload your entire account folder or private diagnostics to a public issue. Regular SavedVariables are written when the UI reloads or the game exits normally; a displayed save path alone does not mean a new file has already been written.

## License

See [LICENSE](LICENSE). You may use, copy, modify and share EasyThreat while retaining the notice. Use with official Blizzard-operated World of Warcraft services is not permitted; OctoWoW use is welcome. This is an independent fan project, provided without warranty. Game artwork and fonts remain the property of their respective owners.
