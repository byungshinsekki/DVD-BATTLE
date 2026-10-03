"""Run the exported Windows release and verify it leaves player settings intact."""
import json
import os
from pathlib import Path
import subprocess

from build_multiplatform_151 import REPORTS, RELEASE, sha, run_checked


def main():
    exe = RELEASE / "windows/DVD_BATTLE_1.5.1.exe"
    REPORTS.mkdir(parents=True, exist_ok=True)
    settings = Path(os.environ["APPDATA"]) / "Godot/app_userdata/DVD BATTLE · Godot Edition/settings.cfg"
    before = sha(settings) if settings.exists() else None
    version_cmd = "$v = (Get-Item -LiteralPath '" + str(exe).replace("'", "''") + "').VersionInfo; @{file=$v.FileVersion;product=$v.ProductVersion} | ConvertTo-Json -Compress"
    version = json.loads(subprocess.check_output(["powershell", "-NoProfile", "-Command", version_cmd], text=True))
    assert version == {"file": "1.5.1.0", "product": "1.5.1.0"}, version
    results = {}
    cases = {
        "startup": ["--headless", "--quit-after", "90"],
        "codex": ["--windowed", "--resolution", "1600x900", "--fixed-fps", "60", "--", "--goto=codex", "--codex=items/l_heart"],
        "battle": ["--windowed", "--resolution", "1600x900", "--fixed-fps", "60", "--", "--demo-dm=8/dm_ruined_town/777", "--warp=20", "--select=2"],
    }
    for name, args in cases.items():
        engine_log = REPORTS / f"windows_{name}_engine.log"
        args = ["--log-file", str(engine_log), *args]
        if name != "startup":
            args += ["--shot=" + (REPORTS / f"windows_{name}.png").as_posix(), "--shot-frames=120"]
        result = run_checked([exe, *args], f"windows_{name}.log", timeout=120)
        log = engine_log.read_text(encoding="utf-8", errors="replace")
        assert "SCRIPT ERROR" not in log and "ERROR:" not in log, log
        if name != "startup":
            shot = REPORTS / f"windows_{name}.png"
            assert shot.is_file() and shot.stat().st_size > 10_000 and "SHOT saved" in log
            result["screenshot"] = shot.name
        results[name] = result
    after = sha(settings) if settings.exists() else None
    assert before == after, "Player settings changed during smoke test"
    report = {"status": "PASS", "executable_sha256": sha(exe), "version": version,
              "player_settings_unchanged": before == after, "runs": results}
    (REPORTS / "windows_smoke.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
