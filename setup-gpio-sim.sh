#!/usr/bin/env bash
# Deprecated: gpio-sim is not used in this kit.
# Redirects to gpio-mockup for one release so old docs keep working.
set -euo pipefail
echo "note: gpio-sim is disabled; using gpio-mockup instead." >&2
exec "$(cd "$(dirname "$0")" && pwd)/setup-gpio-mockup.sh" "$@"
