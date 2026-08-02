#!/bin/bash

# Install the latest released Notary package from GitHub.

set -u
set -o pipefail

readonly GITHUB_API_URL="https://api.github.com/repos/lawnmowerwoman/Notary/releases"
readonly TARGET_VOLUME="/"
readonly EXPECTED_TEAM_ID="KP5T66DWT2"
readonly INSTALLED_APP_INFO="/Applications/Notary.app/Contents/Info.plist"

tmp_dir=""
pkg_path=""
allow_beta=false

log() {
    printf '%s\n' "$*"
}

fail() {
    local exit_code="$1"
    shift

    printf 'Error: %s\n' "$*" >&2
    exit "$exit_code"
}

cleanup() {
    if [[ -n "${tmp_dir}" && -d "${tmp_dir}" ]]; then
        log "Cleaning up..."
        rm -rf "${tmp_dir}"
        tmp_dir=""
    fi
}

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        fail 6 "This script must be run as root because installer -pkg requires administrator privileges."
    fi
}

usage() {
    cat <<'EOF'
Usage: installNotary.sh [--beta]

Options:
  --beta    Allow beta packages whose build number ends with a letter.
  --help    Show this help.
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --beta)
                allow_beta=true
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                fail 20 "Unknown argument: $1"
                ;;
        esac
        shift
    done
}

create_temp_dir() {
    tmp_dir="$(mktemp -d "/private/tmp/notary-install.XXXXXX")" || fail 2 "Could not create a temporary directory."
}

fetch_releases() {
    curl --fail --silent --show-error --location \
        --header "Accept: application/vnd.github+json" \
        --header "X-GitHub-Api-Version: 2022-11-28" \
        "${GITHUB_API_URL}"
}

plist_extract() {
    local key_path="$1"
    local file_path="$2"

    /usr/bin/plutil -extract "${key_path}" raw -o - "${file_path}" 2>/dev/null
}

version_from_pkg_url() {
    local download_url="$1"
    local file_name
    local without_extension

    file_name="$(basename "${download_url%%\?*}")"
    without_extension="${file_name%.pkg}"

    if [[ "${without_extension}" =~ ^notary-([0-9]+([.][0-9]+)*)(-([[:alnum:]]+))?$ ]]; then
        printf '%s|%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[4]}"
        return 0
    fi

    return 1
}

installed_version() {
    local marketing
    local build

    [[ -f "${INSTALLED_APP_INFO}" ]] || return 1
    marketing="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${INSTALLED_APP_INFO}" 2>/dev/null || true)"
    build="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${INSTALLED_APP_INFO}" 2>/dev/null || true)"
    [[ -n "${marketing}" ]] || return 1

    printf '%s|%s\n' "${marketing}" "${build}"
}

display_descriptor() {
    local descriptor="$1"
    local marketing="${descriptor%%|*}"
    local build="${descriptor#*|}"

    if [[ -n "${build}" && "${build}" != "${marketing}" ]]; then
        printf '%s (%s)\n' "${marketing}" "${build}"
    else
        printf '%s\n' "${marketing}"
    fi
}

is_beta_build() {
    local build="$1"

    [[ "${build}" =~ [[:alpha:]]$ ]]
}

compare_dot_versions() {
    local left="$1"
    local right="$2"
    local IFS=.
    local -a left_parts right_parts
    local count
    local i
    local left_value
    local right_value

    read -r -a left_parts <<< "${left#v}"
    read -r -a right_parts <<< "${right#v}"
    count="${#left_parts[@]}"
    [[ "${#right_parts[@]}" -gt "${count}" ]] && count="${#right_parts[@]}"

    for ((i = 0; i < count; i++)); do
        left_value="${left_parts[$i]:-0}"
        right_value="${right_parts[$i]:-0}"
        ((10#${left_value} > 10#${right_value})) && return 1
        ((10#${left_value} < 10#${right_value})) && return 2
    done

    return 0
}

build_without_beta_suffix() {
    local build="$1"

    if is_beta_build "${build}"; then
        printf '%s\n' "${build%?}"
    else
        printf '%s\n' "${build}"
    fi
}

compare_builds() {
    local left="$1"
    local right="$2"
    local left_base
    local right_base
    local left_beta=false
    local right_beta=false

    [[ "${left}" == "${right}" ]] && return 0
    [[ -z "${left}" && -n "${right}" ]] && return 2
    [[ -n "${left}" && -z "${right}" ]] && return 1

    left_base="$(build_without_beta_suffix "${left}")"
    right_base="$(build_without_beta_suffix "${right}")"
    is_beta_build "${left}" && left_beta=true
    is_beta_build "${right}" && right_beta=true

    if [[ "${left_base}" == "${right_base}" && "${left_beta}" != "${right_beta}" ]]; then
        [[ "${left_beta}" == false ]] && return 1
        return 2
    fi

    compare_mixed_versions "${left}" "${right}"
}

compare_mixed_versions() {
    local left="$1"
    local right="$2"
    local left_tokens
    local right_tokens

    left_tokens="$(printf '%s\n' "${left}" | sed -E 's/([0-9]+|[A-Za-z]+)/\1 /g')"
    right_tokens="$(printf '%s\n' "${right}" | sed -E 's/([0-9]+|[A-Za-z]+)/\1 /g')"

    awk -v left="${left_tokens}" -v right="${right_tokens}" '
        BEGIN {
            leftCount = split(left, l, " ")
            rightCount = split(right, r, " ")
            count = leftCount > rightCount ? leftCount : rightCount
            for (i = 1; i <= count; i++) {
                lv = l[i]
                rv = r[i]
                if (lv == "" && rv == "") { continue }
                if (lv == "") { exit 2 }
                if (rv == "") { exit 1 }
                ln = lv ~ /^[0-9]+$/
                rn = rv ~ /^[0-9]+$/
                if (ln && rn) {
                    if (lv + 0 > rv + 0) { exit 1 }
                    if (lv + 0 < rv + 0) { exit 2 }
                    continue
                }
                if (lv > rv) { exit 1 }
                if (lv < rv) { exit 2 }
            }
            exit 0
        }
    '
}

compare_descriptors() {
    local left="$1"
    local right="$2"
    local left_marketing="${left%%|*}"
    local left_build="${left#*|}"
    local right_marketing="${right%%|*}"
    local right_build="${right#*|}"

    [[ "${left_build}" == "${left_marketing}" ]] && left_build=""
    [[ "${right_build}" == "${right_marketing}" ]] && right_build=""

    compare_dot_versions "${left_marketing}" "${right_marketing}"
    case "$?" in
        1|2) return "$?" ;;
    esac

    compare_builds "${left_build}" "${right_build}"
}

descriptor_is_newer() {
    local candidate="$1"
    local baseline="$2"

    compare_descriptors "${candidate}" "${baseline}"
    [[ "$?" -eq 1 ]]
}

select_release_candidate() {
    local releases_file="$1"
    local release_index=0
    local asset_index
    local prerelease
    local download_url
    local descriptor
    local build
    local best_descriptor=""
    local best_url=""

    while plist_extract "${release_index}.tag_name" "${releases_file}" >/dev/null; do
        prerelease="$(plist_extract "${release_index}.prerelease" "${releases_file}" || printf 'false')"
        asset_index=0
        while download_url="$(plist_extract "${release_index}.assets.${asset_index}.browser_download_url" "${releases_file}")"; do
            if [[ "${download_url%%\?*}" == *.pkg ]] && descriptor="$(version_from_pkg_url "${download_url}")"; then
                build="${descriptor#*|}"
                if [[ "${allow_beta}" != true ]]; then
                    if [[ "${prerelease}" == "true" ]] || is_beta_build "${build}"; then
                        asset_index=$((asset_index + 1))
                        continue
                    fi
                fi
                if [[ -z "${best_descriptor}" ]] || descriptor_is_newer "${descriptor}" "${best_descriptor}"; then
                    best_descriptor="${descriptor}"
                    best_url="${download_url}"
                fi
            fi
            asset_index=$((asset_index + 1))
        done
        release_index=$((release_index + 1))
    done

    [[ -n "${best_url}" ]] || return 1
    printf '%s\n%s\n' "${best_descriptor}" "${best_url}"
}

download_pkg() {
    local download_url="$1"
    local file_name

    file_name="$(basename "${download_url%%\?*}")"
    [[ -n "${file_name}" && "${file_name}" == *.pkg ]] || fail 14 "Could not determine a valid PKG filename from the release asset URL."

    pkg_path="${tmp_dir}/${file_name}"

    curl --fail --location --show-error \
        --output "${pkg_path}" \
        "${download_url}" || fail 3 "Download failed."

    [[ -s "${pkg_path}" ]] || fail 4 "Downloaded package is missing or empty."
}

validate_pkg() {
    local signature_output
    local actual_team_id

    signature_output="$(pkgutil --check-signature "${pkg_path}" 2>&1)" || fail 5 "Downloaded package signature could not be verified."

    actual_team_id="$(printf '%s\n' "${signature_output}" | awk -F '[()]' '/Developer ID Installer:/ { print $2; exit }')"

    [[ -n "${actual_team_id}" ]] || fail 15 "Could not determine the package signer Team ID."
    [[ "${actual_team_id}" == "${EXPECTED_TEAM_ID}" ]] || fail 16 "Package signer Team ID mismatch. Expected ${EXPECTED_TEAM_ID}, got ${actual_team_id}."
}

install_pkg() {
    installer -pkg "${pkg_path}" -target "${TARGET_VOLUME}" >/dev/null || fail 9 "Package installation failed."
}

main() {
    local release_json
    local releases_file
    local installed_descriptor
    local candidate
    local candidate_descriptor
    local download_url

    trap cleanup EXIT

    parse_arguments "$@"
    create_temp_dir

    log "Checking GitHub releases..."
    release_json="$(fetch_releases)" || fail 13 "Could not retrieve GitHub releases."
    releases_file="${tmp_dir}/releases.json"
    printf '%s\n' "${release_json}" > "${releases_file}"

    candidate="$(select_release_candidate "${releases_file}")" || fail 14 "Could not find a suitable Notary package in GitHub releases."
    candidate_descriptor="$(printf '%s\n' "${candidate}" | sed -n '1p')"
    download_url="$(printf '%s\n' "${candidate}" | sed -n '2p')"

    installed_descriptor="$(installed_version || true)"

    log ""
    if [[ -n "${installed_descriptor}" ]]; then
        log "Installed version: $(display_descriptor "${installed_descriptor}")"
    else
        log "Installed version: not installed"
    fi
    log "GitHub version: $(display_descriptor "${candidate_descriptor}")"

    if [[ -n "${installed_descriptor}" ]] && ! descriptor_is_newer "${candidate_descriptor}" "${installed_descriptor}"; then
        log ""
        log "No newer Notary version is available. Nothing to install."
        cleanup
        trap - EXIT
        exit 0
    fi

    log "Downloading..."
    download_pkg "${download_url}"

    validate_pkg

    log "Installing..."
    require_root
    install_pkg

    cleanup
    trap - EXIT

    log "Installation completed."
}

main "$@"
