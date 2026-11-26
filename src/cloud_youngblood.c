// Steam Cloud saves shared with the Windows version (adapted from Wolfenstein-TOB-Recomp's cloud_wolf.c).
//
// Wolfenstein: Youngblood never calls the Steam Cloud API: its saves sync through Steam Auto-Cloud, which the Steam client runs
// by itself on Windows' Saved Games folder (rule: root WinSavedGames,
// MachineGames/Wolfenstein Youngblood/base/savegame.user/{64BitSteamID}). The game finds that folder with
// SHGetKnownFolderPath(FOLDERID_SavedGames). Steam for Mac resolves the Windows root for a game that runs through a
// compatibility tool, into the tool's Wine-style prefix:
//   <library>/steamapps/compatdata/1056960/pfx/drive_c/users/steamuser/Saved Games
// and syncs it there before launch and after exit, in both directions. It only does so when the tool's internal name
// contains "proton"; NSR's tool ID, "nsr_proton", does (framework/tools/nsr.py). The guest's
// C:\users\Player\Saved Games\MachineGames is a link into that prefix, so the game reads and writes the very files
// Steam syncs, with nothing to import. (Settings stay in Documents\My Games, which Steam doesn't sync.)
//
// Saves made by an earlier build in the app's own folder are kept, renamed to MachineGames.local-<date>.
// YOUNGBLOOD_LOCAL_SAVES=1 keeps saves in the app's folder instead (no cloud).
#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <dirent.h>
#include <time.h>
#include <unistd.h>
#include "game.h"
#include "rt.h"

#define SAVE_DIR "Wolfenstein Youngblood/base/savegame.user"

// The constructor runs before boot opens the log, so its messages wait here until youngblood_cloud_log().
static char msgs[4096];
static void say(const char *fmt, ...) {
    size_t n = strlen(msgs);
    va_list ap; va_start(ap, fmt); vsnprintf(msgs + n, sizeof msgs - n, fmt, ap); va_end(ap);
}
void youngblood_cloud_log(void) {
    static int done;
    if (!done++ && *msgs) rt_log("%s", msgs);
}

static void mkdir_p(const char *path) {
    char t[PATH_MAX]; snprintf(t, sizeof t, "%s", path);
    for (char *p = t + 1; *p; p++) if (*p == '/') { *p = 0; mkdir(t, 0755); *p = '/'; }
    mkdir(t, 0755);
}

static int is_dir(const char *p) { struct stat st; return stat(p, &st) == 0 && S_ISDIR(st.st_mode); }

// The game's compatdata folder, in the Steam library that holds the game:
//   1. STEAM_COMPAT_DATA_PATH, which Steam sets for a compatibility tool (a launch from Steam);
//   2. next to the game folder boot uses (<data>/game-dir.txt: <library>/steamapps/common/<game>);
//   3. the default library.
static void compat_data(const char *home, const char *data, char *out, size_t n) {
    const char *env = getenv("STEAM_COMPAT_DATA_PATH");
    if (env && *env) { snprintf(out, n, "%s", env); return; }
    char p[PATH_MAX], line[PATH_MAX];
    snprintf(p, sizeof p, "%s/game-dir.txt", data);
    FILE *f = fopen(p, "r");
    if (f) {
        int ok = fgets(line, sizeof line, f) != NULL; fclose(f);
        line[strcspn(line, "\n")] = 0;
        char *common = ok ? strstr(line, "/steamapps/common/") : NULL;
        if (common) {
            *common = 0;
            snprintf(out, n, "%s/steamapps/compatdata/%u", line, rt_game.steam_app_id);
            if (is_dir(out)) return;
        }
    }
    snprintf(out, n, "%s/Library/Application Support/Steam/steamapps/compatdata/%u", home, rt_game.steam_app_id);
}

// The runtime re-executes itself once at startup, so the move of local saves usually happens in the first pass,
// whose messages are never logged: list the kept folders every time instead.
static void report(const char *saved, const char *target) {
    say("[cloud] saves: Steam Cloud (%s)\n", target);
    DIR *d = opendir(saved); if (!d) return;
    struct dirent *e;
    while ((e = readdir(d))) if (!strncmp(e->d_name, "MachineGames.local-", 19))
        say("[cloud] earlier local saves kept in %s/%s\n", saved, e->d_name);
    closedir(d);
}

__attribute__((constructor)) static void youngblood_cloud_init(void) {
    const char *home = getenv("HOME");
    const char *local = rt_game_env("LOCAL_SAVES");
    if (!home) return;
    if (local && *local && strcmp(local, "0")) { say("[cloud] YOUNGBLOOD_LOCAL_SAVES: saves stay in the app's folder\n"); return; }

    // the guest's C:\users\Player\Saved Games, under the data folder exactly as runtime/files.c maps drive C:
    char data[PATH_MAX], saved[PATH_MAX], link[PATH_MAX], cdata[PATH_MAX], target[PATH_MAX];
    const char *dd = rt_game_env("DATA_DIR");
    if (dd && *dd) snprintf(data, sizeof data, "%s", dd);
    else snprintf(data, sizeof data, "%s/Library/Application Support/%s", home, rt_game.data_name);
    snprintf(saved, sizeof saved, "%s/c/users/Player/Saved Games", data);
    snprintf(link, sizeof link, "%s/MachineGames", saved);

    char steam[PATH_MAX]; snprintf(steam, sizeof steam, "%s/Library/Application Support/Steam", home);
    if (!is_dir(steam)) { say("[cloud] no Steam for Mac: saves stay in the app's folder\n"); return; }
    compat_data(home, data, cdata, sizeof cdata);
    snprintf(target, sizeof target, "%s/pfx/drive_c/users/steamuser/Saved Games/MachineGames", cdata);

    char base[PATH_MAX + 64]; snprintf(base, sizeof base, "%s/" SAVE_DIR, target);
    mkdir_p(base);
    mkdir_p(saved);

    struct stat st;
    if (lstat(link, &st) == 0) {
        if (S_ISLNK(st.st_mode)) {
            char cur[PATH_MAX]; ssize_t r = readlink(link, cur, sizeof cur - 1);
            if (r > 0) { cur[r] = 0; if (!strcmp(cur, target)) { report(saved, target); return; } }
            unlink(link);   // an older target (another library): relink
        } else {
            // saves of an earlier, local-only build: keep them aside
            char keep[PATH_MAX + 64], stamp[32]; time_t t = time(NULL);
            strftime(stamp, sizeof stamp, "%Y%m%d-%H%M%S", localtime(&t));
            snprintf(keep, sizeof keep, "%s.local-%s", link, stamp);
            if (rename(link, keep)) { say("[cloud] could not move %s aside (%s): saves stay local\n", link, strerror(errno)); return; }
        }
    }
    if (symlink(target, link)) { say("[cloud] could not link %s (%s): saves stay local\n", link, strerror(errno)); return; }
    report(saved, target);
}
