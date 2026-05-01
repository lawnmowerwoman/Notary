#!/bin/zsh --no-rcs
# ==============================================================================
#  Notary – DEPLOY / BOOTSTRAP (v2.0)
#  - writes /var/db/notary.plist (Jamf API credentials + flags)
#  - creates/updates LaunchDaemon de.twocent.notary
#  - ensures Jamf EAs exist:
#      UPDATE=true  -> TEXT EAs (runner updates via API)
#      UPDATE=false -> SCRIPT EAs (Jamf recon reads from twccr.plist)
# ==============================================================================

VERSION="2.1.1"
echo "Deploy Notary – v${VERSION}"

emulate -L zsh
set -o errexit -o pipefail -o nounset
IFS=$'\n\t'

log() { print -r -- "[$(date +%F' '%T)] $*"; }

plist_read_key() {
  local plist_path="$1"
  local plist_key="$2"
  if [[ ! -f "${plist_path}" ]]; then
    return 0
  fi

  /usr/libexec/PlistBuddy -c "Print :${plist_key}" "${plist_path}" 2>/dev/null || true
}

plist_write_state() {
  local plist_path="$1"
  local jamf_client_id="$2"
  local jamf_client_secret="$3"
  local api_update="$4"
  local ignore_local="$5"
  local plist_dir lock_dir tmp_path attempts=0
  local retry_round=1 max_rounds=3 max_attempts=100 stale_after=30 lock_mtime=0 now=0

  plist_dir="$(dirname "${plist_path}")"
  lock_dir="${plist_path}.lockdir"
  mkdir -p "${plist_dir}"
  rm -f "${plist_dir}/.${LABEL}.state.XXXXXX.plist" 2>/dev/null || true

  # The deploy script may overlap with runner-side state access on some hosts.
  # Use a simple lock directory so we never update /var/db/notary.plist concurrently.
  # Retry a few times and clear stale locks from interrupted runs.
  while (( retry_round <= max_rounds )); do
    attempts=0
    until mkdir "${lock_dir}" 2>/dev/null; do
      attempts=$(( attempts + 1 ))

      if [[ -d "${lock_dir}" ]]; then
        lock_mtime="$(stat -f %m "${lock_dir}" 2>/dev/null || echo 0)"
        now="$(date +%s)"
        if [[ "${lock_mtime}" =~ '^[0-9]+$' ]] && (( now - lock_mtime > stale_after )); then
          log "WARN: removing stale plist lock for ${plist_path}"
          rmdir "${lock_dir}" 2>/dev/null || true
          continue
        fi
      fi

      if (( attempts >= max_attempts )); then
        break
      fi
      sleep 0.1
    done

    if [[ -d "${lock_dir}" ]]; then
      break
    fi

    if (( retry_round < max_rounds )); then
      log "WARN: plist lock busy for ${plist_path}; retrying (${retry_round}/${max_rounds})"
      sleep "${retry_round}"
    fi
    retry_round=$(( retry_round + 1 ))
  done

  if [[ ! -d "${lock_dir}" ]]; then
    log "ERROR: could not acquire plist lock for ${plist_path}"
    return 1
  fi

  # BSD mktemp requires the XXXXXX pattern at the end of the template path.
  tmp_path="$(mktemp "${plist_dir}/.${LABEL}.state.XXXXXX")"
  {
    # Preserve unrelated keys in notary.plist while only refreshing the values
    # that belong to deployment state and Jamf API bootstrap.
    if [[ "${ignore_local:l}" == "true" ]]; then
      /usr/bin/plutil -create binary1 "${tmp_path}"
    elif [[ -f "${plist_path}" ]]; then
      # Copy raw bytes only. This avoids cp/copyfile metadata handling, which
      # has shown sporadic EPERM failures on some clients under Jamf.
      if ! /bin/cat "${plist_path}" > "${tmp_path}"; then
        log "WARN: existing ${plist_path} could not be read; recreating local state"
        /usr/bin/plutil -create binary1 "${tmp_path}"
      fi
    else
      /usr/bin/plutil -create binary1 "${tmp_path}"
    fi

    if [[ -n "${jamf_client_id}" ]]; then
      /usr/libexec/PlistBuddy -c "Delete :jamfClientID" "${tmp_path}" >/dev/null 2>&1 || true
      /usr/libexec/PlistBuddy -c "Add :jamfClientID string ${jamf_client_id}" "${tmp_path}"
    fi

    if [[ -n "${jamf_client_secret}" ]]; then
      /usr/libexec/PlistBuddy -c "Delete :jamfClientSecret" "${tmp_path}" >/dev/null 2>&1 || true
      /usr/libexec/PlistBuddy -c "Add :jamfClientSecret string ${jamf_client_secret}" "${tmp_path}"
    fi

    /usr/libexec/PlistBuddy -c "Delete :apiupdate" "${tmp_path}" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :apiupdate bool ${api_update:l}" "${tmp_path}"

    # Write permissions before the final move so the on-disk plist remains root-only.
    chmod 600 "${tmp_path}" || true
    chown root:wheel "${tmp_path}" || true

    # Replace the plist atomically to avoid truncated or partially rewritten files.
    mv -f "${tmp_path}" "${plist_path}"
    chmod 600 "${plist_path}" || true
    chown root:wheel "${plist_path}" || true
  } always {
    rm -f "${tmp_path}" 2>/dev/null || true
    rmdir "${lock_dir}" 2>/dev/null || true
  }
}

if (( EUID != 0 )); then
  log "ERROR: must run as root"
  exit 9
fi

# cleanup (Beta)
if [[ -f /Library/LaunchDaemons/de.apfelwerk.harden.plist ]]; then
    launchctl bootout system /Library/LaunchDaemons/de.apfelwerk.harden.plist || true
    rm -f /Library/LaunchDaemons/de.apfelwerk.harden.plist
fi
if [[ -f /Library/LaunchDaemons/de.twocent.compliance.plist ]]; then
    launchctl bootout system /Library/LaunchDaemons/de.twocent.compliance.plist || true
    rm -f /Library/LaunchDaemons/de.twocent.compliance.plist
fi
if [[ -f /usr/local/sbin/harden.sh ]]; then
    rm -f /usr/local/sbin/harden.sh
fi
if [[ -f /usr/local/sbin/ComplianceRunner ]]; then
    rm -f /usr/local/sbin/ComplianceRunner
fi
if [[ -f /usr/local/sbin/notary ]]; then
    # Legacy service location before the planned move to /usr/local/libexec/notary.
    rm -f /usr/local/sbin/notary
fi
if [[ -f /var/db/awxcr.plist ]]; then
    rm -f /var/db/awxcr.plist
fi
if [[ -f /var/db/twccr.plist ]]; then
    rm -f /var/db/twccr.plist
fi

# --- Paths / IDs ---------------------------------------------------------------
LABEL="de.twocent.notary"
DAEMON="/Library/LaunchDaemons/${LABEL}.plist"

BIN="/usr/local/libexec/notary"
MGMT_DIR="/Library/Management"
LOG_DIR="${MGMT_DIR}/Logs"

STORAGE="/var/db/notary.plist"

# --- Args ----------------------------------------------------------------------
CLIENT_ID=""
CLIENT_SECRET=""
UPDATE=true
INTERVAL="3600"
DAILY_TIME=""
IGNORE_LOCAL=false

for arg in "$@"; do
  case "$arg" in
    --client=*|-c=*)    CLIENT_ID="${arg#*=}" ;;
    --secret=*|-s=*)    CLIENT_SECRET="${arg#*=}" ;;
    --noupdate|--no-update) UPDATE=false ;;
    --update|-u)        UPDATE=true ;;
    --interval=*|-i=*)  INTERVAL="${arg#*=}" ;;
    --daily=*)          DAILY_TIME="${arg#*=}" ;;
    --ignorelocal|--ignore-local) IGNORE_LOCAL=true ;;
    *) ;;
  esac
done

# --- Load existing creds from storage if present -------------------------------
existing_id=""; existing_secret=""
if [[ "${IGNORE_LOCAL:l}" != "true" && -f "${STORAGE}" ]]; then
  existing_id="$(plist_read_key "${STORAGE}" "jamfClientID")"
  existing_secret="$(plist_read_key "${STORAGE}" "jamfClientSecret")"
fi

# 2a) Fill missing credentials from stored state so routine updates do not need
# to resend both secrets on every deploy run.
if [[ -z "${CLIENT_ID}" && -n "${existing_id}" ]]; then
  CLIENT_ID="${existing_id}"
fi
if [[ -z "${CLIENT_SECRET}" && -n "${existing_secret}" ]]; then
  CLIENT_SECRET="${existing_secret}"
fi
if [[ "${CLIENT_ID}" == "${existing_id}" && "${CLIENT_SECRET}" == "${existing_secret}" && -n "${existing_id}" && -n "${existing_secret}" ]]; then
  log "INFO: Using stored Jamf API credentials from ${STORAGE}"
fi

# 2b) If creds passed but storage already has creds -> log update notice
if [[ -n "${CLIENT_ID}" && -n "${CLIENT_SECRET}" && -n "${existing_id}" && -n "${existing_secret}" ]]; then
  if [[ "${CLIENT_ID}" != "${existing_id}" ]]; then
    log "INFO: Credentials passed; updating stored jamfClientID in ${STORAGE}"
  else
    log "INFO: Credentials passed; updating stored jamfClientSecret in ${STORAGE} (id unchanged)"
  fi
fi

# If still missing, we can continue (daemon may still run; EA ensure will be skipped)
haveCreds=1
if [[ -z "${CLIENT_ID}" || -z "${CLIENT_SECRET}" ]]; then
  haveCreds=0
  log "WARN: Jamf API credentials missing (EA ensure will be skipped). Pass --client= --secret= or pre-provision ${STORAGE}."
fi

if [[ -n "${DAILY_TIME}" && ! "${DAILY_TIME}" =~ '^[0-2][0-9]:[0-5][0-9]$' ]]; then
  log "ERROR: --daily must be HH:MM"
  exit 3
fi
if [[ -z "${INTERVAL}" || ! "${INTERVAL}" =~ '^[0-9]+$' ]]; then
  log "ERROR: --interval must be integer seconds"
  exit 4
fi

# --- Jamf Pro URL (from client) ------------------------------------------------
jamfProURL=$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url 2>/dev/null || echo "")
jamfProURL="${jamfProURL%/}"
if [[ -z "${jamfProURL}" ]]; then
  log "ERROR: Jamf URL not found on client"
  exit 5
fi
log "Jamf Pro URL: ${jamfProURL}"

# --- Ensure dirs ---------------------------------------------------------------
mkdir -p "${LOG_DIR}"
chown root:wheel "${MGMT_DIR}" "${LOG_DIR}" || true
chmod 755 "${MGMT_DIR}" "${LOG_DIR}" || true

# --- Stop existing daemon if present ------------------------------------------
if /bin/launchctl print "system/${LABEL}" >/dev/null 2>&1; then
  /bin/launchctl bootout system "${DAEMON}" 2>/dev/null || true
  log "LaunchDaemon stopped"
fi

# --- Persist credentials (only if we have them) --------------------------------
# These keys must match RunnerState / ManagedConfig loading.
# (No backward compatibility needed, per your note.)
if (( haveCreds == 1 )); then
  plist_write_state "${STORAGE}" "${CLIENT_ID}" "${CLIENT_SECRET}" "${UPDATE}" "${IGNORE_LOCAL}"
else
  plist_write_state "${STORAGE}" "" "" "${UPDATE}" "${IGNORE_LOCAL}"
fi
log "Wrote state to ${STORAGE} (apiupdate=${UPDATE})"

# --- HTTP helpers (for EA creation) -------------------------------------------
CURL_STATUS=""; CURL_BODY=""; CURL_ERROR="0"

http_status_msg() {
  local code="${1:-000}"
  case "$code" in
    200|201|204) echo "OK";;
    400) echo "Bad Request";;
    401) echo "Unauthorized";;
    403) echo "Forbidden";;
    404) echo "Not Found";;
    409) echo "Conflict";;
    500) echo "Server Error";;
    502) echo "Bad Gateway";;
    503) echo "Service Unavailable";;
    504) echo "Gateway Timeout";;
    *) echo "HTTP $code";;
  esac
}

_redact_args() {
  local out=() a
  for a in "$@"; do
    case "$a" in
      Authorization:*|authorization:*) out+=("Authorization: Bearer ***") ;;
      *) out+=("$a") ;;
    esac
  done
  print -r -- "${out[@]}"
}

http_request() {
  local url="$1" method="$2" data="${3:-}"
  shift 3 || true

  local safe; safe=$(_redact_args "$@")
  log "HTTP ${method} ${url} ${safe}"

  local response exitcode
  local curl_common=(-sS --connect-timeout 10 --max-time 30 --retry 2 --retry-delay 2 --retry-all-errors)

  if [[ -n "$data" ]]; then
    response=$(curl "${curl_common[@]}" -w $'\n%{http_code}' -X "$method" "$@" -d "$data" "$url" 2>&1); exitcode=$?
  else
    response=$(curl "${curl_common[@]}" -w $'\n%{http_code}' -X "$method" "$@" "$url" 2>&1); exitcode=$?
  fi

  if (( exitcode != 0 )); then
    CURL_STATUS="000"; CURL_BODY=""; CURL_ERROR="$exitcode"; return $exitcode
  fi

  CURL_STATUS=$(printf '%s\n' "$response" | tail -n1)
  CURL_BODY=$(printf '%s\n' "$response" | sed '$d')
  CURL_ERROR="0"
  return 0
}

json_get() {
  # json_get "<json>" "<key>"
  # prefers jq, falls back to python3
  local json="$1" key="$2"
  if command -v jq >/dev/null 2>&1; then
    print -r -- "$json" | jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null || true
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$key" <<'PY' 2>/dev/null || true
import json,sys
k=sys.argv[1]
data=sys.stdin.read()
try:
  obj=json.loads(data)
  v=obj.get(k,"")
  if v is None: v=""
  print(v)
except Exception:
  pass
PY
    return 0
  fi
  return 0
}

BearerToken=""

getBearerToken() {
  local form="grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}"
  http_request "${jamfProURL}/api/oauth/token" "POST" "$form" -H "Content-Type: application/x-www-form-urlencoded"
  [[ "$CURL_STATUS" =~ ^20[0-4]$ ]] || { log "ERROR OAuth token: $(http_status_msg "$CURL_STATUS")"; return 1; }

  BearerToken="$(json_get "$CURL_BODY" "access_token")"
  [[ -n "${BearerToken}" ]] || { log "ERROR Token parse failed"; return 1; }
  return 0
}

invalidateToken() {
  [[ -z "${BearerToken}" ]] && return 0
  http_request "${jamfProURL}/api/v1/auth/invalidate-token" "POST" "" -H "Authorization: Bearer ${BearerToken}"
  log "Invalidate token: $(http_status_msg "$CURL_STATUS")"
  BearerToken=""
  return 0
}

# --- EA creation ---------------------------------------------------------------
EA_NAMES=("Notary Runner" "Notary Issues" "Notary Compliance")

ensure_extension_attributes() {
  getBearerToken || { log "ERROR: cannot get bearer token"; return 1; }

  # list all EA names via paging
  local page=0 page_size=200
  typeset -A present; present=()

  while :; do
    http_request "${jamfProURL}/api/v1/computer-extension-attributes?page=${page}&page-size=${page_size}&sort=name.asc" "GET" "" \
      -H "Accept: application/json" -H "Authorization: Bearer ${BearerToken}"
    [[ "$CURL_STATUS" =~ ^20[0-4]$ ]] || { log "ERROR EA list: $(http_status_msg "$CURL_STATUS")"; break; }

    if command -v jq >/dev/null 2>&1; then
      printf '%s' "$CURL_BODY" | jq -r '.results[]?.name' | while IFS= read -r n; do
        [[ -n "$n" ]] && present["$n"]=1
      done
      local got; got=$(printf '%s' "$CURL_BODY" | jq -r '.results | length' 2>/dev/null || echo 0)
      if (( got < page_size )); then break; else (( ++page )); fi
    else
      # python fallback: just detect end via results count
      if ! command -v python3 >/dev/null 2>&1; then
        log "WARN: neither jq nor python3 available; cannot ensure EA creation"
        break
      fi
      local out; out=$(python3 - <<'PY' <<EOF 2>/dev/null || true
import json,sys
data=sys.stdin.read()
try:
  obj=json.loads(data)
  res=obj.get("results",[])
  for r in res:
    n=r.get("name","")
    if n: print(n)
  print("__COUNT__="+str(len(res)))
except Exception:
  print("__COUNT__=0")
PY
EOF
)
      # parse names
      local count=0
      while IFS= read -r line; do
        if [[ "$line" == __COUNT__=* ]]; then
          count="${line#__COUNT__=}"
        elif [[ -n "$line" ]]; then
          present["$line"]=1
        fi
      done <<< "$out"

      if (( count < page_size )); then break; else (( ++page )); fi
    fi
  done

  # create missing
  local name payload
  for name in "${EA_NAMES[@]}"; do
    if [[ -n "${present["$name"]:-}" ]]; then
      log "EA exists: $name"
      continue
    fi

    log "Creating missing EA: $name"

    if [[ "${UPDATE}" == true ]]; then
      # runner updates via API -> TEXT EA
      if command -v jq >/dev/null 2>&1; then
        payload=$(jq -n --arg n "$name" --arg d "Created by Notary deploy script v2.0" \
          '{name:$n, description:$d, dataType:"STRING", enabled:true, inventoryDisplayType:"GENERAL", inputType:"TEXT"}')
      else
        payload=$(python3 - <<PY
import json
print(json.dumps({
  "name": "$name",
  "description": "Created by Notary deploy script v2.0",
  "dataType": "STRING",
  "enabled": True,
  "inventoryDisplayType": "GENERAL",
  "inputType": "TEXT"
}))
PY
)
      fi
    else
      # recon mode -> SCRIPT EA reading from notary.plist
      local ea
      ea="echo \"<result>\$(/usr/bin/defaults read ${STORAGE} \\\"${name}\\\" 2>/dev/null)</result>\""
      if command -v jq >/dev/null 2>&1; then
        payload=$(jq -n --arg n "$name" --arg d "Created by Notary deploy script v2.0 (recon mode)" --arg e "$ea" \
          '{name:$n, description:$d, dataType:"STRING", enabled:true, inventoryDisplayType:"GENERAL", inputType:"SCRIPT", scriptContents:$e}')
      else
        payload=$(python3 - <<PY
import json
print(json.dumps({
  "name": "$name",
  "description": "Created by Notary deploy script v2.0 (recon mode)",
  "dataType": "STRING",
  "enabled": True,
  "inventoryDisplayType": "GENERAL",
  "inputType": "SCRIPT",
  "scriptContents": "$ea"
}))
PY
)
      fi
    fi

    http_request "${jamfProURL}/api/v1/computer-extension-attributes" "POST" "${payload}" \
      -H "Content-Type: application/json" -H "Authorization: Bearer ${BearerToken}"

    [[ "$CURL_STATUS" =~ ^20[0-4]$ ]] || { log "ERROR create EA '$name': $(http_status_msg "$CURL_STATUS")"; invalidateToken; return 1; }
    log "EA created: $name"
  done

  invalidateToken
  return 0
}

# --- LaunchDaemon --------------------------------------------------------------
write_daemon() {
  if [[ -n "${DAILY_TIME}" ]]; then
    log "WARN: --daily is ignored in engagement mode; using continuous daemon with internal interval control"
  fi

  tee "${DAEMON}" >/dev/null <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${BIN}</string>
    <string>--engagement</string>
    <string>--engagement-interval</string>
    <string>${INTERVAL}</string>
  </array>
  <key>KeepAlive</key><true/>
  <key>RunAtLoad</key><true/>
  <key>ExitTimeOut</key><integer>15</integer>
  <key>StandardOutPath</key><string>${LOG_DIR}/notary.stdout.log</string>
  <key>StandardErrorPath</key><string>${LOG_DIR}/notary.stderr.log</string>
</dict></plist>
PLIST
  chown root:wheel "${DAEMON}"
  chmod 644 "${DAEMON}"
  log "Wrote ${DAEMON}"
}

random_api_delay() {
  local delay=$(( RANDOM % 6 ))
  if (( delay > 0 )); then
    log "INFO: Random API delay before Jamf calls: ${delay}s"
    /bin/sleep "${delay}"
  else
    log "INFO: Random API delay before Jamf calls: 0s"
  fi
}

# --- Bootstrap order -----------------------------------------------------------
if (( haveCreds == 1 )); then
  random_api_delay
  ensure_extension_attributes || log "WARN: EA ensure failed (notary may still work, but Jamf fields may be missing)"
else
  log "INFO: Skipping EA ensure (no credentials available)"
fi

# --- Verify binary (warn only) -------------------------------------------------
binOK=1
if [[ ! -x "${BIN}" ]]; then
  binOK=0
  log "WARN: binary missing or not executable: ${BIN} (LaunchDaemon may fail to start until package is installed)"
fi

write_daemon

if (( binOK == 1 )); then
  /bin/launchctl bootstrap system "${DAEMON}" || log "WARN: launchctl bootstrap failed"
  /bin/launchctl enable system/"${LABEL}" 2>/dev/null || true
  log "LaunchDaemon bootstrapped: ${LABEL}"
else
  log "INFO: Skipping launchctl bootstrap (binary missing)"
fi

log "Deployment complete."
exit 0
