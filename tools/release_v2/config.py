"""Single source of V2 release names and local tool paths."""
from pathlib import Path

VERSION = "2.0"
FILE_VERSION = "2.0.0.0"
MAC_VERSION = "2.0.0"
GAME_VERSION = "GD-2.0"
ENGINE_VERSION = "4.7.2.stable"
PROJECT = Path(__file__).resolve().parents[2]
SCRATCH = Path("D:/DVD20_CODEX_SCRATCH")
QA = Path("D:/DVD20_QA_CODEX/release_v2/project")
QA_PROFILE = "DVD_BATTLE_V20_CODEX_QA"
RELEASE = PROJECT.parent / f"DVD_BATTLE_{VERSION}_RELEASE"
GODOT = Path("D:/DVD_BATTLE_1.2.1_RECOVERY_WORK/tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe")
TEMPLATES = {
    "windows": Path("D:/DVD_BATTLE_1.2.1_RECOVERY_WORK/tools/godot-4.7.2/templates/windows_release_x86_64.exe"),
    "linux": Path("D:/DVD_BATTLE_BUILD_TOOLS/godot-4.7.2/templates/linux_release.x86_64"),
    "macos": Path("D:/DVD_BATTLE_BUILD_TOOLS/godot-4.7.2/templates/macos.zip"),
}
PLATFORMS = {
    "windows": ("Windows Desktop", f"windows/DVD_BATTLE_{VERSION}.exe"),
    "linux": ("Linux", f"linux/DVD_BATTLE_{VERSION}.x86_64"),
    "macos": ("macOS", f"macos/DVD_BATTLE_{VERSION}_macOS.zip"),
}
HELPER = PROJECT / "zz_work/tools/gd.ps1"
SPLIT_BYTES = 27 * 1024 * 1024
MAX_ATTACHMENT_BYTES = 28 * 1024 * 1024
ARCHIVE_TIME = (2026, 1, 1, 0, 0, 0)
PROFILE_NAMES = ["DVD_BATTLE_V20_DEVELOPER", "DVD_BATTLE_V153_DEVELOPER", "DVD_BATTLE_V152_DEVELOPER"]
EXCLUDED_PARTS = {".git", ".godot", ".claude", "zz_work", "zz_diag", "__pycache__"}
