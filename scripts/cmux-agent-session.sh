#!/usr/bin/env bash

set -euo pipefail

# Keep the shell entrypoint thin so the implementation can stay under the file-size limit.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Delegate the real logic to Python for safer JSON handling and easier cmux tree parsing.
python3 "$SCRIPT_DIR/cmux-agent-session.py" "$@"
