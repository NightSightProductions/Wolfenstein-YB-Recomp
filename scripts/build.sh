#!/bin/bash
#
# Builds "Wolfenstein Youngblood.app" from YOUR copy of Wolfenstein: Youngblood (Windows
# version, Steam). Nothing from the game is stored in this repository; everything is generated locally from
# your install, and the app reads the game data from your install at run time.
#
# Usage: scripts/build.sh [path/to/Wolfenstein Youngblood]   (the folder with Youngblood_x64vk.exe)
#
# Progress lines start with "==> [n/6]" so an installer can follow along.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
die() { echo "error: $*" >&2; exit 1; }
step() { echo "==> [$1/6] $2"; }

FOLDER="Wolfenstein Youngblood"
find_game() {
    local c
    for c in \
        "$HOME/Library/Application Support/Steam/steamapps/common/$FOLDER" \
        "$HOME/Library/Application Support/CrossOver/Bottles/"*"/drive_c/Program Files (x86)/Steam/steamapps/common/$FOLDER" \
        "$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles/"*"/drive_c/Program Files (x86)/Steam/steamapps/common/$FOLDER"; do
        [[ -f "$c/Youngblood_x64vk.exe" ]] && { echo "$c"; return; }
    done
}
GAME="${1:-$(find_game)}"
[[ -n "$GAME" ]] || die "the game was not found. Pass the folder that contains Youngblood_x64vk.exe"

# The Steam release this project is written against
SHA_EXE="b68a8a41827ce366edfb9c4902ac0a76dfd3e7f61cbdcaa2895e88f60c9c1f55"          # as shipped (SteamStub v3.1)
SHA_UNWRAPPED="0f66d8123ba84dfb17b38c8f12498131bcd06abec5d784b77ded215bdbb0ca41"    # after tools/unwrap_steamstub.py
SHA_OODLE="988e8226d129b03011a96f51b476e86d38c0c3e817266375a78a7cf3b85d93c4"        # oo2core_6_win64.dll
SHA_BINK="05bdd56e088798d2e09a8ea912fadaea821ffea2b328f89e1f525f9859b36e06"         # bink2w64.dll

step 1 "Checking requirements"
for t in clang make python3 codesign ar openssl; do
    command -v "$t" >/dev/null 2>&1 || die "'$t' was not found. Install Apple's Command Line Tools: xcode-select --install"
done
[[ "$(uname -m)" == "arm64" ]] || die "this build targets Apple Silicon Macs"

step 2 "Verifying your copy of the game"
check() {
    [[ -f "$1" ]] || die "$1 was not found"
    local sha; sha="$(shasum -a 256 "$1" | awk '{print $1}')"
    [[ "$sha" == "$2" ]] || die "$1 is not from the supported Steam release (SHA-256 $sha). Make sure the game is fully updated and not modified."
}
check "$GAME/Youngblood_x64vk.exe" "$SHA_EXE"
check "$GAME/oo2core_6_win64.dll" "$SHA_OODLE"
check "$GAME/bink2w64.dll" "$SHA_BINK"

step 3 "Preparing the translator"
[[ -x "$ROOT/.venv/bin/python" ]] || python3 -m venv "$ROOT/.venv"
"$ROOT/.venv/bin/python" -m pip install --quiet --disable-pip-version-check "capstone==5.0.6" "lief==0.16.6"

cd "$ROOT"
mkdir -p build
python3 -I tools/unwrap_steamstub.py "$GAME/Youngblood_x64vk.exe" build/Youngblood_x64vk.unwrapped.exe
check build/Youngblood_x64vk.unwrapped.exe "$SHA_UNWRAPPED"
ln -sf build/Youngblood_x64vk.unwrapped.exe orig.exe
ln -sf "$GAME/oo2core_6_win64.dll" orig_oodle.dll
ln -sf "$GAME/bink2w64.dll" orig_bink.dll

step 4 "Translating the game's code to C"
make -s gen
make -s gen-dll
make -s gen-bink

step 5 "Compiling (this takes several minutes)"
make -s -j"$(sysctl -n hw.ncpu)" boot

step 6 "Packaging the app"
if [[ -d "$ROOT/prebuilt/kosmickrisp" ]]; then
    rm -rf build/kosmickrisp && cp -R "$ROOT/prebuilt/kosmickrisp" build/kosmickrisp
elif [[ ! -d build/kosmickrisp ]]; then
    echo "note: no KosmicKrisp build (make kosmickrisp); the app will use a system install (/usr/local/share/vulkan/icd.d)"
fi
make -s app
mkdir -p "$HOME/Library/Application Support/youngblood-recomp"
printf '%s\n' "$GAME" > "$HOME/Library/Application Support/youngblood-recomp/game-dir.txt"
echo "Built: $ROOT/build/Wolfenstein Youngblood.app"
