// Wolfenstein: Youngblood settings for Recomp-Framework (see framework/runtime/game.h).
#include "game.h"

const RtGame rt_game = {
    .name = "Wolfenstein: Youngblood",
    .exe = "Youngblood_x64vk.exe",
    .win_dir = "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Wolfenstein Youngblood",
    .data_name = "youngblood-recomp",
    .log_name = "Youngblood-recomp",
    .env_prefix = "YOUNGBLOOD",
    .steam_folder = "Wolfenstein Youngblood",
    .steam_app_id = 1056960,
    .relaunch_prefix = "Youngblood",
    .extra_args = NULL,
    .cloud_save_dir = NULL,     // saves: src/cloud_youngblood.c links Saved Games\MachineGames to the Steam Cloud folder
    .cloud_prefix = NULL,
    .computer_name = "MAC",
    .pick_folder_msg = "Choose your Wolfenstein: Youngblood game folder: the one that contains Youngblood_x64vk.exe.",
    // the DRM-free copy made at build time by tools/unwrap_steamstub.py and bundled into the app
    .image = "Youngblood_x64vk.exe",
};
