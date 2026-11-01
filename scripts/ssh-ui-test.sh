#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
read -r simulator_runtime simulator_type < <(xcrun simctl list runtimes -j | python3 -c '
import json,sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and r.get("platform") == "iOS"]
runtime = max(runtimes, key=lambda r: tuple(map(int, r["version"].split("."))))
device = next(t for t in runtime["supportedDeviceTypes"] if t["productFamily"] == "iPhone")
print(runtime["identifier"], device["identifier"])
')
simulator_id="$(xcrun simctl create "TerminalKun2 isolated UI tests" "$simulator_type" "$simulator_runtime")"
fixture_pid=''
cleanup() {
  if [ -n "$fixture_pid" ]; then kill "$fixture_pid" 2>/dev/null || true; fi
  xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
  xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
}
trap cleanup EXIT
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b > build/logs/simulator-boot.log 2>&1
swift build --product SSHFixture --disable-automatic-resolution > build/logs/fixture-build.log 2>&1
fixture_port="$(python3 - <<'PY'
import socket
with socket.socket() as probe:
    probe.bind(('127.0.0.1', 0))
    print(probe.getsockname()[1])
PY
)"
TERMINALKUN2_FIXTURE_PORT="$fixture_port" .build/out/Products/Debug/SSHFixture build/ssh-fixture > build/logs/fixture.log 2>&1 &
fixture_pid=$!
for attempt in {1..50}; do
  if /usr/bin/nc -z 127.0.0.1 "$fixture_port" 2>/dev/null; then break; fi
  kill -0 "$fixture_pid"
  sleep 0.1
done
export TEST_RUNNER_TERMINALKUN2_SSH_UI=1
export TEST_RUNNER_TERMINALKUN2_FIXTURE_PORT="$fixture_port"
bash scripts/dev.sh ui "$simulator_id"
