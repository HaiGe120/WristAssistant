#!/usr/bin/env bash
# Build and install the iOS app, including its embedded Watch app, onto a
# connected physical iPhone. The build product is staged outside Documents
# before install so FileProvider/Finder xattrs cannot poison code signing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
PROJECT="${ROOT}/WristAssistant.xcodeproj"
SCHEME="WristAssistant"
DERIVED="${ROOT}/build/derived"
APP_PATH="${DERIVED}/Build/Products/Debug-iphoneos/WristAssistant.app"
STAGE_DIR="/tmp/WristAssistantDeviceInstall"
STAGED_APP="${STAGE_DIR}/WristAssistant.app"
LOG_DIR="${ROOT}/build/device-install"
DEVICE="${1:-}"

XCODE_DEV="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="${XCODE_DEV}/usr/bin:${XCODE_DEV}/bin:${PATH}"
export DEVELOPER_DIR="${XCODE_DEV}"

log() { printf '[device-install.sh %s] %s\n' "$(date +%H:%M:%S)" "$*"; }

resolve_device() {
  xcrun devicectl list devices 2>/dev/null \
    | awk '/available \(paired\)/ { print $3; exit }'
}

if [[ -z "${DEVICE}" ]]; then
  DEVICE="$(resolve_device)"
fi

if [[ -z "${DEVICE}" ]]; then
  log "ERROR: no available paired physical device found."
  xcrun devicectl list devices || true
  exit 2
fi

mkdir -p "${LOG_DIR}"

log "xcodegen generate"
( cd "${ROOT}" && xcodegen generate >/dev/null )

log "xcodebuild Debug iphoneos -> ${DERIVED}"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "${DERIVED}" \
  -allowProvisioningUpdates \
  OTHER_CODE_SIGN_FLAGS="--strip-disallowed-xattrs" \
  clean build 2>&1 | tee "${LOG_DIR}/build.log" | tail -40

if [[ ! -d "${APP_PATH}" ]]; then
  log "ERROR: expected app at ${APP_PATH}"
  exit 1
fi

log "stage app outside Documents -> ${STAGED_APP}"
rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}"
ditto --noextattr --noqtn "${APP_PATH}" "${STAGED_APP}"
find "${STAGED_APP}" -exec xattr -c {} \;

log "verify staged app signature"
codesign --verify --deep --strict --verbose=4 "${STAGED_APP}" 2>&1 \
  | tee "${LOG_DIR}/codesign-verify.log"

log "install to device ${DEVICE}"
xcrun devicectl device install app \
  --device "${DEVICE}" \
  "${STAGED_APP}" \
  --json-output "${LOG_DIR}/install.json" \
  --log-output "${LOG_DIR}/install.log"

log "installed ${STAGED_APP}"
