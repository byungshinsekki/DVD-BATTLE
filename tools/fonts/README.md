# 번들 폰트 재생성

`build_fonts.py`는 로컬 원본 폰트에서 필요한 글자만 추려 `assets/fonts/glyph_serif.otf`를 재생성합니다. 다운로드나 패키지 설치는 수행하지 않습니다. Python과 `fontTools`가 필요하며, 사전 검증 환경은 Python 3.14.6 / fontTools 4.66.1입니다.

공식 원본은 **Noto Serif CJK KR Black, Serif 2.002, 정적 CFF OpenType**입니다. 다음 고정 출처와 SHA를 사용합니다.

- [공식 원본](https://raw.githubusercontent.com/notofonts/noto-cjk/4efc595762d1f4b4fa504bccfe8e59de91fda063/Serif/OTF/Korean/NotoSerifCJKkr-Black.otf)
- 저장소 커밋: `4efc595762d1f4b4fa504bccfe8e59de91fda063`
- 원본 SHA256: `55079040681047b067237f5c7555face4ba4970db53ae021d0492602e10666a8`
- 라이선스: [OFL-1.1 원문](https://raw.githubusercontent.com/notofonts/noto-cjk/4efc595762d1f4b4fa504bccfe8e59de91fda063/Serif/LICENSE)
- 이 작업 환경의 로컬 원본: `D:\DVD20_CODEX_SCRATCH\fonts\NotoSerifCJKkr-Black.otf`
- 준비된 Python: `D:\DVD20_CODEX_SCRATCH\fonts\venv\Scripts\python.exe`

프로젝트 루트에서 아래 순서로 실행합니다. `$fontPython`, `$serifSource`는 다른 환경의 로컬 경로로 바꿀 수 있습니다. 원본 SHA 확인은 실행 전 별도로 수행해야 하며 `--source-url`은 출처 기록용입니다.

```powershell
$fontPython = 'D:\DVD20_CODEX_SCRATCH\fonts\venv\Scripts\python.exe'
$serifSource = 'D:\DVD20_CODEX_SCRATCH\fonts\NotoSerifCJKkr-Black.otf'
$serifOrigin = 'https://raw.githubusercontent.com/notofonts/noto-cjk/4efc595762d1f4b4fa504bccfe8e59de91fda063/Serif/OTF/Korean/NotoSerifCJKkr-Black.otf'
& $fontPython -B tools/fonts/build_fonts.py --serif-source $serifSource --source-url $serifOrigin --audit-only --out zz_work/measure/C7/audit
```

`font_audit.json`의 `requested_uncovered_after_plan`, `source_absent_requested`, `ui_missing_before`를 검토한 뒤 생성합니다. `--audit-only`는 폰트 파일을 교체하지 않고 보고서만 기록합니다. 감사의 종료코드 0만으로 누락 없음이나 UI 표시 성공을 판단하지 않습니다.

```powershell
& $fontPython -B tools/fonts/build_fonts.py --serif-source $serifSource --source-url $serifOrigin --out zz_work/measure/C7/build
```

각 실행은 기존 폰트의 모든 Unicode cmap을 보존하고, 현재 `scripts/**/*.gd`의 문자열 리터럴에서 한자·CJK 기호·도형·화살표를 다시 수집합니다. 주석은 제외하며 Unicode 이스케이프도 읽습니다. `extra_glyphs.txt`는 아직 코드에 없는 예정 글자와 자동 수집 범위 밖 기호를 추가합니다. 새 영웅 병합 후 같은 명령을 다시 실행하면 해당 범위의 새 글자가 포함됩니다. 임의의 새 한글이나 모든 Unicode 블록을 자동 수집하는 도구는 아닙니다.

원본이 기존 cmap을 보존하지 못하거나 번들 합집합에 필수 글자가 남지 않거나 세리프 결과가 **1,500,000바이트**를 넘으면 생성에 실패합니다. 결과와 SHA는 `font_audit.json`, 출처·버전·라이선스는 `tools/fonts/FONT_SOURCES.md`에 기록합니다. 정적 CFF 원본을 사용하므로 `.otf` 경로를 유지하며 VF/TrueType 입력은 이 흐름에서 거부합니다.

UI 폰트는 기본적으로 재생성하지 않습니다. 사전 감사에서 `ui_regular/bold/black` 각각 `寶屋岩據政林癒` 7자가 없었지만, 실제 사용은 `CodexScreen._fact_row → UITheme.glyph_tile → DB.font_glyph`와 정치가 `glyph → GlyphDisc/전투 glyph → DB.font_glyph` 경로입니다. 이 근거로 현재 작업은 세리프만 재생성합니다. 세 얼굴의 cmap이 완전하다는 뜻은 아닙니다. 새로운 UI 본문에 누락 문자를 쓰게 되면 사용 위치를 다시 확인하고, 적절한 공식 로컬 UI 원본과 `--rebuild-ui`, 필요한 `--ui-regular-source/--ui-bold-source/--ui-black-source`, `--ui-source-url`을 명시합니다. Sans 원본을 자동으로 받지 않습니다.

재현성을 확인할 때는 원본 SHA, 기존 cmap, 코드와 extra_glyphs의 수집 결과, Python/fontTools 버전을 고정하고 서로 다른 보고서 폴더로 두 번 생성하여 출력 SHA를 비교합니다. 빌더는 코드포인트를 정렬하며 `--no-recalc-timestamp`, `--canonical-order`, `SOURCE_DATE_EPOCH=0`을 사용합니다. 입력에 새 글자가 추가되면 이전 결과와 다른 SHA가 정상일 수 있습니다.

생성 후 Godot 가져오기 검사를 먼저 수행하고 `res://tests/fonts_v2.gd`를 실행합니다. 검사는 `CACHE_MODE_IGNORE`로 `glyph_serif`·`ui_black`·`symbols`를 새로 읽고, resource fallback과 시스템 fallback을 모두 끈 상태에서 현재 영웅·스킬·상태·역할·개체·아이템·도감 글리프를 검사합니다. `政報誘宣訊默`는 세리프 자체에 있어야 합니다. 이 합집합 검사가 UI 개별 폰트의 모든 본문을 보증하지는 않습니다. 이어 기존 25종 검사, `codex_ui_151`을 포함한 UI 장면 5종, 정치가 도감 화면(`--goto=codex --codex=chars/politician`)의 실제 글꼴을 확인합니다. 테스트 보고서는 기본 `zz_work/measure/C7/fonts_v2.json` 또는 `--report`로 지정한 경로에 기록됩니다.

사전 검증은 별도 프로젝트에서 완료했습니다. 기존 237 cmap을 유지한 결과는 **307 cmap / 242,168바이트**, 반복 생성 SHA는 모두 `0a8d6590024862eea52dd9ec0e681805d14cf432add9a98d3709e41c3c4eb226`이었습니다. 별도 Godot 가져오기와 원본 폰트 검사는 **501 PASS / 0 FAIL / 133개 고유 코드포인트**였습니다. 이는 당시 입력의 증거이며, 이 안내서 작성 시점에는 본 프로젝트 C7 적용 전입니다. 최종 소스에 적용한 뒤 다시 검사하고, 이후 글자가 늘어나면 크기·SHA·검사 개수가 달라질 수 있습니다.
