#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
/usr/bin/swiftc -module-cache-path /tmp/sunset-swift-module-cache \
    Sources/LampProtocol.swift Sources/ConnectionTiming.swift Sources/TerminationPolicy.swift \
    Tests/main.swift -o build/SunsetTests
build/SunsetTests
/usr/bin/python3 -c 'import ast, pathlib; ast.parse(pathlib.Path("Tools/install.py").read_text())'
/bin/zsh -n build.sh install.sh update.sh release.sh
