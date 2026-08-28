#!/bin/sh
# Compatibility wrapper; the dependency-free generator lives in Python.
exec "$(dirname "$0")/generate-karabiner" "$@"
