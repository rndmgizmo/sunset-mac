#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
[[ -z "$(git status --porcelain)" ]] || { print -u2 'Lokale Änderungen vorhanden. Bitte zuerst committen oder sichern.'; exit 1; }
[[ "$(git branch --show-current)" == main ]] || { print -u2 'Updates werden nur auf main installiert.'; exit 1; }
git pull --ff-only origin main
zsh install.sh
