#!/usr/bin/env bash
# Builds dist/RedGuildForever.zip with only the files the game needs.
set -euo pipefail
cd "$(dirname "$0")"

lua5.1 tests/run.lua

rm -rf dist
mkdir -p dist/RedGuildForever
cp RedGuildForever.toc ./*.lua README.md CHANGELOG.md dist/RedGuildForever/
(cd dist && zip -qr RedGuildForever.zip RedGuildForever)
echo "built dist/RedGuildForever.zip"
