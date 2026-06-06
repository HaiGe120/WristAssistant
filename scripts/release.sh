#!/usr/bin/env bash
# scripts/release.sh — App Store archive + export for WristChat.
#
# Why this exists: sim.sh is for the Debug-iphonesimulator flow. This
# script handles the Release/iphoneos archive + IPA export that gets
# uploaded to App Store Connect (via `xcrun altool --upload-app` or
# Transporter).
#
# What it does:
#   1. Regenerate the Xcode project from project.yml (so any change
#      to DEVELOPMENT_TEAM / CFBundleDisplayName / version lands).
#   2. xcodebuild archive (Release, generic/platform=iOS) into
#      build/derived/WristChat.xcarchive.
#   3. xcodebuild -exportArchive with scripts/ExportOptions-AppStore.plist
#      into build/derived/ipa/WristChat.ipa.
#
# Usage:
#   scripts/release.sh                # archive + export (no upload)
#   scripts/release.sh upload         # archive + export + altool upload
#   APPLE_ID='you@example.com' \
#     APP_SPECIFIC_PWD='abcd-efgh-ijkl-mnop' \
#     scripts/release.sh upload
#
# Signing is automatic — Xcode uses the DEVELOPMENT_TEAM in project.yml
# (currently 1524412550) and your signed-in Apple ID. If you need
# manual signing, swap signingStyle in ExportOptions-AppStore.plist.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
PROJECT="${ROOT}/WristAssistant.xcodeproj"
SCHEME="WristAssistant"
DERIVED="${ROOT}/build/derived"
ARCHIVE_PATH="${DERIVED}/WristChat.xcarchive"
EXPORT_DIR="${DERIVED}/ipa"
IPA_PATH="${EXPORT_DIR}/WristChat.ipa"
EXPORT_OPTIONS="${SCRIPT_DIR}/ExportOptions-AppStore.plist"

XCODE_DEV="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="${XCODE_DEV}/usr/bin:${XCODE_DEV}/bin:${PATH}"
export DEVELOPER_DIR="${XCODE_DEV}"

log() { printf '[release.sh %s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# Always regenerate the project so project.yml is the source of truth.
log "xcodegen generate"
( cd "${ROOT}" && xcodegen generate >/dev/null )

mkdir -p "${EXPORT_DIR}"

log "xcodebuild archive -> ${ARCHIVE_PATH}"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "${DERIVED}" \
  -archivePath "${ARCHIVE_PATH}" \
  -allowProvisioningUpdates \
  archive 2>&1 | tail -40

log "xcodebuild -exportArchive -> ${IPA_PATH}"
xcodebuild \
  -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_DIR}" \
  -exportOptionsPlist "${EXPORT_OPTIONS}" \
  2>&1 | tail -20

if [[ ! -f "${IPA_PATH}" ]]; then
  log "ERROR: expected IPA at ${IPA_PATH} but it was not produced."
  log "Contents of ${EXPORT_DIR}:"
  ls -la "${EXPORT_DIR}" || true
  exit 1
fi
log "ipa ready: ${IPA_PATH}"
ls -lh "${IPA_PATH}"

if [[ "${1:-}" == "upload" ]]; then
  if [[ -z "${APPLE_ID:-}" || -z "${APP_SPECIFIC_PWD:-}" ]]; then
    log "ERROR: upload requested but APPLE_ID and APP_SPECIFIC_PWD are not set."
    log "Generate an app-specific password at appleid.apple.com and re-run:"
    log "  APPLE_ID='you@example.com' APP_SPECIFIC_PWD='abcd-efgh-ijkl-mnop' \\"
    log "    scripts/release.sh upload"
    exit 1
  fi
  log "xcrun altool --upload-app (App Store Connect)"
  xcrun altool --upload-app \
    -f "${IPA_PATH}" \
    -t ios \
    -u "${APPLE_ID}" \
    -p "${APP_SPECIFIC_PWD}" \
    --output-format xml
  log "upload submitted. Check App Store Connect → Activity."
fi
