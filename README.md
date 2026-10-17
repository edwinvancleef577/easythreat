# EasyThreat

**Threat bars and a combat journal for OctoWoW.**

See who has aggro and how close you or your pet are to taking it. EasyThreat adds compact bars to your existing interface and helps your group review fights together.

**Build:** `20261017-peer1` (development build) · **Author:** VanCleef

## Installation

1. Choose **Code → Download ZIP** on this repository and extract the archive.
2. Copy the enclosed **EasyThreat** folder into your game's `Interface/AddOns` directory.
3. Check that the resulting path is `Interface/AddOns/EasyThreat/EasyThreat.toc`.
4. Enable EasyThreat on the character-selection screen and enter the game.
5. Open configuration with **`/et`** or a left-click on the minimap icon.

When updating, close the game and replace the addon folder. Keep your SavedVariables to retain settings. Only the **EasyThreat** folder is required; recording is built in, so a separate `EasyThreat_Recorder` addon is unnecessary.

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
- During initial build-up, a blue bar and number show the known threat accumulated by the sole participating actor. Once another player or pet generates threat, the display changes to the combat view.
- The combat view shows proximity to taking aggro when sufficient data is available. A full challenger bar means the estimated takeover threshold has been reached; it is not a damage ranking.
- A colored border identifies the reported or observed aggro holder: green for an assigned tank, red for another role. The holder and the actor with the largest raw threat total can differ.
- Other participants use their configured player colors. **Always use player colors** can also keep your own bar and the build-up bar in those colors.
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

Use the filter buttons to select tracks, switch between the group and yourself with your pets, and drag the time-range handles to inspect part of a fight. You can save one reference fight and compare it with the latest fight. Detailed journal appearance belongs in the main configuration menu.

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

## Regression check

The included two-client regression simulates an unobserved pull, an offline roster member, a pet, an explicit threat reset and limited GUID APIs. From the repository root, install `tests/requirements.txt` and run `python tests/peer_availability.py`. These simulated checks do not replace in-game testing.

## License

See [LICENSE](LICENSE). You may use, copy, modify and share EasyThreat while retaining the notice. Use with official Blizzard-operated World of Warcraft services is not permitted; OctoWoW use is welcome. This is an independent fan project, provided without warranty. Game artwork and fonts remain the property of their respective owners.
