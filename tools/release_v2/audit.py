"""Bounded PE/ELF/Mach-O/PCK structure checks; no native-platform claims.

Mach-O signature checks validate blob structure and ad-hoc flags. They do not
replace Apple's codesign verification, certificate trust or notarization.
"""
import ctypes
import hashlib
import os
import plistlib
import struct
import zipfile
from pathlib import Path
import config
from common import require, sha
from package import inspect_archive, valid_member


def unpack(fmt, data, offset=0):
    require(offset >= 0 and offset + struct.calcsize(fmt) <= len(data), "Truncated or out-of-range binary field")
    return struct.unpack_from(fmt, data, offset)


def pck_header(data):
    require(len(data) >= 24 and data[:4] == b"GDPC", "Invalid/truncated PCK header")
    version, major, minor, patch, flags = unpack("<5I", data, 4)
    require(version > 0, "Invalid PCK format version")
    expected = tuple(int(x) for x in config.ENGINE_VERSION.split(".")[:3])
    require((major, minor, patch) == expected, "PCK engine version differs from configured Godot")
    return {"pack_format": version, "engine_version": f"{major}.{minor}.{patch}", "flags": flags}


def audit_pck(path):
    path = Path(path)
    size = path.stat().st_size
    require(size >= 36, "Binary too short for an embedded PCK and footer")
    with path.open("rb") as stream:
        stream.seek(size - 12)
        footer = stream.read(12)
        packed_size = unpack("<Q", footer)[0]
        start = size - 12 - packed_size
        require(packed_size >= 24 and 0 <= start < size - 12, "Embedded PCK size/offset out of bounds")
        require(footer[8:] == b"GDPC", "Missing PCK footer magic")
        stream.seek(start)
        header = pck_header(stream.read(24))
    return {"path": str(path), "sha256": sha(path), "file_bytes": size,
            "embedded_pck": {"header_magic": "GDPC", "footer_magic": "GDPC", "footer_bytes": 12,
                             "pck_offset": start, "pck_bytes": packed_size, "structural_check": "PASS", **header},
            "native_execution_tested_by_this_audit": False}


def _pe(path):
    size = path.stat().st_size
    with path.open("rb") as stream:
        dos = stream.read(64)
        require(dos[:2] == b"MZ", "Missing DOS/PE header")
        offset = unpack("<I", dos, 60)[0]
        require(64 <= offset <= size - 24, "PE header offset out of bounds")
        stream.seek(offset)
        coff = stream.read(24)
        require(coff[:4] == b"PE\0\0", "Missing PE signature")
        machine, count, _timestamp, _symbol, _symbols, optional_size, flags = unpack("<HHIIIHH", coff, 4)
        require(machine == 0x8664 and 0 < count <= 96, "Expected x86_64 PE with sections")
        require(flags & 2 and not flags & 0x2000, "PE is not an executable image")
        require(optional_size >= 112 and offset + 24 + optional_size + count * 40 <= size, "Truncated PE optional/section headers")
        optional = stream.read(optional_size)
        require(unpack("<H", optional)[0] == 0x20B, "Expected PE32+ optional header")
        headers_size = unpack("<I", optional, 60)[0]
        require(offset + 24 + optional_size + count * 40 <= headers_size <= size, "Invalid PE SizeOfHeaders")
        sections = stream.read(count * 40)
        ranges = []
        for index in range(count):
            raw_size, raw_offset = unpack("<II", sections, index * 40 + 16)
            if raw_size:
                require(raw_offset >= headers_size and raw_offset + raw_size <= size, "PE section raw data out of bounds")
                ranges.append((raw_offset, raw_offset + raw_size))
        ranges.sort()
        require(all(a[1] <= b[0] for a, b in zip(ranges, ranges[1:])), "Overlapping PE sections")
    return {"format": "PE32+", "architecture": "x86_64", "sections": count}


def _elf(path):
    size = path.stat().st_size
    with path.open("rb") as stream:
        header = stream.read(64)
        require(header[:7] == b"\x7fELF\x02\x01\x01", "Expected little-endian ELF64 version 1")
        kind, machine, version = unpack("<HHI", header, 16)
        require(kind in (2, 3) and machine == 62 and version == 1, "Expected executable/PIE x86_64 ELF")
        program_offset = unpack("<Q", header, 32)[0]
        header_size, entry_size, count = unpack("<HHH", header, 52)
        require(header_size == 64 and entry_size == 56 and count > 0, "Invalid ELF64 program table")
        require(program_offset >= 64 and program_offset + entry_size * count <= size, "ELF program table out of bounds")
        stream.seek(program_offset)
        table = stream.read(entry_size * count)
        loads = 0
        for index in range(count):
            ptype, _flags, offset, _vaddr, _paddr, filesz, memsz, _alignment = unpack("<II6Q", table, index * entry_size)
            require(offset + filesz <= size, "ELF program data out of bounds")
            if ptype == 1:
                loads += 1
                require(filesz <= memsz, "ELF load file size exceeds memory size")
        require(loads > 0, "ELF has no loadable segment")
    return {"format": "ELF64", "architecture": "x86_64", "load_segments": loads, "native_execution_tested": False}


def _code_signature(data, offset, size):
    require(size >= 20 and offset >= 32 and offset + size <= len(data), "Mach-O signature range out of slice")
    blob = data[offset:offset + size]
    magic, declared, slots = unpack(">III", blob)
    require(magic == 0xFADE0CC0 and 12 + slots * 8 <= declared <= len(blob), "Invalid signature superblob")
    directories = []
    ranges = []
    for index in range(slots):
        slot_type, at = unpack(">II", blob, 12 + index * 8)
        require(at >= 12 + slots * 8 and at + 8 <= declared, "Signature slot points into its index/outside blob")
        blob_magic, length = unpack(">II", blob, at)
        require(length >= 8 and at + length <= declared, "Signature child blob out of bounds")
        ranges.append((at, at + length))
        if blob_magic == 0xFADE0C02:
            require(length >= 44, "Truncated CodeDirectory")
            _magic, _length, version, flags, hash_offset, ident_offset, special, count, limit = unpack(">9I", blob, at)
            hash_size, hash_type, _platform, page_size = unpack(">4B", blob, at + 36)
            require(flags & 2, "CodeDirectory is not ad-hoc signed")
            expected_size = {1: 20, 2: 32, 3: 20, 4: 48}.get(hash_type)
            require(expected_size == hash_size and 0 <= page_size <= 30, "Invalid CodeDirectory hash parameters")
            require(44 <= ident_offset < length, "CodeDirectory identifier out of bounds")
            require(b"\0" in blob[at + ident_offset:at + length], "Unterminated CodeDirectory identifier")
            require(hash_offset - special * hash_size >= 44 and hash_offset + count * hash_size <= length, "CodeDirectory hash slots out of bounds")
            if version >= 0x20300 and limit == 0xFFFFFFFF:
                require(length >= 64, "Missing 64-bit CodeDirectory limit")
                limit = unpack(">Q", blob, at + 56)[0]
            require(limit <= offset, "CodeDirectory signs beyond its signature start")
            directories.append({"slot_type": slot_type, "bytes": length, "version_hex": hex(version),
                                "flags_hex": hex(flags), "ad_hoc_flag_set": True, "code_limit": limit,
                                "code_slots": count, "hash_type": hash_type})
    ranges.sort()
    require(all(a[1] <= b[0] for a, b in zip(ranges, ranges[1:])), "Overlapping signature blobs")
    require(directories, "No ad-hoc CodeDirectory in signature")
    return {"load_command": "LC_CODE_SIGNATURE", "offset_in_slice": offset, "allocated_bytes": size,
            "superblob_bytes": declared, "code_directories": directories}


def audit_macos(path):
    path = Path(path)
    archive_info = inspect_archive(path)  # CRC, unsafe paths, duplicate names, symlinks.
    with zipfile.ZipFile(path) as archive:
        plist_names = [name for name in archive.namelist() if name.endswith(".app/Contents/Info.plist")]
        require(len(plist_names) == 1, "Expected exactly one macOS app Info.plist")
        info_name = plist_names[0]
        plist = plistlib.loads(archive.read(info_name))
        require(isinstance(plist, dict), "Info.plist must be a dictionary")
        require(plist.get("CFBundleShortVersionString") == config.MAC_VERSION and plist.get("CFBundleVersion") == config.MAC_VERSION, "macOS bundle version mismatch")
        basename = plist.get("CFBundleExecutable", "")
        require(isinstance(basename, str) and valid_member(basename).name == basename, "Unsafe bundle executable name")
        require(isinstance(plist.get("CFBundleIdentifier"), str) and bool(plist["CFBundleIdentifier"]), "Missing bundle identifier")
        contents = info_name.rsplit("/", 1)[0]
        executable = contents + "/MacOS/" + basename
        info = archive.getinfo(executable)
        mode = info.external_attr >> 16
        require(info.create_system == 3 and mode & 0o777 == 0o755, "macOS executable ZIP mode must be 0755")
        binary = archive.read(info)
        magic, count = unpack(">II", binary)
        require(magic == 0xCAFEBABE and count == 2, "Expected two-slice universal Mach-O")
        architectures, intervals = [], []
        for index in range(count):
            cpu, _subtype, offset, size, alignment = unpack(">IIIII", binary, 8 + index * 20)
            require(cpu in (0x1000007, 0x100000C), "Unexpected Mach-O architecture")
            require(offset >= 8 + count * 20 and size >= 32 and offset + size <= len(binary), "Mach-O slice out of bounds")
            require(alignment <= 30 and offset % (1 << alignment) == 0, "Invalid Mach-O slice alignment")
            intervals.append((offset, offset + size))
            data = binary[offset:offset + size]
            header = unpack("<8I", data)
            require(header[0] == 0xFEEDFACF and header[1] == cpu and header[3] == 2, "Invalid Mach-O executable slice header")
            ncmds, command_bytes = header[4], header[5]
            require(ncmds > 0 and 32 + command_bytes <= len(data), "Mach-O load-command area out of bounds")
            position, signatures = 32, []
            for _ in range(ncmds):
                command, length = unpack("<II", data, position)
                require(length >= 8 and length % 8 == 0 and position + length <= 32 + command_bytes, "Malformed Mach-O load command")
                if command == 0x1D:
                    require(length == 16, "Malformed LC_CODE_SIGNATURE length")
                    signature_offset, signature_size = unpack("<II", data, position + 8)
                    require(signature_offset >= 32 + command_bytes, "Signature overlaps Mach-O commands")
                    signatures.append(_code_signature(data, signature_offset, signature_size))
                position += length
            require(position == 32 + command_bytes and len(signatures) == 1, "Mach-O load commands/signature count mismatch")
            architectures.append({"architecture": {0x1000007: "x86_64", 0x100000C: "arm64"}[cpu],
                                  "cpu_type_hex": hex(cpu), "slice_offset": offset, "slice_bytes": size, "signatures": signatures})
        intervals.sort()
        require(intervals[0][1] <= intervals[1][0], "Overlapping Mach-O slices")
        require({item["architecture"] for item in architectures} == {"x86_64", "arm64"}, "Missing universal architecture")
        packs = [name for name in archive.namelist() if name.startswith(contents + "/Resources/") and name.endswith(".pck")]
        require(len(packs) == 1, "Expected one game PCK inside app Resources")
        with archive.open(packs[0]) as stream:
            pack = pck_header(stream.read(24))
        seal_name = contents + "/_CodeSignature/CodeResources"
        seal = archive.read(seal_name)
        require(bool(seal) and isinstance(plistlib.loads(seal), dict), "Invalid CodeResources plist")
    return {"format": "Mach-O Universal 2", "path": str(path), "sha256": archive_info["sha256"], "file_bytes": path.stat().st_size,
            "zip_crc": "PASS", "bundle_identifier": plist["CFBundleIdentifier"], "executable_member": executable,
            "zip_create_system": info.create_system, "executable_unix_mode": oct(mode), "execute_permissions": "0755",
            "architectures": architectures, "pck_member": packs[0], "pck_header": pack,
            "code_resources": {"member": seal_name, "bytes": len(seal), "sha256": hashlib.sha256(seal).hexdigest(), "plist_parse": "PASS"},
            "signing": "ad-hoc structure only", "native_execution_tested_by_this_audit": False,
            "apple_codesign_validation_executed": False, "apple_notarization_verified": False}


def inspect_binary(platform, path):
    path = Path(path)
    require(path.is_file(), "Export file missing: " + str(path))
    if platform == "windows":
        return _pe(path)
    if platform == "linux":
        return _elf(path)
    require(platform == "macos", "Unknown binary platform: " + str(platform))
    return audit_macos(path)


def windows_version(path):
    require(os.name == "nt", "Windows version-resource validation needs a Windows host")
    api = ctypes.WinDLL("version", use_last_error=True)
    api.GetFileVersionInfoSizeW.argtypes = [ctypes.c_wchar_p, ctypes.POINTER(ctypes.c_uint32)]
    api.GetFileVersionInfoSizeW.restype = ctypes.c_uint32
    api.GetFileVersionInfoW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
    api.GetFileVersionInfoW.restype = ctypes.c_int
    api.VerQueryValueW.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p, ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_uint)]
    api.VerQueryValueW.restype = ctypes.c_int
    size = api.GetFileVersionInfoSizeW(str(path), None)
    require(size > 0, "Missing Windows version resource")
    buffer = ctypes.create_string_buffer(size)
    require(api.GetFileVersionInfoW(str(path), 0, size, buffer), "Cannot read Windows version resource")
    pointer, length = ctypes.c_void_p(), ctypes.c_uint()
    require(api.VerQueryValueW(buffer, "\\", ctypes.byref(pointer), ctypes.byref(length)), "Missing VS_FIXEDFILEINFO")
    require(pointer.value is not None and length.value >= 52, "Truncated VS_FIXEDFILEINFO")
    words = ctypes.cast(pointer, ctypes.POINTER(ctypes.c_uint32 * 13)).contents
    require(words[0] == 0xFEEF04BD, "Invalid Windows fixed version signature")
    def dotted(ms, ls):
        return ".".join(str(n) for n in (ms >> 16, ms & 0xFFFF, ls >> 16, ls & 0xFFFF))
    actual = {"file_version": dotted(words[2], words[3]), "product_version": dotted(words[4], words[5])}
    require(all(v == config.FILE_VERSION for v in actual.values()), "Windows version mismatch: " + str(actual))
    return actual


def audit_all(exports):
    require(set(exports) == {"windows", "linux", "macos"}, "Audit requires exactly three platform exports")
    result = {}
    for platform, value in exports.items():
        path = Path(value["path"])
        original = sha(path)
        require(original == value["sha256"], "Export changed before binary audit: " + platform)
        entry = inspect_binary(platform, path)
        if platform != "macos":
            entry.update(audit_pck(path))
            if platform == "windows":
                entry.update(windows_version(path))
        require(sha(path) == original, "Export changed during binary audit: " + platform)
        entry.update(status="PASS", bytes=path.stat().st_size, sha256=original)
        result[platform] = entry
    return result
