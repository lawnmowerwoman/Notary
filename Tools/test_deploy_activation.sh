#!/bin/zsh --no-rcs
set -eu -o pipefail

SCRIPT="${0:A:h}/deploy.sh"
# Load only helpers and argument parsing, never deployment or Jamf operations.
source <(sed '/^if (( EUID != 0 )); then/,$d' "${SCRIPT}")
parse_args() {
  eval "$(sed -n '/^# --- Args /,/^# --- Load existing /p' "${SCRIPT}")"
}
assert_equal() {
  [[ "$1" == "$2" ]] || { print -u2 -- "FAIL: $3"; exit 1; }
}

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT
LABEL="de.twocent.notary"
STATE="${TEMP_DIR}/state.plist"
CODE="NOTXDEVMOCS2472R"
# Non-root tests exercise real plist writes; ownership is enforced by root deploy.
chown() { [[ "${2:-}" == "${TEMP_DIR}/"* ]]; }

parse_args "--activation=${CODE}"
assert_equal "${ACTIVATION_CODE}" "${CODE}" "argument parsing"
parse_args / / user "--activation=NOTX-TEST-1234"
assert_equal "${ACTIVATION_CODE}" "NOTX-TEST-1234" "Jamf positional arguments"
for invalid in '' 'NOTX bad' 'NOTX;Delete' 'NOTX"bad' $'NOTX\nBAD' "$(printf 'X%.0s' {1..129})"; do
  if (parse_args "--activation=${invalid}") >/dev/null 2>&1; then
    print -u2 -- "FAIL: invalid activation accepted"
    exit 1
  fi
done
if (parse_args --activation) >/dev/null 2>&1; then
  print -u2 -- "FAIL: missing activation value accepted"
  exit 1
fi

plist_write_state "${STATE}" id secret true true false "${CODE}"
assert_equal "$(plist_read_key "${STATE}" activationCode)" "${CODE}" "fresh state"
/usr/bin/plutil -replace apptoken -string test-token "${STATE}"
/usr/bin/plutil -replace appTokenCache -json '{"tokenVersion":7}' "${STATE}"
parse_args
plist_write_state "${STATE}" id secret true true false "${ACTIVATION_CODE}"
assert_equal "$(plist_read_key "${STATE}" activationCode)" "${CODE}" "omitted option preserves code"
plist_write_state "${STATE}" id secret true true false NOTX-REPLACED
assert_equal "$(plist_read_key "${STATE}" activationCode)" NOTX-REPLACED "explicit replacement"
assert_equal "$(plist_read_key "${STATE}" apptoken)" test-token "token preserved"
assert_equal "$(plist_read_key "${STATE}" appTokenCache:tokenVersion)" 7 "cache preserved"
assert_equal "$(plist_read_key "${STATE}" jamfClientID)" id "credentials preserved"
assert_equal "$(stat -f %Lp "${STATE}")" 600 "private permissions"
plist_write_state "${STATE}" '' '' false false true "${CODE}"
assert_equal "$(plist_read_key "${STATE}" activationCode)" "${CODE}" "explicit code with ignorelocal"
assert_equal "$(plist_read_key "${STATE}" apptoken)" '' "ignorelocal keeps reset semantics"
[[ ! -d "${STATE}.lockdir" ]] || { print -u2 -- "FAIL: lock remains"; exit 1; }
print -- "Deploy activation tests passed"
