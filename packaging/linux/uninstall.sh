#!/bin/sh
APP=leaf-raker
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

rm -f "$DATA/applications/$APP.desktop" "$DATA/icons/hicolor/256x256/apps/$APP.png"
rm -rf "$DATA/$APP"

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DATA/applications" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$DATA/icons/hicolor" || true

echo "Leaf Raker uninstalled."
echo "Your settings are kept in $DATA/godot/app_userdata/Cozy Fall Jam Forrest"
