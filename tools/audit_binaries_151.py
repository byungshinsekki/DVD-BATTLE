"""Read-only structural audit of the final V1.5.1 exports; not a native launch test."""
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT.parent / "DVD_BATTLE_1.5.1_RELEASE"
OUTPUT = ROOT / "reports/multiplatform_151/binary_audit.json"


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def audit_pck(path):
    with path.open("rb") as stream:
        stream.seek(-12, 2)
        footer = stream.read(12)
        pck_bytes = struct.unpack_from("<Q", footer)[0]
        pck_start = path.stat().st_size - 12 - pck_bytes
        assert 0 <= pck_start < path.stat().st_size - 12
        stream.seek(pck_start)
        header = stream.read(4)
        assert footer[8:] == header == b"GDPC"
    return {"path": str(path), "sha256": sha(path), "file_bytes": path.stat().st_size,
            "embedded_pck": {"header_magic": header.decode("ascii"),
                             "footer_magic": footer[8:].decode("ascii"),
                             "footer_bytes": 12, "pck_offset": pck_start,
                             "pck_bytes": pck_bytes, "structural_check": "PASS"},
            "native_execution_tested_by_this_audit": False}


def audit_macos(path):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        info_name = next(n for n in archive.namelist() if n.endswith(".app/Contents/Info.plist"))
        plist = plistlib.loads(archive.read(info_name))
        executable = info_name.rsplit("/", 1)[0] + "/MacOS/" + plist["CFBundleExecutable"]
        info = archive.getinfo(executable)
        mode = info.external_attr >> 16
        assert info.create_system == 3 and mode & 0o777 == 0o755
        binary = archive.read(info)
        magic, count = struct.unpack_from(">II", binary)
        assert magic == 0xCAFEBABE and count == 2
        architectures = []
        for index in range(count):
            cpu, subtype, offset, size, alignment = struct.unpack_from(">IIIII", binary, 8 + index * 20)
            data = binary[offset:offset + size]
            header = struct.unpack_from("<8I", data)
            assert header[0] == 0xFEEDFACF
            ncmds = header[4]
            position = 32
            signatures = []
            for _ in range(ncmds):
                command, length = struct.unpack_from("<II", data, position)
                assert length >= 8 and position + length <= len(data)
                if command == 0x1D:
                    signature_offset, signature_size = struct.unpack_from("<II", data, position + 8)
                    signature = data[signature_offset:signature_offset + signature_size]
                    sig_magic, sig_size, slots = struct.unpack_from(">III", signature)
                    assert sig_magic == 0xFADE0CC0 and sig_size <= len(signature)
                    directories = []
                    for slot in range(slots):
                        slot_type, at = struct.unpack_from(">II", signature, 12 + slot * 8)
                        blob_magic = struct.unpack_from(">I", signature, at)[0]
                        if blob_magic == 0xFADE0C02:
                            _, blob_size, version, flags = struct.unpack_from(">IIII", signature, at)
                            assert flags & 2
                            directories.append({"slot_type": slot_type, "bytes": blob_size,
                                                "version_hex": hex(version), "flags_hex": hex(flags),
                                                "ad_hoc_flag_set": True})
                    assert directories
                    signatures.append({"load_command": "LC_CODE_SIGNATURE", "offset_in_slice": signature_offset,
                                       "allocated_bytes": signature_size, "superblob_bytes": sig_size,
                                       "code_directories": directories})
                position += length
            assert signatures
            architectures.append({"architecture": {0x01000007: "x86_64", 0x0100000C: "arm64"}[cpu],
                                  "cpu_type_hex": hex(cpu), "slice_offset": offset, "slice_bytes": size,
                                  "signatures": signatures})
        assert {a["architecture"] for a in architectures} == {"x86_64", "arm64"}
        seal_name = info_name.rsplit("/", 1)[0] + "/_CodeSignature/CodeResources"
        seal = archive.read(seal_name)
        assert seal and isinstance(plistlib.loads(seal), dict)
        result = {"path": str(path), "sha256": sha(path), "file_bytes": path.stat().st_size,
                  "zip_crc": "PASS", "executable_member": executable, "zip_create_system": info.create_system,
                  "executable_unix_mode": oct(mode), "execute_permissions": "0755", "architectures": architectures,
                  "code_resources": {"member": seal_name, "bytes": len(seal),
                                     "sha256": hashlib.sha256(seal).hexdigest(), "plist_parse": "PASS"},
                  "native_execution_tested_by_this_audit": False,
                  "apple_codesign_validation_executed": False, "apple_notarization_verified": False}
    return result


def main():
    report = {"status": "PASS", "audited_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "audit_kind": "Independent read-only binary structure and archive metadata inspection",
              "binaries": {"windows": audit_pck(RELEASE / "windows/DVD_BATTLE_1.5.1.exe"),
                           "linux": audit_pck(RELEASE / "linux/DVD_BATTLE_1.5.1.x86_64"),
                           "macos": audit_macos(RELEASE / "macos/DVD_BATTLE_1.5.1_macOS.zip")},
              "limitations": ["This audit did not execute any exported game on Windows, Linux or macOS.",
                              "Windows launch tests are reported separately in windows_smoke.json.",
                              "Linux and macOS native runtime behavior is not established by these structural checks.",
                              "Code signature presence and ad-hoc flags were inspected; Apple codesign verification, trust and notarization were not performed.",
                              "PCK magic, location and declared size were checked; this audit does not parse every packed resource."]}
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"status": report["status"], "report": str(OUTPUT)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
