# Engine fonts and licenses

Font files are not stored in this repository. The Dockerfile installs them from Debian packages,
and each package ships its license in `/usr/share/doc/<package>/copyright` inside the image.
`tool/check_fonts.js` fails the image build if any other font family is present.

| Font | Debian package | License |
|---|---|---|
| Noto Sans CJK KR / JP | fonts-noto-cjk | SIL Open Font License 1.1 |
| Noto Serif CJK KR / JP | fonts-noto-cjk-extra | SIL Open Font License 1.1 |
| NanumGothic, NanumMyeongjo, NanumBarunGothic | fonts-nanum | SIL Open Font License 1.1 |
| Liberation Sans / Serif / Mono | fonts-liberation2 | SIL Open Font License 1.1 |
| Carlito | fonts-crosextra-carlito | SIL Open Font License 1.1 |
| Caladea | fonts-crosextra-caladea | Apache License 2.0 |

Also present because LibreOffice and fontconfig depend on them: OpenSymbol (LibreOffice, MPL 2.0) and DejaVu (Bitstream Vera license).
Commercial fonts (함초롬, 맑은 고딕, 바탕, 굴림 and similar) are never installed; documents that use them are rendered
with the substitutes in `config/fontsubst.xcu`.
