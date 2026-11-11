#!/bin/zsh
# Compile et lance les tests de logique (modèle, CSV, veille, rapport, plan d'exemple).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -swift-version 5 -target arm64-apple-macos14 -o build/tests \
  Sources/Model.swift Sources/Store.swift Sources/Inbox.swift Sources/L10n.swift Sources/Sample.swift Sources/Stats.swift Sources/OpenMacApps.swift Sources/Treg.swift Sources/AgentCore.swift Sources/Markdown.swift Sources/AgentRunner.swift Sources/AgentStore.swift Sources/Outreach.swift Sources/Backup.swift Sources/AssistCore.swift tests/main.swift
export HERALD_DATA_DIR="$(mktemp -d)"   # jamais le vrai plan
build/tests
rm -rf "$HERALD_DATA_DIR"
