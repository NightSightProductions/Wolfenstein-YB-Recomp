#!/bin/bash
#
# Builds the macOS distribution of Wolfenstein Youngblood Recomp:
#
#   Wolfenstein-Youngblood-Recomp-macOS.dmg
#     Install Wolfenstein Youngblood Recomp.app   installer wizard (Installer.swift) carrying
#       source/                 this project's source, including the framework submodule (git ls-files --recurse-submodules) - no game files
#       source/prebuilt/kosmickrisp   the KosmicKrisp Vulkan driver built from Mesa (make kosmickrisp)
#     License.txt
#
# The installer builds the game on the user's Mac from their own copy of Wolfenstein: Youngblood (the
# Windows release from Steam), by running scripts/build.sh.
#
# Requirements: Xcode Command Line Tools (swiftc, git) and build/kosmickrisp (run `make kosmickrisp`).
# The installer's icon is docs/logo.png when the project has one, else the icon of a local build of the app
# (build/*.app, taken from your copy of the game: it stays in the DMG, never in the repository).
# Usage: setup/macos/build_installer.sh [output dir]

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SETUP="${ROOT}/setup/macos"
OUT="${1:-${ROOT}/build-macos-dist}"
STAGE="${OUT}/stage"
MIN_MACOS="26.0"   # the runtime and KosmicKrisp need a current macOS

APP_NAME="Wolfenstein Youngblood Recomp"
INSTALLER="${STAGE}/dmg/Install ${APP_NAME}.app"
DMG="${OUT}/Wolfenstein-Youngblood-Recomp-macOS.dmg"

die() { echo "error: $*" >&2; exit 1; }

git -C "${ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "run this from a git checkout"
[[ -f "${ROOT}/build/kosmickrisp/kosmickrisp_icd.json" ]] || die "build/kosmickrisp is missing: run 'make kosmickrisp' first"
VERSION="$(git -C "${ROOT}" describe --tags --always 2>/dev/null || echo 1.0)"
VERSION="${VERSION#v}"

rm -rf "${STAGE}"
mkdir -p "${INSTALLER}/Contents/MacOS" "${INSTALLER}/Contents/Resources/source"

# The project's own files: tracked, or new and not ignored (.gitignore is a whitelist that keeps out game code and
# data), here and in the framework submodule.
# The framework's third_party submodules (DXVK, FFmpeg, dxbc-spirv, SPIRV-Cross) are for its 32-bit Windows target
# and not used here; uninitialized, they are listed as bare directories, so only regular files are copied.
source_files() {
    git ls-files --cached --others --exclude-standard | grep -v "^framework$"
    git -C framework ls-files --cached --others --exclude-standard | sed "s#^#framework/#"
}
(cd "${ROOT}" && source_files | sort -u | grep -v "^docs/" \
    | grep -v -E "^framework/third_party/(dxvk|ffmpeg|dxbc-spirv|spirv-cross)(/|$)" | while read -r f; do
    [[ -f "$f" ]] || continue
    mkdir -p "${INSTALLER}/Contents/Resources/source/$(dirname "$f")"
    cp -p "$f" "${INSTALLER}/Contents/Resources/source/$f"
done)
# The prebuilt Vulkan driver (open source: Mesa, MIT; the Khronos loader, Apache-2.0)
mkdir -p "${INSTALLER}/Contents/Resources/source/prebuilt"
cp -R "${ROOT}/build/kosmickrisp" "${INSTALLER}/Contents/Resources/source/prebuilt/kosmickrisp"

sed -e "s/@VERSION@/${VERSION}/g" -e "s/@MIN_MACOS@/${MIN_MACOS}/g" "${SETUP}/InstallerInfo.plist" > "${INSTALLER}/Contents/Info.plist"
xcrun swiftc -O -swift-version 5 -target "arm64-apple-macos${MIN_MACOS}" "${SETUP}/Installer.swift" -o "${INSTALLER}/Contents/MacOS/installer"
[[ -f "${SETUP}/WelcomeImage.png" ]] && cp "${SETUP}/WelcomeImage.png" "${INSTALLER}/Contents/Resources/"
# The installer's icon: docs/logo.png, else the local app build's icon; without either, the default app icon
ICON_SRC=""
[[ -f "${ROOT}/docs/logo.png" ]] && ICON_SRC="${ROOT}/docs/logo.png"
[[ -z "${ICON_SRC}" ]] && ICON_SRC="$(ls "${ROOT}"/build/*.app/Contents/Resources/*.icns 2>/dev/null | head -1)"
if [[ "${ICON_SRC}" == *.icns ]]; then
    cp "${ICON_SRC}" "${INSTALLER}/Contents/Resources/AppIcon.icns"
elif [[ -n "${ICON_SRC}" ]]; then
    ICONSET="${STAGE}/AppIcon.iconset"
    rm -rf "${ICONSET}" && mkdir -p "${ICONSET}"
    for size in 16 32 128 256; do
        sips -z "${size}" "${size}" "${ICON_SRC}" --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
        if [[ ${size} -le 128 ]]; then
            sips -z $((size * 2)) $((size * 2)) "${ICON_SRC}" --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
        fi
    done
    iconutil -c icns "${ICONSET}" -o "${INSTALLER}/Contents/Resources/AppIcon.icns"
fi

# Ad hoc signature: Apple Silicon only runs signed code. Distribution outside this Mac
# needs a Developer ID signature and notarization; set SIGN_ID to use one.
SIGN_ID="${SIGN_ID:--}"
SIGN_OPTS=()
[[ "${SIGN_ID}" != "-" ]] && SIGN_OPTS=(--options runtime --timestamp)
codesign --force --sign "${SIGN_ID}" "${SIGN_OPTS[@]+"${SIGN_OPTS[@]}"}" "${INSTALLER}"

cp "${ROOT}/LICENSE" "${STAGE}/dmg/License.txt"
rm -f "${DMG}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGE}/dmg" -ov -format UDZO "${DMG}" >/dev/null
echo "Created ${DMG}"
