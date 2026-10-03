# Bundled font sources

License: OFL-1.1. Sources are provided locally; this builder performs no downloads.

## glyph_serif

- Source file: `NotoSerifCJKkr-Black.otf`
- Family: Noto Serif CJK KR Black
- Version: Version 2.002;hotconv 1.1.0;makeotfexe 2.6.0
- SHA256: `55079040681047b067237f5c7555face4ba4970db53ae021d0492602e10666a8`
- Official origin: https://raw.githubusercontent.com/notofonts/noto-cjk/4efc595762d1f4b4fa504bccfe8e59de91fda063/Serif/OTF/Korean/NotoSerifCJKkr-Black.otf
- License: OFL-1.1 (http://scripts.sil.org/OFL)
- Output SHA256: `1732fb183cb8812665f3b1c15efc2fe1b483fd81f5332d8437092ee141567cc0`

Existing cmap entries are retained. New CJK/shape/arrow characters are collected from quoted script literals and extra_glyphs.txt.
Subsetting uses layout-features=*, name-IDs=*, name-languages=*, notdef-outline, canonical-order and no-recalc-timestamp.
Run the raw-font Godot test after reimport. Build manifests report unsupported source characters and the bundled union explicitly.
