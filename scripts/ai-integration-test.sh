#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
# Endpoint and model must refer to a real inference service.
: "${TERMINALKUN2_AI_TEST_ENDPOINT:?Set the actual API URL}"
: "${TERMINALKUN2_AI_TEST_MODEL:?Set an installed model name}"
python3 scripts/check-dependencies.py
swift test --disable-automatic-resolution --filter CommandTests/testLiveCommandAPI 2>&1 | tee build/logs/ai-integration.log
