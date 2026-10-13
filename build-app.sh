#!/bin/sh
set -eu
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    export DEVELOPER_DIR
fi
DERIVED_DATA=".build/XcodeDerivedData"
xcodebuild -project Air7Menu.xcodeproj -scheme Air7Menu -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" build
BUILT_APP="$DERIVED_DATA/Build/Products/Debug/Air7Menu.app"
APP="Air 7 Menu.app"
rm -rf "$APP"
ditto "$BUILT_APP" "$APP"
codesign --force --deep --sign - "$APP"
open "$APP"
echo "Launched $APP"
