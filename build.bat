@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"

if not defined GODOT set "GODOT=%USERPROFILE%\Downloads\Utility apps\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
if not exist "%GODOT%" (
	echo Godot not found at "%GODOT%"
	echo Set it first:  set GODOT=C:\path\to\Godot_console.exe
	exit /b 1
)
if not defined ISCC set "ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"

set "OUT=builds"
set "WORK=builds\work"
set "FAILED="
set "START=%time%"
echo ============================================
echo  Leaf Raker build  -  started %START%
echo ============================================

if exist "%WORK%" rmdir /s /q "%WORK%"
if not exist "%OUT%" mkdir "%OUT%"
del /q "%OUT%\LeafRaker-*" 2>nul

echo.
echo [0/4] Importing assets...   (%time%)
"%GODOT%" --headless --path . --import 2>&1 | findstr /C:"%%" /C:"ERROR"

call :export 1 "Windows Desktop" "%WORK%\windows\Forrest.exe"
call :export 2 "Windows ARM64" "%WORK%\windows-arm64\Forrest.exe"
call :export 3 "Linux" "%WORK%\linux\Forrest.x86_64"
call :export 4 "macOS" "%OUT%\LeafRaker-macos.zip"

echo.
echo [zip] Packing portable downloads...   (%time%)
call :zip "%OUT%\LeafRaker-windows-x64-portable.zip" "'%WORK%\windows\Forrest.exe'"
call :zip "%OUT%\LeafRaker-windows-arm64-portable.zip" "'%WORK%\windows-arm64\Forrest.exe'"
call :zip "%OUT%\LeafRaker-linux.zip" "'%WORK%\linux\Forrest.x86_64','%WORK%\linux\Forrest.pck','packaging\linux\install.sh','packaging\linux\uninstall.sh','packaging\linux\leaf-raker.png'"

echo.
echo [setup] Building Windows installers...   (%time%)
if not exist "%ISCC%" (
	echo       skipped - Inno Setup not found, get it from jrsoftware.org/isdl.php
) else (
	call :setup x64 windows
	call :setup arm64 windows-arm64
)

echo.
echo ============================================
if defined FAILED (
	echo  FAILED:!FAILED!
	echo  Raw exports kept in %WORK% for checking.
	echo  started %START%   finished !time!
	echo ============================================
	exit /b 1
)
rmdir /s /q "%WORK%"
echo  All builds done. Downloads are in %OUT%\
dir /b "%OUT%\LeafRaker-*"
echo  started %START%   finished %time%
echo ============================================
exit /b 0

:export
echo.
echo [%~1/4] Exporting %~2   (%time%)
if not exist "%~dp3" mkdir "%~dp3"
"%GODOT%" --headless --path . --export-release "%~2" "%~3" 2>&1 | findstr /C:"%%" /C:"ERROR"
if exist "%~3" (
	for %%F in ("%~3") do set /a "MB=%%~zF / 1048576"
	echo       OK  !MB! MB   [!time!]
) else (
	echo       FAILED
	set "FAILED=!FAILED! %~2"
)
exit /b 0

:zip
powershell -NoProfile -Command "Compress-Archive -Path %~2 -DestinationPath '%~1' -CompressionLevel Optimal -Force" && (echo       %~nx1 OK) || (echo       %~nx1 FAILED & set "FAILED=!FAILED! %~nx1")
exit /b 0

:setup
set "SETUP=%OUT%\LeafRaker-windows-%~1-installer.exe"
echo       building LeafRaker-windows-%~1-installer.exe   (%time%)
"%ISCC%" /Qp "/DArch=%~1" "/DSrcDir=..\%WORK%\%~2" packaging\installer.iss
if exist "%SETUP%" (
	for %%F in ("%SETUP%") do set /a "MB=%%~zF / 1048576"
	echo       LeafRaker-windows-%~1-installer.exe OK  !MB! MB
) else (
	echo       LeafRaker-windows-%~1-installer.exe FAILED
	set "FAILED=!FAILED! setup-%~1"
)
exit /b 0
