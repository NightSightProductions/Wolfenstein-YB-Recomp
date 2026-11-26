# Wolfenstein: Youngblood on Recomp-Framework (framework/, a git submodule): static recompilation to
# native arm64 macOS. id Tech 6, Vulkan-only; modelled on DOOM-Recomp (same engine generation) and
# Wolfenstein-TOB-Recomp (SteamStub unwrapping).
#   make gen gen-dll gen-bink   translate Youngblood_x64vk.exe, oo2core_6_win64.dll and bink2w64.dll
#   make -j8 boot               build the runtime + translated game
#   make app                    "build/Wolfenstein Youngblood.app"
#   make kosmickrisp            build the Vulkan driver from Mesa (with the framework's patches)
#   make steam-play             register the app with NightSight Recomp (NSR) (needs NotProton)
#
# orig.exe must be the DRM-free (unwrapped) executable: the Steam release's .text is encrypted by SteamStub v3.1
# (tools/unwrap_steamstub.py, run by scripts/build.sh).
FW        = framework
PYTHON    = .venv/bin/python
BUILD     = build
GAME_EXE ?= orig.exe
APP_NAME  = Youngblood
APP_FILE  = Wolfenstein Youngblood
APP_DISPLAY = Wolfenstein: Youngblood
BUNDLE_ID = com.nightsightproductions.youngblood-recomp
APP_CATEGORY = public.app-category.action-games
APP_FLAGS = --resource $(BUILD)/Youngblood_x64vk.unwrapped.exe=Youngblood_x64vk.exe
GAME_SRC  = src/game.c src/native_youngblood.c src/imports_youngblood.c src/cloud_youngblood.c
NATIVE    = tools/native.txt
PATCHES   = tools/patches.txt
# the game's DLLs that contain code, translated as modules (rules below)
EXTRA_LIBS_FORCE = $(BUILD)/liboo2core_6_win64.a $(BUILD)/libbink2w64.a

include $(FW)/recomp.mk
# id Tech 6 synchronizes its threads through integer flags and locks (as in DOOM 2016), so float and vector
# accesses don't need x86 ordering (see the framework README, "Memory ordering")
GEN_CFLAGS += -DRT_RELAX_FP

# Both DLLs prefer 0x180000000, where arm64 macOS maps its shared cache, so they are translated rebased into the
# framework's DLL range (0x160000000-0x164000000).
# Oodle Data (oo2core_6_win64.dll): the decompressor for the game's resource containers. It synchronizes only
# through kernel objects, so it needs no TSO ordering.
OODLE_DLL ?= orig_oodle.dll
$(eval $(call MODULE_RULES,oo2core_6_win64,$(OODLE_DLL),gen_oodle,--rebase 160000000,-DRT_TSO=0))
# RAD Bink 2 (bink2w64.dll): rebased to 0x162000000, after Oodle. Hand-written assembly: no ABI trimming.
BINK_DLL ?= orig_bink.dll
$(eval $(call MODULE_RULES,bink2w64,$(BINK_DLL),gen_bink,--rebase 162000000 --no-abi-trim,-DRT_TSO=0))

gen-dll: gen-oo2core_6_win64
gen-bink: gen-bink2w64
.PHONY: gen-dll gen-bink

# Steam Play: Play on the game's own Steam entry starts the app (framework/tools/nsr.py, NightSight Recomp).
# NSR's tool ID ("nsr_proton") contains "proton", which Steam for Mac needs before it syncs the game's Auto-Cloud saves
# (Windows' Saved Games) into the tool's compatdata prefix, where src/cloud_youngblood.c points the game's saves.
APP_PATH ?= $(CURDIR)/$(BUILD)/$(APP_FILE).app
steam-play:
	python3 $(FW)/tools/nsr.py install
	python3 $(FW)/tools/nsr.py add --appid 1056960 --app "$(APP_PATH)" --pass-paths --exe 'Youngblood_x64vk.exe' \
	    --name "Wolfenstein: Youngblood"
.PHONY: steam-play
