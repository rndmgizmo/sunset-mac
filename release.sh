#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
zsh test.sh
zsh build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
if [[ "${GITHUB_REF_TYPE:-}" == tag && "${GITHUB_REF_NAME:-}" != "v$version" ]]; then
    print -u2 'Release-Tag und App-Version stimmen nicht überein.'
    exit 1
fi
architecture=$(/usr/bin/uname -m)
archive="$PWD/build/Sunset-$version-$architecture.zip"
/usr/bin/ditto -c -k --keepParent --norsrc build/Sunset.app "$archive"
(cd build; /usr/bin/shasum -a 256 "${archive:t}") > "$archive.sha256"
print -- "$archive"
