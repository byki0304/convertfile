'use strict';
// Build-time guard: lists installed font families and fails if any is outside the free-license allow list.

const { execSync } = require('node:child_process');

const ALLOWED = [
  /^Noto (Sans|Serif)( Mono)? CJK/,
  /^Nanum/,
  /^Liberation/,
  /^Carlito$/,
  /^Caladea$/,
  /^OpenSymbol$/, // LibreOffice symbol font (MPL/LGPL, shipped with LibreOffice itself)
  /^DejaVu/, // Bitstream Vera derivative, free license; pulled in by fontconfig
];

// Each line lists one family with its localized aliases (e.g. "NanumGothic,나눔고딕"); one allowed alias is enough.
const families = new Set(
  execSync('fc-list : family', { encoding: 'utf8' })
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean),
);

const bad = [...families].filter((line) => !line.split(',').some((f) => ALLOWED.some((re) => re.test(f.trim()))));
console.log(`fonts: ${families.size} families`);
if (bad.length) {
  console.error(`Fonts outside the allow list: ${bad.join(', ')}`);
  process.exit(1);
}
