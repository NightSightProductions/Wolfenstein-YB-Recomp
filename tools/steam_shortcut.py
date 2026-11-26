#!/usr/bin/env python3
"""Add "Wolfenstein Youngblood.app" to the Steam for Mac library as a non-Steam game.

Wolfenstein: Youngblood has no macOS build, so Steam's own library entry can't launch it (unless NightSight Recomp, the
Steam Play tool, is used); a shortcut can. The app reports itself to Steam as app 1056960 when it starts, so Steam
shows the player in Wolfenstein: Youngblood, counts the playtime and records achievements on the real entry.

Steam reads userdata/<account>/config/shortcuts.vdf (binary VDF) when it starts and rewrites it when it quits,
so Steam must not be running while the file is changed: with --restart-steam it is quit first and started again.

usage: steam_shortcut.py --app "/Applications/Wolfenstein Youngblood.app" [--restart-steam] [--remove]
Only the standard library is used (the installer runs it with the system Python).
"""
import glob, os, shutil, struct, subprocess, sys, time, zlib

STEAM = os.path.expanduser("~/Library/Application Support/Steam")
NAME = "Wolfenstein: Youngblood"
TAG = "Wolfenstein Youngblood Recomp"   # marks our entry, to update it instead of adding another

# ---- binary VDF: 0x00 map, 0x01 string, 0x02 int32, 0x08 end of map ----
def parse(data):
    def read_map(i):
        out = {}
        while True:
            t = data[i]; i += 1
            if t == 8: return out, i
            e = data.index(b"\0", i); key = data[i:e].decode("utf-8", "replace"); i = e + 1
            if t == 0: out[key], i = read_map(i)
            elif t == 1: e = data.index(b"\0", i); out[key] = data[i:e].decode("utf-8", "replace"); i = e + 1
            elif t == 2: out[key] = struct.unpack_from("<i", data, i)[0]; i += 4
            else: raise ValueError("unknown VDF type %d" % t)
    root, _ = read_map(0)
    return root

def dump(m):
    out = bytearray()
    for k, v in m.items():
        kb = k.encode() + b"\0"
        if isinstance(v, dict): out += b"\x00" + kb + dump(v)
        elif isinstance(v, int): out += b"\x02" + kb + struct.pack("<i", v)
        else: out += b"\x01" + kb + str(v).encode() + b"\0"
    return bytes(out) + b"\x08"

def shortcut_id(exe, name):
    """the id Steam gives a non-Steam game (also names its artwork files in config/grid)"""
    return (zlib.crc32((exe + name).encode()) & 0xFFFFFFFF) | 0x80000000

def steam_running():
    return subprocess.run(["pgrep", "-x", "steam_osx"], capture_output=True).returncode == 0

def quit_steam():
    subprocess.run(["osascript", "-e", 'tell application "Steam" to quit'], capture_output=True)
    for _ in range(60):
        if not steam_running(): return True
        time.sleep(0.5)
    return False

def main():
    args = sys.argv[1:]
    app = os.path.abspath(args[args.index("--app") + 1]) if "--app" in args else "/Applications/Wolfenstein Youngblood.app"
    remove = "--remove" in args
    users = sorted(glob.glob(os.path.join(STEAM, "userdata", "*", "config")))
    if not users: print("Steam for Mac has no user folders yet (log in to Steam once)"); return 1
    was_running = steam_running()
    if was_running:
        if "--restart-steam" not in args: print("Steam is running: quit it first, or pass --restart-steam"); return 1
        print("quitting Steam");
        if not quit_steam(): print("Steam did not quit"); return 1
    exe = '"%s"' % app
    sid = shortcut_id(exe, NAME)
    icon = os.path.join(app, "Contents", "Resources", "Youngblood.png")
    for cfg in users:
        path = os.path.join(cfg, "shortcuts.vdf")
        root = parse(open(path, "rb").read()) if os.path.exists(path) and os.path.getsize(path) > 2 else {"shortcuts": {}}
        sc = root.setdefault("shortcuts", {})
        entries = [v for k, v in sorted(sc.items(), key=lambda kv: int(kv[0])) if not (isinstance(v, dict) and TAG in v.get("tags", {}).values())]
        if not remove:
            entries.append({
                "appid": sid - (1 << 32) if sid >= 1 << 31 else sid, "AppName": NAME, "Exe": exe,
                "StartDir": '"%s"' % os.path.dirname(app), "icon": icon if os.path.exists(icon) else "", "ShortcutPath": "",
                "LaunchOptions": "", "IsHidden": 0, "AllowDesktopConfig": 1, "AllowOverlay": 1, "OpenVR": 0, "Devkit": 0,
                "DevkitGameID": "", "DevkitOverrideAppID": 0, "LastPlayTime": 0, "FlatpakAppID": "",
                "tags": {"0": TAG},
            })
        root["shortcuts"] = {str(i): e for i, e in enumerate(entries)}
        if os.path.exists(path): shutil.copy2(path, path + ".bak")
        with open(path, "wb") as f: f.write(dump(root))
        print("%s %s in %s" % ("removed" if remove else "added", NAME, path))
    if was_running:
        subprocess.run(["open", "-a", "Steam"])
        print("Steam restarted")
    return 0

if __name__ == "__main__":
    sys.exit(main())
