#!/usr/bin/env python3
"""Removes the SteamStub (x64) wrapper from the user's own copy of Youngblood_x64vk.exe, so the translator can
read the game's code. Run at build time on the user's machine; the output is never distributed.

Adapted from Wolfenstein-TOB-Recomp (v3.0) and Wolfenstein-TNC-Recomp (v3.1, a larger header with 64-bit fields).
Youngblood's Steam release uses v3.1 with encryption off (flag 0x04), so only the entry point is restored.

What the stub does at startup, done here ahead of time:
  - its header sits just before the stub entry point in .bind, XOR-chained with a key in its first dword;
  - unless flag 0x04 is set, .text is AES-256-CBC encrypted, its first 16 bytes moved into the header ("stolen"
    bytes), and the IV itself ECB-encrypted with the same key.
The output is the same PE with .text decrypted (if it was encrypted) and the entry point set back to the original. Ownership is
unaffected: the recompiled game still signs in through the real Steam client (runtime/steam.c).

Usage: unwrap_steamstub.py Youngblood_x64vk.exe out.exe
"""
import struct, subprocess, sys

FLAG_NO_ENCRYPTION = 0x04

# variant: (header size, signature, field offsets)
#   oep / code_va / code_raw: (offset, struct format)
VARIANTS = {
    '3.0': dict(size=0xD0, sig=0xC0DEC0DE, ep=(0x10, '<I'), oep=(0x1C, '<I'), app=0x30, flags=0x34,
                code_va=(0x40, '<I'), code_raw=(0x44, '<I'), key=0x48, iv=0x68, stolen=0x78),
    '3.1': dict(size=0xF0, sig=0xC0DEC0DF, ep=(0x10, '<Q'), oep=(0x20, '<Q'), app=0x38, flags=0x3C,
                code_va=(0x48, '<Q'), code_raw=(0x50, '<Q'), key=0x58, iv=0x78, stolen=0x88),
}


def die(msg):
    sys.exit(f"unwrap_steamstub: {msg}")


def sections(pe):
    e_lfanew = struct.unpack_from('<I', pe, 0x3C)[0]
    nsec = struct.unpack_from('<H', pe, e_lfanew + 6)[0]
    opt_size = struct.unpack_from('<H', pe, e_lfanew + 20)[0]
    opt = e_lfanew + 24
    if struct.unpack_from('<H', pe, opt)[0] != 0x20B:
        die("not a PE32+ (x64) image")
    tab = opt + opt_size
    out = []
    for i in range(nsec):
        s = tab + i * 40
        name = pe[s:s + 8].rstrip(b'\0').decode('latin-1')
        vsize, va, rawsize, rawoff = struct.unpack_from('<IIII', pe, s + 8)
        out.append((name, va, vsize, rawoff, rawsize))
    return opt, out


def rva_to_off(secs, rva):
    for _, va, vsize, rawoff, rawsize in secs:
        if va <= rva < va + max(vsize, rawsize):
            return rva - va + rawoff
    die(f"RVA {rva:#x} is outside every section")


def aes(mode, key, data, iv=None):
    cmd = ['openssl', 'enc', '-d', f'-aes-256-{mode}', '-nopad', '-K', key.hex()]
    if iv is not None:
        cmd += ['-iv', iv.hex()]
    r = subprocess.run(cmd, input=data, capture_output=True)
    if r.returncode != 0 or len(r.stdout) != len(data):
        die(f"openssl failed: {r.stderr.decode(errors='replace').strip()}")
    return r.stdout


def header(pe, ep_off):
    for name, v in VARIANTS.items():
        size = v['size']
        h = bytearray(pe[ep_off - size:ep_off])
        key = struct.unpack_from('<I', h, 0)[0]
        for x in range(4, size, 4):
            w = struct.unpack_from('<I', h, x)[0]
            struct.pack_into('<I', h, x, w ^ key)
            key = w
        if struct.unpack_from('<I', h, 4)[0] == v['sig']:
            return name, v, h
    die("no SteamStub v3.0/v3.1 x64 header at the entry point (already unwrapped, or another variant)")


def main():
    if len(sys.argv) != 3:
        die("usage: unwrap_steamstub.py in.exe out.exe")
    pe = bytearray(open(sys.argv[1], 'rb').read())
    opt, secs = sections(pe)
    ep = struct.unpack_from('<I', pe, opt + 16)[0]
    ep_off = rva_to_off(secs, ep)

    variant, v, h = header(pe, ep_off)
    field = lambda f: struct.unpack_from(v[f][1], h, v[f][0])[0]
    stub_ep, oep, code_va, code_raw = field('ep'), field('oep'), field('code_va'), field('code_raw')
    app_id, flags = struct.unpack_from('<II', h, v['app'])[0], struct.unpack_from('<I', h, v['flags'])[0]
    aes_key = bytes(h[v['key']:v['key'] + 0x20])
    aes_iv = bytes(h[v['iv']:v['iv'] + 0x10])
    stolen = bytes(h[v['stolen']:v['stolen'] + 0x10])
    if stub_ep != ep:
        die(f"header entry {stub_ep:#x} != PE entry {ep:#x}")
    print(f"SteamStub v{variant} x64: app {app_id}, flags {flags:#x}, OEP {oep:#x}, code {code_va:#x}+{code_raw:#x}")

    if not flags & FLAG_NO_ENCRYPTION:
        code = [s for s in secs if s[1] == code_va]
        if not code:
            die(f"no section at code RVA {code_va:#x}")
        _, _, _, rawoff, rawsize = code[0]
        if rawsize != code_raw or rawsize % 16:
            die(f"unexpected code section size {rawsize:#x} (header says {code_raw:#x})")
        iv = aes('ecb', aes_key, aes_iv)
        plain = aes('cbc', aes_key, stolen + bytes(pe[rawoff:rawoff + rawsize]), iv)
        pe[rawoff:rawoff + rawsize] = plain[:rawsize]

    struct.pack_into('<I', pe, opt + 16, oep)          # AddressOfEntryPoint
    struct.pack_into('<I', pe, opt + 64, 0)            # CheckSum: no longer valid
    open(sys.argv[2], 'wb').write(pe)
    print(f"wrote {sys.argv[2]}")


if __name__ == '__main__':
    main()
