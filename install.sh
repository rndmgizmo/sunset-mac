#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
if [[ "${1:-}" == --no-build ]]; then
    shift
else
    zsh test.sh
    zsh build.sh
fi
/usr/bin/python3 Tools/install.py "$@"
