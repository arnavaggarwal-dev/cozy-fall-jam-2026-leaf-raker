#!/bin/sh
set -u
cd "$(dirname "$0")"

GODOT="${GODOT:-$(command -v godot || command -v godot4 || echo "flatpak run org.godotengine.Godot")}"
if ! $GODOT --version >/dev/null 2>&1; then
	echo "Godot not found. Set it first:  GODOT=/path/to/godot ./build.sh"
	exit 1
fi
ISCC="${ISCC:-$HOME/.wine/drive_c/Program Files (x86)/Inno Setup 6/ISCC.exe}"

OUT=builds
WORK=builds/work
FAILED=""
START=$(date +%T)
echo "============================================"
echo " Leaf Raker build  -  started $START"
echo "============================================"

rm -rf "$WORK"
mkdir -p "$OUT"
rm -f "$OUT"/LeafRaker-*

echo
echo "[0/4] Importing assets...   ($(date +%T))"
$GODOT --headless --path . --import 2>&1 | grep -E "%|ERROR"

export_preset() {
	echo
	echo "[$1/4] Exporting $2   ($(date +%T))"
	mkdir -p "$(dirname "$3")"
	$GODOT --headless --path . --export-release "$2" "$3" 2>&1 | grep -E "%|ERROR"
	if [ -f "$3" ]; then
		echo "      OK  $(($(stat -c%s "$3") / 1048576)) MB   [$(date +%T)]"
	else
		echo "      FAILED"
		FAILED="$FAILED $2"
	fi
}

pack() {
	zip="$1"
	shift
	if zip -j -q -9 "$zip" "$@"; then
		echo "      ${zip##*/} OK"
	else
		echo "      ${zip##*/} FAILED"
		FAILED="$FAILED ${zip##*/}"
	fi
}

installer() {
	setup="$OUT/LeafRaker-windows-$1-installer.exe"
	echo "      building ${setup##*/}   ($(date +%T))"
	wine "$ISCC" /Qp "/DArch=$1" "/DSrcDir=..\\$(echo "$WORK/$2" | tr / \\\\)" "packaging\\installer.iss"
	if [ -f "$setup" ]; then
		echo "      ${setup##*/} OK  $(($(stat -c%s "$setup") / 1048576)) MB"
	else
		echo "      ${setup##*/} FAILED"
		FAILED="$FAILED setup-$1"
	fi
}

export_preset 1 "Windows Desktop" "$WORK/windows/Forrest.exe"
export_preset 2 "Windows ARM64" "$WORK/windows-arm64/Forrest.exe"
export_preset 3 "Linux" "$WORK/linux/Forrest.x86_64"
export_preset 4 "macOS" "$OUT/LeafRaker-macos.zip"

echo
echo "[zip] Packing portable downloads...   ($(date +%T))"
pack "$OUT/LeafRaker-windows-x64-portable.zip" "$WORK/windows/Forrest.exe"
pack "$OUT/LeafRaker-windows-arm64-portable.zip" "$WORK/windows-arm64/Forrest.exe"
pack "$OUT/LeafRaker-linux.zip" "$WORK/linux/Forrest.x86_64" "$WORK/linux/Forrest.pck" \
	packaging/linux/install.sh packaging/linux/uninstall.sh packaging/linux/leaf-raker.png

echo
echo "[setup] Building Windows installers...   ($(date +%T))"
if ! command -v wine >/dev/null 2>&1 || [ ! -f "$ISCC" ]; then
	echo "      skipped - needs wine + Inno Setup 6 (jrsoftware.org/isdl.php) under wine"
else
	installer x64 windows
	installer arm64 windows-arm64
fi

echo
echo "============================================"
if [ -n "$FAILED" ]; then
	echo " FAILED:$FAILED"
	echo " Raw exports kept in $WORK for checking."
	echo " started $START   finished $(date +%T)"
	echo "============================================"
	exit 1
fi
rm -rf "$WORK"
echo " All builds done. Downloads are in $OUT/"
ls -1 "$OUT" | grep '^LeafRaker-'
echo " started $START   finished $(date +%T)"
echo "============================================"
