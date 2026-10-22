#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/build/Sunset.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
/usr/bin/swiftc -O -module-cache-path /tmp/sunset-swift-module-cache \
    Sources/LampProtocol.swift Sources/ConnectionTiming.swift Sources/TerminationPolicy.swift Sources/BluetoothLamp.swift Sources/LampWindowController.swift Sources/main.swift \
    -framework AppKit -framework CoreBluetooth -o "$APP/Contents/MacOS/Sunset"
/usr/bin/swift -module-cache-path /tmp/sunset-swift-module-cache Assets/generate-icon.swift "$PWD/build/Sunset.iconset"
/usr/bin/iconutil -c icns "$PWD/build/Sunset.iconset" -o "$APP/Contents/Resources/Sunset.icns"
/usr/bin/xattr -cr "$APP"
/usr/bin/codesign --force --sign - "$APP"
echo "$APP"
