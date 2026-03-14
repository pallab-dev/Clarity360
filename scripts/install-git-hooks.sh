#!/bin/sh

set -eu

git config core.hooksPath .githooks
chmod +x .githooks/pre-push

echo "Configured Git hooks from .githooks."
echo "Direct pushes to release/* and production will now be blocked locally."
