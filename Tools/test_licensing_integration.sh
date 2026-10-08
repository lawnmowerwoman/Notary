#!/bin/zsh --no-rcs
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT_DIR}"
TEST_CONTAINER="notary-licensing-test-$$"
TEST_ADMIN_TOKEN="$(uuidgen)"
# This public fixture seed matches LicensingTests.swift, never a production key.
TEST_SIGNING_KEY="AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA"
trap 'docker rm -f -v "${TEST_CONTAINER}" >/dev/null 2>&1 || true' EXIT
docker run -d --platform linux/amd64 --name "${TEST_CONTAINER}" \
  -p 127.0.0.1::8080 \
  -e "LICENSING_ADMIN_BEARER_TOKEN=${TEST_ADMIN_TOKEN}" \
  -e LICENSING_SIGNING_KEY_ID=licensing-test \
  -e "LICENSING_SIGNING_PRIVATE_KEY=${TEST_SIGNING_KEY}" \
  ministry/licensingservice:0B1 >/dev/null
TEST_PORT="$(docker inspect "${TEST_CONTAINER}" --format '{{(index (index .NetworkSettings.Ports "8080/tcp") 0).HostPort}}')"
for attempt in {1..30}; do
  if curl --silent --fail "http://127.0.0.1:${TEST_PORT}/api/v1/health" >/dev/null; then break; fi
  sleep 0.2
done
NOTARY_LICENSING_TEST_SERVER="http://127.0.0.1:${TEST_PORT}" \
NOTARY_LICENSING_TEST_ADMIN_TOKEN="${TEST_ADMIN_TOKEN}" swift run transport-tests
