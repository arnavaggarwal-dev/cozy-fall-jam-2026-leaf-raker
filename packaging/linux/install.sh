#!/bin/sh
set -e
cd "$(dirname "$0")"

APP=leaf-raker
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
HOME_DIR="$DATA/$APP"

for f in Forrest.x86_64 Forrest.pck uninstall.sh leaf-raker.png; do
	if [ ! -f "$f" ]; then
		echo "Missing $f here. Unzip a fresh download and run install.sh from there."
		exit 1
	fi
done

if [ -d "$HOME_DIR" ]; then
	if [ "$(cd "$HOME_DIR" && pwd)" = "$(pwd)" ]; then
		echo "Run install.sh from the downloaded folder, not from the installed one."
		exit 1
	fi
	echo "Replacing the existing Leaf Raker install..."
	rm -rf "$HOME_DIR"
fi

mkdir -p "$HOME_DIR" "$DATA/applications" "$DATA/icons/hicolor/256x256/apps"
mv Forrest.x86_64 Forrest.pck uninstall.sh "$HOME_DIR/"
chmod +x "$HOME_DIR/Forrest.x86_64"
mv -f leaf-raker.png "$DATA/icons/hicolor/256x256/apps/$APP.png"

cat > "$DATA/applications/$APP.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Leaf Raker
Comment=Rake the autumn forest and find the 15 lost things
Exec="$HOME_DIR/Forrest.x86_64"
Path=$HOME_DIR
Icon=$APP
Terminal=false
Categories=Game;
EOF

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DATA/applications" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$DATA/icons/hicolor" || true

echo "Leaf Raker installed. Look for it in your app menu."
echo "To remove it later: sh \"$HOME_DIR/uninstall.sh\""
echo "This folder is now empty apart from install.sh, you can delete it."
