# Leaf Raker

A cozy little autumn game made for a fall game jam. Fifteen things got lost under the leaves in this forest. Grab your rake and find them all.

Look for warm light glowing up through the leaf litter, rake it away, and see what you dig up. Squirrels bury acorns everywhere (look for the little sprouts), and a thrown acorn will blow a stubborn pile sky high. Every lost thing does something, so check the tooltips in your inventory.

## Controls

| | |
|---|---|
| Move | WASD |
| Look | Mouse or arrow keys |
| Jump / Dash | Space / Shift |
| Use item | Left click or C |
| Hotbar | 1-9 or mouse wheel |
| Inventory | E or Tab |
| Drop / Pick up | Q (Ctrl+Q for the whole stack) / F |
| Fresh leaves | R |
| Pause | Esc |
| Fullscreen | F11 |

Controllers work too, laid out like most first person games: sticks walk and look, A jumps, B dashes, RT uses your item, X picks up, Y opens the inventory, LB/RB flick through the hotbar and d-pad down drops. In the inventory the left stick moves the cursor, A grabs, X splits a stack and RT quick moves. Everything except the number keys can be rebound in Options, keyboard and controller separately.

## Playing

**Windows:** run `LeafRaker-windows-x64-installer.exe` (or the arm64 one), or unzip `LeafRaker-windows-x64-portable.zip` and run `Forrest.exe` if you'd rather not install anything. Windows might say it "protected your PC". Click *More info*, then *Run anyway*.

**Linux:** unzip `LeafRaker-linux.zip` and run `sh install.sh`. It adds Leaf Raker to your app menu. `uninstall.sh` removes it again.

**macOS:** unzip `LeafRaker-macos.zip`, then right-click the app and choose *Open* the first time.

There are four save slots. Progress saves on its own when you pause, find something, or quit, and you can clear a slot from the save screen. Your best time and settings are shared across all slots.

## Building it yourself

You need Godot 4.7.1 with the export templates installed. Open the project, or run `build.bat` (or `build.sh` on Linux/macOS) to export Windows, Linux and macOS in one go. If [Inno Setup](https://jrsoftware.org/isdl.php) is installed it builds the Windows installers too. The finished downloads land in `builds/`, and the installer and Linux scripts live in `packaging/`.

## Credits

Models, sounds, music and fonts come from some very generous people. See [CREDITS.md](CREDITS.md) for the full list.

Made by Lazilydev.
