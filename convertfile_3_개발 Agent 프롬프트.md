# convertfile 개발 Agent 프롬프트 (기획서 0.4 기준)

> 사용법: 아래 `---` 사이의 전체 내용을 개발 Agent에게 그대로 전달한다.
> `{ }`로 표시된 배포 정보는 코딩을 시작할 때 확정된 Firebase, GitHub, Vercel 내역으로 바꾼다.

---

## 0. 너의 역할과 작업 방식

너는 이 프로젝트의 단독 풀스택 개발자다. 아래 명세대로 **convertfile / AI 문서 변환 작업대**를 처음부터 끝까지 구현한다.

1. **기준 문서:** 프로젝트 폴더의 `convertfile_2_업무용 프로그램 개발 표준 세부 기획서.md`(0.4)가 최종 기준이다. 이 프롬프트와 기준 문서가 다르면 기준 문서를 따르고, 다른 점을 나에게 알린다. `업무용 프로그램_개발 표준 세부 기획서_1_4.txt`는 공통 고정 정책의 원문이다.
2. **명세에 없는 기능은 만들지 않는다.** 12장 '구현하지 말 것'에 있는 항목은 절대 넣지 않는다. 명세가 모호하면 추측해서 기능을 늘리지 말고 질문한다.
3. **단계별로 진행한다.** 13장의 단계 순서를 지키고, 단계마다 끝에 검사 명령을 돌린 뒤 결과(통과/실패, 남은 문제)를 보고하고 다음 단계로 간다.
4. **필요한 것은 필요한 단계에서 요청한다.** Firebase 프로젝트, GitHub 저장소, Vercel 프로젝트, API 키는 해당 단계에 도달했을 때 나에게 요청한다. 키 값을 코드, 문서, 대화 기록, 커밋에 쓰지 않는다. 나에게 받은 키는 `firebase functions:secrets:set` 명령으로 Secret Manager에만 넣도록 안내한다.
5. **가짜 데이터 금지.** 시드 데이터, 가짜 환율, 가짜 변환 결과, 목업 응답으로 화면을 채우지 않는다. 데이터 없음 상태와 실제 서버 호출만으로 핵심 시나리오가 끝나야 한다.
6. **코드 언어:** 필드, 함수, 경로, 오류 코드, 이벤트 코드는 영어다. 화면 문장만 한국어(기준), English, 日本語 3개 언어로 바뀐다.

## 1. 프로젝트 정보

```text
프로젝트: convertfile / AI 문서 변환 작업대
기획 기준: 업무용 프로그램 개발 표준 세부 기획서 1.4 / convertfile 0.4 / 2026-10-19
한 줄 약속: 가운데 입력창에 말하거나 파일을 넣으면 AI가 알맞은 메뉴로 안내하고, 한글·PDF·오피스·Markdown·텍스트 문서를
          원하는 형식으로 바꾸거나 PDF를 합치고 정리해 바로 내려받게 한다.
저장소: {GitHub 저장소 주소}, 브랜치 main
Firebase 프로젝트 ID: {Firebase 프로젝트 ID}
Vercel 프로젝트: {Vercel 프로젝트 이름 / 주소}
리전: asia-northeast3 (Functions, Cloud Run, Cloud Tasks 모두)
로컬 확인: flutter run -d chrome / docker run -p 8081:8080 convert-engine
```

## 2. 스택

| 영역 | 기술 |
|---|---|
| 클라이언트 | Flutter 웹 PWA, Riverpod 3. go_router 없이 선택 상태(provider)로 메뉴와 탭을 바꾼다 |
| PDF(브라우저) | `pdf-lib`(MIT)를 `web/js/pdf_tools.js`에 두고 `dart:js_interop`으로 호출(병합, 페이지 삭제·이동·추출). 썸네일 `pdfrx`(MIT). 인쇄 `printing`(Apache-2.0). **Syncfusion은 쓰지 않는다** |
| 서버 | Node.js 22 Cloud Functions v2 (Admin SDK) |
| 변환 엔진 | Cloud Run 서비스 `convert-engine`: Node.js 22 컨테이너 + LibreOffice(헤드리스) + H2Orestart 확장(hwp·hwpx 읽기) + Pandoc + `mammoth`, `turndown`, `markdown-it`, `pdfjs-dist`, `exceljs`, `pptxgenjs`, `docx`, `jszip`. 메모리 8GiB, CPU 4, 동시 처리 1, 시간 제한 1800초, 최소 인스턴스 0, 최대 5, 비인증 호출 금지 |
| 작업 큐 | Cloud Tasks `convert-queue`: 엔진을 OIDC 토큰으로 호출, dispatchDeadline 1800초, 최대 시도 2회 |
| 주 저장소 | Firebase Auth, Firestore 이름 있는 DB `convertfile`(`(default)` DB는 쓰지 않음), Storage 기본 버킷 |
| 보조 저장소 | 같은 프로젝트 Firestore DB `convertfile-backup`. 트리거로만 복제, 클라이언트 접근 금지 |
| AI | Gemini REST `generateContent`, `responseMimeType: application/json` + `responseSchema`, thinkingLevel `low` |
| 외부 API | ExchangeRate-API v6 (KRW 기준), 서버 캐시 60분 |
| 호스트 | Vercel. `main` 푸시로 배포, 빌드 `bash tool/vercel-build.sh`(Flutter가 없으면 stable을 받아 `flutter build web --release`), 출력 `build/web`, 모든 경로를 `index.html`로 리라이트(`vercel.json`) |
| 비밀 | Secret Manager: `GEMINI_API_KEY`, `EXCHANGE_RATE_API_KEY` |
| 일반 환경 변수 | `GEMINI_MODEL`(기본 `gemini-3.8-flash`), `GEMINI_MODEL_VISION`(기본값은 GEMINI_MODEL과 같음), `ENGINE_URL` |

## 3. 폴더 구조

```text
lib/main.dart                 진입, 테마, 로케일, ProviderScope, 로그인→셸
lib/pages/app_shell.dart      프레임 판정, 사이드바/레일/하단 탭, 그룹 탭, 헤더 버튼, 팝업 계산기 Overlay
lib/pages/layouts/            desktop_layout.dart, phone_landscape_layout.dart, portrait_layout.dart
lib/features/ai_home/         입력 카드, 음성, 파일 첨부, 대화 목록, 안내 카드, 프리셋
lib/features/convert/         변환 메뉴 7개 공통 화면, 형식 표(file_rules와 공유), 변환 기록 목록
lib/features/pdf_merge/       PDF 합치기
lib/features/pdf_edit/        PDF 편집
lib/features/calculator/      popup/, full/(basic, scientific, fx, business), 계산 기록
lib/features/history/         마이페이지 전체 변환 기록
lib/features/account/         마이페이지, 비밀번호 변경, 읽기 설정, 탈퇴, 연동 서비스
lib/features/auth/            로그인, 가입, 게스트, Google, 휴대폰 로그인
lib/shared/                   api, state, logic, theme, widgets, app_text(i18n), errors, file_rules, phone_login
functions/index.js            Functions 전체
functions/.env.example        변수 이름만
engine/Dockerfile, engine/server.js
engine/converters/            libreoffice, pandoc, docir(문서 중간 형식), pptx, xlsx, hwpx, text, ocr
engine/templates/hwpx/        OWPML 템플릿
engine/fonts/                 무료 글꼴과 각 LICENSE 파일
engine/config/fontsubst.xcu   LibreOffice 글꼴 대체 설정
web/js/pdf_tools.js           pdf-lib 래퍼
web/index.html, web/manifest.json, web/icons/, web/favicon.ico, web/brand/(prompts.md, thumbnails/, states/)
app_icons/app_icon_master.png
tool/make_icons.py, tool/vercel-build.sh
assets/images/                foldy_wave, foldy_run, foldy_point, foldy_head, foldy_logo (.webp)
test/, test/fixtures/         형식별 샘플 문서(직접 만든 것, 개인정보 없음. 앱 번들에 넣지 않음)
firestore.rules, storage.rules, firebase.json, vercel.json
```

## 4. 공통 고정 정책 (모든 코드에 적용)

1. 생성, 수정, 삭제, 만료, 용량, 권한, 외부 조회 저장, 잔액 계산은 Node.js 서버가 확정한다.
2. 서버가 성공하기 전에는 화면에 반영 완료를 보이지 않는다.
3. 관리용 ID를 쓰면 화면, 통계, 클라이언트가 읽는 문서에 넣지 않는다.
4. 데이터 없음 상태와 실제 서버 호출만으로 핵심 시나리오가 끝나야 한다. 가짜 데이터와 시드 데이터를 넣지 않는다.
5. 개발용 진단은 프로덕션 빌드에 없다.
6. 주 저장소는 이 프로그램의 Firebase 하나다. 다른 프로그램의 키를 넣지 않는다.
7. 소스, 시드, 환경 예시에 관리자 비밀번호와 API 키를 넣지 않는다. 키는 서버 비밀로만 둔다.
8. 참고 제품의 로고와 아이콘 파일을 넣지 않는다(Microsoft, 한컴, Adobe 포함).
9. 서비스 워커를 쓰지 않는다. 예전 서비스 워커와 캐시는 `index.html`에서 지우고 한 번 새로고침한다.
10. 통계와 관리 화면에 본문과 파일 바이트를 그리지 않는다.
11. 브랜드 프롬프트 7종을 `web/brand/prompts.md`에 쓰고, 아이콘은 원본 한 장에서 스크립트로 만든다.
12. 통계를 쓰면 비회원과 로그인 사용자를 나눠 센다. 실패와 재시도로 숫자를 중복하지 않는다(이 프로젝트는 통계 해당 없음).
13. 비회원을 계정에 연결하면 같은 uid의 데이터를 유지한다.
14. 탈퇴 문안과 삭제 범위, 남는 데이터가 같아야 한다.
15. 감사 로그에는 행위와 필드 이름만 남기고 이전 본문은 남기지 않는다.
16. `해당 없음`과 MVP 이후 항목은 구현하지 않는다.
17. 화면 문장만 한국어, English, 日本語로 바꾸고, 코드와 데이터베이스 항목은 영어로 둔다.
18. AI는 서버에서 스키마 JSON(enum과 필수 칸)으로만 받는다. 키워드로 메뉴를 고르지 않는다. 실패하면 한 번 다시 묻고, 그래도 안 되면 사실대로 알린다.
19. 클라이언트는 자기 uid 아래만 읽고, 쓰기는 Admin SDK만 한다. 주 DB는 삭제 보호를 켜고, 보조 DB는 서버 트리거로만 복제한다.
20. 글자크기·줄간 거리 5단계와 행 펼치기(탭 또는 더블클릭, 체크는 체크박스만)를 기본 UI로 넣는다.
21. 변환은 Cloud Run 엔진만 하고, 결과 파일 크기를 확인한 뒤에만 done으로 쓴다.
22. 형식 허용 여부는 형식 표 코드로만 판정한다. AI가 고른 메뉴도 형식 표로 다시 검사한다.
23. PDF 합치기·편집은 브라우저에서만 처리하고 파일을 서버로 보내지 않는다.
24. 결과 파일은 서명 주소로만 내려받고, 업로드 원본과 결과는 168시간 뒤 사라진다.
25. 비밀번호는 인증 제공자만 저장한다. DB에 비밀번호나 해시를 쓰지 않는다. 로그인 실패 문장은 계정 없음과 비밀번호 틀림을 구분하지 않는다.
26. 엔진과 화면에 넣는 글꼴은 무료 라이선스(SIL OFL 1.1, Apache-2.0)만 쓴다.

## 5. 사용자와 한도

| 항목 | 로그인 사용자 | 게스트(익명 인증) |
|---|---|---|
| 기능 | 전부 | 전부(같음) |
| 파일 하나 최대 크기(변환·AI 첨부) | 1GB (1,073,741,824바이트) | 100MB (104,857,600바이트) |
| 하루 사용 용량(변환·AI 첨부 원본 크기 합계, 서버가 셈) | 1GB | 100MB |
| PDF 도구 한 작업 합계(브라우저가 확인, 하루 용량에 넣지 않음) | 1GB | 100MB |
| 하루 AI 호출 횟수 | 200회 | 30회 |
| 대화 보존 | 사용자가 지울 때까지 | 168시간 |
| 변환 기록·원본·결과 보존 | 168시간 | 168시간 |

- 하루는 Asia/Seoul 00:00 기준. `users/{uid}/usage/{yyyyMMdd}`를 서버가 트랜잭션으로 센다. 변환 횟수 제한은 없다.
- AI 호출은 `submitPrompt`, `summarizeConversion`, 변환 안의 AI 호출(구조화, 슬라이드, 표, OCR)을 각각 1회로 센다. 같은 요청 안의 자동 재시도 1회는 세지 않는다. 넘으면 `ai-quota-exceeded`이고, AI가 필요한 변환(pdf→md·docx·pptx·xlsx, →pptx, OCR)은 시작 전에 거절한다.
- 실패한 변환 작업의 용량은 하루 사용 용량에서 빼 준다.
- PDF 도구 합계가 300MB를 넘으면 `파일이 커서 기기에 따라 느리거나 멈출 수 있습니다.`를 보인다.
- 업로드는 Firebase Storage 이어 올리기(resumable)로 한다. 파일 전체를 메모리에 읽지 말고 Blob을 그대로 올린다. 진행률을 보이고, 끊기면 이어서 올린다.
- 게스트가 한도에 걸리면 `로그인하면 1GB까지 쓸 수 있습니다.`를 덧붙인다.

## 6. 화면

### 6.1 메뉴 구조

- 그룹 4개: `AI 홈` / `파일 변환`(탭: Markdown, PDF, Word, PowerPoint, Excel, 한글, 텍스트) / `PDF 도구`(탭: 합치기, 편집) / `계산기`(탭: 기본, 공학, 환율, 업무)
- 원안 메뉴 번호: 1 AI 홈, 2~8 변환(→MD, →PDF, →DOCX, →PPTX, →XLSX, →HWPX, →TXT), 9 PDF 합치기, 10 PDF 편집, 11 전체화면 계산기
- 헤더 오른쪽 위(모든 프레임): 언어 버튼(누를 때마다 한국어→English→日本語), `[계산기] [로그아웃] [마이페이지(아바타)]`

### 6.2 프레임 (세 레이아웃 파일을 따로 만들고 실행 중 바로 바꾼다)

- 판정: 너비 ≤ 높이이면 **스마트폰 세로**. 가로이면서 높이 < 600 또는 너비 < 820이면 **스마트폰 가로**. 그 외 **데스크톱**.
- **데스크톱:** 헤더 높이 64(왼쪽 로고 = AI 홈). 왼쪽 사이드바 너비 232(창 너비 < 1180이면 아이콘만 76)에 그룹 4개. 본문 위에 그룹별 탭. 본문 최대 너비 1100. 변환 화면은 너비 ≥ 1000이면 업로드 40 : 기록 60 좌우 분할, 아니면 위아래.
- **스마트폰 가로:** 왼쪽 너비 58 레일(위쪽 로고 = 홈, 그룹 아이콘 4개). 위쪽 띠 왼쪽은 탭(가로 스크롤), 오른쪽은 언어, 계산기, 로그아웃, 아바타.
- **스마트폰 세로:** 헤더 56(로고, 언어, 계산기, 로그아웃(너비 < 370이면 아이콘만), 아바타). 그 아래 탭 칩 줄(가로 스크롤). 맨 아래 하단 탭 4개. 키보드가 올라오면 하단 탭을 숨긴다.
- 회전·크기 변경 시 선택 메뉴와 탭, 입력 중인 문장, 고른 파일, PDF 합치기 순서, 편집 상태, 계산 상태, 팝업 위치를 유지한다(상태는 Riverpod에 두고 레이아웃만 바꾼다).
- 짧은 화면에서 모든 메뉴는 통째로 스크롤된다. PDF 그리드 위의 세로 끌기는 길게 누르지 않으면 화면 스크롤로 넘긴다.

### 6.3 화면별 명세

**로그인 / 가입**
- 로그인: 로고, `ConvertFile`, `말하거나 파일을 넣으면, 필요한 형식으로 바꿔 드립니다.`, 버튼 순서 이메일 로그인 → 휴대폰번호 로그인 → Google로 로그인 → 게스트로 시작 → `처음이면 신규가입`, `로그인 상태 유지`(기본 켬, 끄면 SESSION), 언어 3버튼.
- 가입: 이메일 가입, 휴대폰번호 가입. 비밀번호와 확인.
- 세션이 없으면 로그인 화면, 있으면 AI 홈. 인트로 영상은 없다.

**AI 홈 (메뉴 1)**
- 입력 카드: 입력칸(데스크톱 2–5줄, 휴대폰 한 줄 + 양옆 아이콘), 파일 첨부, 음성 입력(브라우저 음성 인식), 실행. Enter 보내기, Shift+Enter 줄 바꿈. 고른 파일은 형식 색 알약, 누르면 취소.
- 프리셋 3개: `이 파일 PDF로 바꿔줘`, `이 문서 3줄로 요약해줘`, `100달러는 몇 원이야?`(환율 탭을 연다). 파일이 필요한 프리셋은 파일이 없으면 선택 창을 먼저 연다.
- `대화 & 안내` 목록: 최신이 맨 위. 한 턴 = 사용자 말풍선(흰색) + AI 말풍선(`#EAF0FF`). 말풍선마다 체크박스. 입력 쪽과 답 쪽을 따로 지울 수 있다.
- AI 말풍선 안의 안내 카드: 원본→결과 형식 색 카드, 메뉴 이름, `[바로 변환] [메뉴로 이동]`. [메뉴로 이동]은 첨부 파일을 들고 이동만 하고, [바로 변환]은 이동과 변환 시작을 함께 한다. AI가 메뉴를 저절로 바꾸지 않는다.
- 빈 대화: `"이 한글 파일 PDF로 바꿔줘"처럼 말하거나 파일을 넣어 보세요. 알맞은 메뉴로 안내합니다.` + 가리키는 폴디. 입력 힌트: `변환할 형식이나 궁금한 것을 말하거나 파일을 넣으세요.`
- 빈 전송: `내용을 입력하거나 파일을 선택해 주세요.`

**변환 메뉴 2~8 (공통 화면 하나 + 결과 형식 파라미터)**
- 제목(`PDF로 변환` 등), 가능 형식 알약, 업로드 영역(데스크톱 끌어다 놓기 가능), 선택 파일 알약, 변환 방식 표시(`레이아웃 유지` / `내용 중심` / `표 추출`), [변환 시작].
- `최근 변환 기록`(그 결과 형식만, 10건씩): 형식 색 카드, 원본 이름 1줄, 원본→결과, 상태 알약, 크기, `N시간 후 삭제`, [내려받기], [3줄 요약]. 펼치면 원본 이름 전체, 방식, 페이지 수, 3줄 요약, 실패 이유, 글꼴 대체 안내. 결과가 PDF이면 [PDF 편집으로 열기].
- 진행: 기록 맨 위에 행이 생기고 `올리는 중 n%` → `대기 중` → `변환 중` → `완료`/`실패`(작업 문서 실시간 스트림). `완료`와 [내려받기]는 서버가 결과 파일 크기를 확인한 뒤에만.
- 다른 메뉴에 있을 때 끝나면 스낵바 `'{파일명}' 변환을 마쳤습니다. [내려받기]`.
- 빈 기록: `아직 변환한 파일이 없습니다. 파일을 올리거나 홈 입력창에 말해 주세요.`

**PDF 합치기 (메뉴 9, 브라우저 처리)**
- 업로드 칸 5개(번호, 썸네일, 파일명, 페이지 수, 크기, 끌기 손잡이, ×). `[+ 5칸 더 보기]`로 5개씩 늘려 최대 20칸. 위에서 아래로 차례대로 올린다.
- 끌어서 순서 변경(데스크톱 손잡이, 휴대폰 길게 누르기) + 접근성용 [위로] [아래로]. 합계 페이지·용량. [합치기] → `merged_{yyyyMMdd_HHmm}.pdf` 내려받기, `PDF를 만들었습니다. 내려받기를 시작합니다.`
- 빈 상태: `PDF 파일을 올려 주세요. 최대 20개까지 합칠 수 있습니다.`

**PDF 편집 (메뉴 10, 브라우저 처리)**
- 페이지 썸네일 그리드(썸네일 너비 140, 휴대폰 100, 칸 수 자동). 페이지마다 번호와 체크박스. 끌어서 페이지 이동.
- `전체 선택`, [선택 삭제], [선택 페이지만 저장](`{원본}_pages.pdf`), [선택 페이지만 인쇄], [되돌리기], [저장](`{원본}_edited.pdf`). 최대 500페이지.
- 저장하지 않고 떠나면 확인 대화상자. 암호 PDF는 `암호가 걸린 파일은 변환할 수 없습니다.`와 같은 형식의 거절.
- 빈 상태: `편집할 PDF 파일 하나를 올려 주세요.`

**팝업 계산기**
- 헤더 [계산기]로 연다. Overlay로 모든 메뉴 위에 뜨고, 메뉴를 옮겨도 값이 유지된다.
- 처음 위치는 본문 왼쪽 위(16, 16). 크기 데스크톱 260×380, 휴대폰 220×330. 기본형 사칙연산.
- 계산기 머리 왼쪽부터 `[Off] [전체화면]`, 제목 `계산기`. 머리를 잡고 끌어 이동, 화면 밖으로 나가지 않게 막는다. 위치는 프레임별로 기기에 저장(`calcPopupPos.{frame}`).
- [Off]는 닫기. [전체화면]은 지금 값을 들고 메뉴 11의 기본 탭으로 가고 팝업을 닫는다. 키보드 숫자·연산자 입력.

**전체화면 계산기 (메뉴 11)**
- 기본 / 공학(sin, cos, tan, log, ln, √, xʸ, π, e, 괄호, DEG/RAD) / 환율(USD, EUR, JPY(100엔 기준), CNY, GBP, HKD, SGD, AUD, 기준 시각 표시, 양방향 환산, `getExchangeRates` 결과만 사용) / 업무(부가세 공급가↔합계, 할인율·마진율, 날짜 차이·영업일 수).
- 계산 기록은 기기에만(`calcHistory.{uid}`, 최대 100건). 빈 기록: `= 을 누르면 계산 결과가 여기에 남습니다.`

**마이페이지**
- 프로필 카드: 아바타, 표시 이름(Google 이름 → 휴대폰 번호 → 이메일 앞부분 → `게스트`), ID(이메일 또는 휴대폰, 게스트는 `게스트`), 비밀번호 `••••••••`와 [비밀번호 변경], `Google 연결됨`/`게스트` 알약.
- 비밀번호 변경(이메일·휴대폰 계정만): 현재·새·확인 입력 → `reauthenticateWithCredential` → `updatePassword`. 성공 `비밀번호를 변경했습니다.` 실패 `현재 비밀번호가 맞지 않습니다.` Google 계정은 `Google 계정으로 로그인 중입니다. 비밀번호는 Google에서 관리합니다.` 게스트에게는 버튼을 보이지 않는다.
- 오늘 사용량 카드: `312.4MB / 1GB` 형식과 막대, AI `n / 200회`.
- 최근 변환 기록(전체 형식, 10건씩). 빈 상태 `최근 7일 동안 변환한 파일이 없습니다.`
- 설정 카드: 언어 3버튼, 글자크기 5단계(기본 3단계, 단계마다 ±10%), 줄간 거리 5단계(기본 4단계, 기준 1.45배, 단계마다 ±10%). `MaterialApp.builder`의 ReadingScale로 모든 화면에 적용, 기기에 저장.
- 연동 서비스 카드: `Firebase · 주 DB N건`, `Google Cloud · 보조 DB N건`, 마지막 복제 시각, `보조 DB 동기화`, 새로고침.
- 게스트면 `Google 계정 연결`(linkWithPopup, 같은 uid 유지).
- `AI 대화 기록 초기화`(확인 필요), 맨 아래 `탈퇴` 링크와 `로그아웃` 버튼.
- AI 안내: `AI 기능을 쓰면 문서 내용이 Google Gemini로 전송됩니다.`(업로드 영역에도 표시)

**탈퇴**
- 확인 문구: `계정과 변환 기록, 업로드·결과 파일, AI 대화, 사용량 기록을 삭제합니다. 이 기기의 계산 기록도 지워지고, 언어와 글자 설정만 남습니다.` 붉은 `탈퇴`로 확정.
- 서버 `withdraw`: conversions, turns, usage, 그 사용자의 감사 로그, `uploads/{uid}/`, `outputs/{uid}/`, 보조 DB `users/{uid}`, Auth 사용자 삭제. 화면은 `calcHistory.{uid}`를 지우고 로그인 화면으로.

**게스트 로그아웃 경고:** `게스트로 로그아웃하면 이 기록으로 다시 들어올 수 없습니다. 먼저 Google 계정을 연결하면 기록이 유지됩니다.`

### 6.4 공통 UI 규칙

- 목록 행은 접힌 상태가 기본. 휴대폰은 한 번 탭, 데스크톱은 더블클릭으로 그 행만 펼치고 접는다. 체크는 체크박스로만.
- 선택 토글: 체크가 없으면 버튼은 `전체 선택`, 하나라도 있으면 `삭제`. 삭제는 확인 대화상자 `선택한 N개를 삭제합니다. 파일도 함께 지워집니다.` 삭제 중 버튼 막기. 목록이 바뀌면 사라진 ID의 체크와 펼침을 지운다.
- 변환 중(running) 기록은 지우지 않는다: `변환 중인 항목은 끝난 뒤 지울 수 있습니다.`
- 상태 알약: 대기 회색, 변환 중 남색+진행 막대, 완료 초록, 실패 빨강. 항상 글자와 함께.
- 크기는 KB/MB 소수 1자리. 숫자는 로케일 형식.
- 애니메이션: 탭 전환 200ms, 행 펼치기 200ms, 팝업 열고 닫기 180ms, 끌기 중 카드 1.03배와 그림자. 프레임 전환은 지연 없이. 소리 없음.
- Semantics 이름: 체크박스, 펼치기, 끌기 손잡이, 계산기 키, 모든 버튼. 큰 글자(5단계)에서도 넘침 없음.
- 오프라인: 큐를 만들지 않는다. 주 DB 스트림이 실패하면 `readBackup` 결과를 보이고 `Firebase 연결이 끊겨 보조 DB에서 읽는 중입니다. 내려받기는 연결 후 가능합니다.` 띠. PDF 도구와 계산기(환율 제외)는 오프라인에서도 동작.

## 7. 브랜드

- 스타일: 연한 회청색 모눈 작업대 위에, 굵은 남색 선과 딱딱한 그림자를 가진 둥근 파일 카드들이 노란 순환 화살표를 따라 다른 색 카드로 바뀌고, 그 옆에 모서리가 접힌 흰 문서 캐릭터가 서 있다.
- 카드: 남색 테두리 1.8px, 딱딱한 그림자(0, 3), 모서리 반경 16.
- 캐릭터 `폴디`: 흰 종이 몸, 오른쪽 위 접힌 모서리, 동그란 눈, 노란 순환 화살표. 포즈 wave, run, point, head, logo. 데이터 없음 = point, 완료 = wave, 오류 = 어지러운 폴디 + 분홍 카드.
- 로고: 폴디 + `ConvertFile`(굵기 900, `#1F2A4D`).
- 색: 배경 `#EEF1F6`(모눈 `#DDE3EC`), 종이 `#FFFFFF`, 글자 `#1F2A4D`, 보조 `#6B7280`, 주색 `#2F4AA8`, 강조 `#FFC94A`, AI 말풍선 `#EAF0FF`, 위험 `#E5484D`, 확인 `#2FA36B`.
- 형식 색: MD `#4B5563`, PDF `#E5484D`, DOCX `#2F6FE4`, PPTX `#F2783B`, XLSX `#2FA36B`, HWPX `#1FA3B8`, TXT `#B8A47A`, 계산기 `#8E99A8`. 형식 표시는 직접 그린 색 둥근 카드 + 확장자 글자(이미지 파일 없음).
- 화면 글꼴: Noto Sans KR / Noto Sans JP / Noto Sans (google_fonts, SIL OFL 1.1).
- PWA: 이름 `ConvertFile`, `id`·`scope` `/`, `lang` ko, `display` standalone, 배경 `#FFFFFF`, 테마 `#2F4AA8`. `index.html`에 theme-color, apple-touch-icon, favicon.ico, favicon-32, favicon-16.
- 아이콘: `app_icons/app_icon_master.png`(1024, 남색 바탕 위 흰 폴디와 노란 화살표, 글자 없음)에서 `python tool/make_icons.py`(Pillow)로 any 6종(96, 144, 192, 256, 384, 512, 모서리 반경 22%), maskable 2종(192, 512, 90% 크기), apple-touch-icon 180, favicon 16·32·ico 생성. 원본 이미지가 없으면 나에게 요청하고, 그동안은 색과 단순 도형으로 대신한다.
- `web/brand/prompts.md`에 아래 7종을 그대로 쓴다.

```text
[공통]
앱: convertfile / AI 문서 변환 작업대
스타일: (위 스타일 문장)
한 줄 약속: 말하거나 파일을 넣으면 알맞은 메뉴로 안내하고, 문서를 원하는 형식으로 바꾸거나 PDF를 합치고 정리해 바로 내려받게 한다
제외: 워터마크, 실제 사람 사진, 작은 글자, 다른 제품의 로고(Microsoft, 한컴, Adobe 포함)

1) 데스크톱 아이콘 / 남색 둥근 사각형 안의 흰 폴디 전신과 노란 순환 화살표, 글자 없음 / 1024×1024
2) 모바일 아이콘 / 정면으로 확대한 폴디, 접힌 모서리와 화살표만 크게, 여백 최소 / 1024×1024, 가운데 80% 안전 영역
3) 썸네일 스틸 / 입력창에 청록 HWP 카드가 들어가고 폴디가 빨간 PDF, 파란 Word, 초록 Excel 카드를 양옆에 내놓는다 / 1280×720
4) 썸네일 GIF 3초 / 0초 빈 입력창, 1초 HWP 카드 진입, 2초 화살표 회전, 3초 PDF 카드와 초록 체크 / 640×360
5) 데이터 없음 / 점선 업로드 상자를 손으로 가리키는 폴디 / 960×540
6) 완료 / 손을 흔드는 폴디, 초록 체크 두 개, 내려받기 화살표 / 960×540
7) 오류 / 모서리가 구겨지고 별이 도는 어지러운 폴디, 분홍 카드 / 960×540
```

## 8. 파일 형식과 변환 엔진

### 8.1 형식 표 (클라이언트 `lib/shared/file_rules.dart`와 서버·엔진에 같은 표를 둔다. 판정은 이 표로만)

| 결과(메뉴) | 받는 형식 | 방식 |
|---|---|---|
| →MD (2) | pdf, doc, docx, ppt, pptx, xls, xlsx, hwp, hwpx, hwt, txt | docx: mammoth→turndown. xlsx: 시트마다 MD 표. pptx: 슬라이드마다 제목. hwp·구형 Office: LibreOffice로 docx 변환 후 같은 방식. pdf: 텍스트 추출 + AI 구조화, 글자 없으면 OCR. 내용 중심 |
| →PDF (3) | md, doc, docx, ppt, pptx, xls, xlsx, hwp, hwpx, hwt, txt | LibreOffice 직접 변환. md는 markdown-it으로 HTML을 만든 뒤 LibreOffice. 레이아웃 유지 |
| →DOCX (4) | md, pdf, ppt, pptx, xls, xlsx, hwp, hwpx, hwt, txt | hwp·txt: LibreOffice(레이아웃 유지). md: Pandoc. pdf: AI 구조화 + `docx` 라이브러리. pptx·xlsx: 텍스트와 표 이동(내용 중심) |
| →PPTX (5) | md, pdf, doc, docx, xls, xlsx, hwp, hwpx, hwt, txt | 텍스트 추출 → AI 슬라이드 구성 → `pptxgenjs`(최대 30장). xls·xlsx는 시트마다 슬라이드, 표를 슬라이드 표로(슬라이드당 최대 15행, 넘으면 다음 슬라이드). 내용 중심 |
| →XLSX (6) | md, pdf, doc, docx, ppt, pptx, hwp, hwpx, hwt, txt | 문서의 표만 시트로(docx·hwp는 HTML 표, md 표, txt는 탭·쉼표 구분, pdf는 AI 표 추출). 숫자 문자열은 숫자로. 최대 20시트·시트당 5000행. 표가 없으면 `no-table-found`. 표 추출 |
| →HWPX (7) | md, pdf, doc, docx, ppt, pptx, xls, xlsx, txt | 문서 중간 형식(제목, 문단, 목록, 표)을 OWPML 템플릿에 넣어 `jszip`으로 묶는다. **결과는 .hwpx만**(.hwp·.hwt 출력 없음). 내용 중심 |
| →TXT (8) | md, pdf, doc, docx, ppt, pptx, xls, xlsx, hwp, hwpx, hwt | 텍스트 추출(UTF-8, BOM 없음, CRLF). 글자 없는 pdf는 OCR |

- 서버는 확장자와 파일 앞부분(매직 바이트)을 함께 확인한다. hwt는 hwp로 취급. 매크로 파일(docm, xlsm, pptm)은 받지 않는다. 결과와 같은 형식이면 `same-format`.
- 암호가 걸린 파일은 `encrypted-file`, 배포용(보호) 한글 문서는 `protected-hwp`, 글자를 못 찾으면 `no-text-found`.
- 결과 파일명: `{원본 이름}.{결과 확장자}`. 한글 파일명 유지, Content-Disposition에 RFC 5987.

### 8.2 엔진 동작

- `POST /convert {uid, conversionId}`. Cloud Tasks 서비스 계정의 OIDC 토큰만 받는다.
- status가 `queued`인 작업만 처리(재시도로 두 번 변환하지 않음) → `running`, `startedAt` 기록 → Storage에서 원본을 스트림으로 읽어 변환 → `outputs/{uid}/{conversionId}/{결과 파일명}`에 저장 → 결과 크기 > 0 확인 → `done`(outputName, outputPath, outputSize, pageCount, finishedAt). 실패하면 `failed` + errorCode. status는 앞으로만 바꾼다.
- LibreOffice는 작업마다 임시 프로필 폴더를 쓰고 매크로 실행을 끈다. 끝나면 `/tmp`를 지운다. 원본·결과를 컨테이너에 남기지 않는다.
- 1800초를 넘기면 `engine-timeout`.

### 8.3 엔진 글꼴 (무료 라이선스만)

| 글꼴 | 라이선스 | 쓰임 |
|---|---|---|
| Noto Sans CJK KR / JP | SIL OFL 1.1 | 고딕 계열 기본 |
| Noto Serif CJK KR / JP | SIL OFL 1.1 | 명조(바탕) 계열 기본 |
| 나눔고딕, 나눔명조, 나눔바른고딕 | SIL OFL 1.1 | 나눔 글꼴 문서, 보조 대체 |
| Liberation Sans / Serif / Mono | SIL OFL 1.1 | Arial, Times New Roman, Courier New 자리 |
| Carlito, Caladea | SIL OFL 1.1, Apache-2.0 | Calibri, Cambria 자리 |

글꼴 대체표(`engine/config/fontsubst.xcu`):

| 문서 글꼴 | 대체 |
|---|---|
| 함초롬바탕, 바탕, 바탕체, 궁서, 신명조, HY신명조, 한컴바탕 | Noto Serif CJK KR |
| 함초롬돋움, 돋움, 돋움체, 굴림, 굴림체, 맑은 고딕, 한컴돋움, HY견고딕, HY중고딕 | Noto Sans CJK KR |
| MS Mincho, Yu Mincho | Noto Serif CJK JP |
| MS Gothic, Meiryo, Yu Gothic | Noto Sans CJK JP |
| Arial, Helvetica / Times New Roman / Courier New | Liberation Sans / Serif / Mono |
| Calibri / Cambria | Carlito / Caladea |
| 표에 없는 글꼴 | Noto Sans CJK KR |

- 상용이거나 배포 조건이 분명하지 않은 글꼴 파일(함초롬, 맑은 고딕, 바탕, 굴림 등)은 엔진에 넣지 않는다. `engine/fonts/`의 모든 글꼴 옆에 LICENSE 파일을 둔다.
- PDF 결과에는 위 무료 글꼴만 부분 내장한다. DOCX·PPTX·HWPX 결과에는 글꼴 파일을 넣지 않고 이름만 적는다(HWPX `함초롬바탕`·`함초롬돋움`, DOCX·PPTX `맑은 고딕`).
- 대체가 일어나면 펼친 행에 `일부 글꼴을 무료 글꼴로 바꿔 표시했습니다.`

## 9. 서버 명세

### 9.1 Functions (12개, Node.js 22, asia-northeast3, 모두 인증 필수)

| 함수 | 하는 일 |
|---|---|
| `submitPrompt` | AI 홈 입력 처리. AI 횟수·용량 검사 → Gemini 의도 판단 → 형식 표로 첨부 파일 재검사 → 턴 저장(안내 카드, 답, 요약) |
| `requestConversion` | 형식·크기·하루 용량·AI 필요 여부 검사 → conversions 문서 `queued`, expireAt 기록 → usage 증가 → Cloud Tasks 큐에 작업 추가. 만료 기록 정리 |
| `getDownloadUrl` | 소유자 확인 후 10분짜리 서명 주소 발급 |
| `summarizeConversion` | 결과(또는 원본) 텍스트 앞 30000자로 요약 스키마 호출, summaryLines 저장 |
| `getExchangeRates` | `fx_cache/latest`가 60분 이내면 그대로, 아니면 ExchangeRate-API 조회 후 저장. 기준 시각과 함께 반환 |
| `hideTurnParts` | 턴의 userHidden / aiHidden 표시. 둘 다 가려지면 문서 삭제 |
| `deleteByIds` | conversions(원본·결과 파일 포함)와 turns를 400건씩 삭제. running은 제외 |
| `withdraw` | 6.3 탈퇴 범위 삭제 |
| `readBackup` | 주 DB를 못 읽을 때 보조 DB에서 자기 문서 반환(만료 문서 제외) |
| `dbStatus` | 주 DB·보조 DB 자기 문서 건수, 마지막 복제 시각 |
| `syncBackup` | 자기 문서 전체 재복제, 주 DB에 없는 보조 문서 삭제 |
| `mirrorToBackup`(트리거) | `users/{uid}/{collection}/{id}` 쓰기·삭제를 보조 DB에 복제. mirrorEventTime 비교로 늦은 이벤트 우선 |

- 스케줄 함수는 없다. 만료 문서는 목록·요청 함수가 호출될 때 지운다. 파일은 Storage 수명 주기 규칙(7일)이 지운다. Firestore TTL(`conversions.expireAt`, `turns.expireAt`)은 보조 수단이다.
- 서버는 클라이언트가 보낸 메뉴 이름, 형식 판정, 크기를 믿지 않고 다시 확인한다.

### 9.2 AI (Gemini)

- 호출: `GEMINI_MODEL`, JSON + responseSchema, thinkingLevel low. thinking 설정으로 실패하면 thinking 없이 한 번 더. OCR은 `GEMINI_MODEL_VISION`, 페이지 이미지 최대 20쪽. 문서는 앞 30000자만. maxLength는 스키마에 쓰지 않는다.
- 홈 문맥: 지금 시각(Asia/Seoul), 메뉴 목록과 메뉴별 가능 형식, 첨부 파일 이름·확장자·크기, 최근 대화 3턴.
- 홈 스키마(필수 `targetMenu`, `summaryText`, 순서 targetMenu, summaryText, answerText, calcMode, calcInput, fxCurrency):

| targetMenu | 처리 | 실패 문장 |
|---|---|---|
| `to_md`, `to_pdf`, `to_docx`, `to_pptx`, `to_xlsx`, `to_hwpx`, `to_txt` | 형식 표로 재검사 후 안내 카드. 확인하면 `requestConversion`. 첨부가 없으면 `파일을 올리면 바로 변환할 수 있습니다.`와 [메뉴로 이동]만 | 형식·같은 형식 거절 문장 |
| `pdf_merge`, `pdf_edit` | 안내 카드만(처리는 화면). 첨부가 PDF가 아니면 거절 | `PDF 파일만 쓸 수 있습니다.` |
| `calculator` | calcMode(basic, scientific, fx, business), calcInput, fxCurrency(USD, EUR, JPY, CNY, GBP, HKD, SGD, AUD)로 계산기를 연다. 저장 안 함 | `계산 내용을 이해하지 못했습니다. 숫자와 식을 다시 말씀해 주세요.` |
| `summarize` | 첨부 텍스트로 요약 스키마 호출, 턴에 저장 | `요약할 파일을 함께 올려 주세요.` / 글자 없음 문장 |
| `general` | answerText를 턴에 저장 | `답을 만들지 못했습니다. 잠시 후 다시 시도해 주세요.` |

- 변환용 스키마: 슬라이드 `slides[]{title(필수), bullets, notes}` / 표 `tables[]{sheetName, headers(필수), rows(필수)}` / 구조 `blocks[]{type(필수: heading, paragraph, list, table), level, text, items, rows}` / 요약 `lines`(3개), `keywords` / OCR `pages[]{page, text}`.
- 의도 JSON이 두 번 다 깨지면 `요청을 이해하지 못했습니다. 원하는 결과 형식을 함께 말씀해 주세요.` 변환 중 AI 실패는 `failed`(`ai-failed`). 결과 파일이 없거나 0바이트면 절대 done으로 쓰지 않는다.
- 변환은 자동으로 시작하지 않는다. 사용자가 [바로 변환]이나 [변환 시작]을 눌러야 한다. 요약은 [3줄 요약]을 누를 때만.

### 9.3 데이터 (Firestore `convertfile`)

```text
users/{uid}/conversions/{id}
  uid, sourceName, sourceExt, sourceSize, sourcePath,
  targetFormat(md|pdf|docx|pptx|xlsx|hwpx|txt), mode(layout|content|table),
  engine(libreoffice|pandoc|native|gemini), status(queued|running|done|failed), errorCode,
  outputName, outputPath, outputSize, pageCount, summaryLines, fontSubstituted,
  createdAt, startedAt, finishedAt, expireAt(createdAt + 168h)
users/{uid}/turns/{id}
  uid, userText(≤4000자), aiText(≤8000자), isVoice, fileName, filePath, targetMenu, routeCard,
  summaryLines, createdAt, expireAt(게스트만, +168h), userHidden, aiHidden
users/{uid}/usage/{yyyyMMdd}
  uid, bytes, aiCalls, updatedAt
fx_cache/latest      base(KRW), rates, fetchedAt        (서버 전용)
audit/{id}           action, actorUid, targetUid, targetId, changedFields, at   (서버 전용, 파일명·본문 금지)
```

- 오류 코드: `file-too-large`, `unsupported-format`, `same-format`, `encrypted-file`, `protected-hwp`, `no-text-found`, `no-table-found`, `engine-timeout`, `engine-failed`, `ai-failed`, `ai-unavailable`, `quota-exceeded`, `ai-quota-exceeded`.
- Storage: `uploads/{uid}/{timestamp}_{fileName}`, `outputs/{uid}/{conversionId}/{outputName}`.
- 기기에만: locale, fontLevel, lineLevel, `calcHistory.{uid}`(최대 100), `calcPopupPos.{frame}`. 서버로 보내지 않는다.
- 보조 DB: 같은 경로 구조에 mirrorEventTime, mirroredAt 추가. 파일 바이트는 복제하지 않는다.

### 9.4 거절·안내 문장 (한국어 기준, 영어·일본어도 같은 뜻의 짧은 문장)

| 경우 | 문장 |
|---|---|
| 파일 크기 | `파일은 {1GB / 100MB}까지 올릴 수 있습니다.` (게스트 + `로그인하면 1GB까지 쓸 수 있습니다.`) |
| PDF 도구 합계 | `PDF 도구는 한 번에 {1GB / 100MB}까지 쓸 수 있습니다.` |
| 하루 용량 | `오늘 쓸 수 있는 용량({1GB / 100MB})을 모두 썼습니다. 내일 다시 이용해 주세요.` |
| AI 횟수 | `오늘 AI 사용 횟수({200 / 30}회)를 모두 썼습니다. 파일 변환과 PDF 도구는 계속 쓸 수 있습니다.` |
| 형식 | `이 메뉴에서는 {형식 목록} 파일만 올릴 수 있습니다.` |
| 같은 형식 | `이미 {형식} 파일입니다. 다른 결과 형식을 골라 주세요.` |
| 암호 | `암호가 걸린 파일은 변환할 수 없습니다.` |
| 보호 한글 | `배포용(보호) 한글 문서는 변환할 수 없습니다.` |
| 글자 없음 | `파일에서 글자를 찾지 못했습니다.` |
| 표 없음 | `표를 찾지 못했습니다. 표가 있는 문서를 올려 주세요.` |
| 시간 초과 | `변환 시간이 너무 오래 걸려 멈췄습니다. 파일을 나눠서 다시 시도해 주세요.` |
| AI 키 없음 | `AI 키가 아직 없습니다. 파일 변환과 PDF 도구는 사용할 수 있습니다.` |
| 그 외 | `변환하지 못했습니다. 연결 또는 파일을 확인해 주세요.` |
| 변환 완료 | `변환을 마쳤습니다. 7일 동안 내려받을 수 있습니다.` |
| AI 안내 | `'{메뉴}'에서 처리할 수 있습니다. 바로 변환할까요?` |

## 10. 로그인·계정

- 수단: 이메일+비밀번호, 휴대폰+비밀번호, Google(팝업), 게스트(익명). 콘솔에서 익명, Google, 이메일/비밀번호를 켠다(나에게 안내).
- 휴대폰은 문자 인증이 아니다. E.164 번호에서 `+`를 뺀 숫자로 `{digits}@phone.{Firebase 프로젝트 ID}.firebaseapp.com`을 만들어 이메일 로그인한다. 메일을 보내지 않고 화면에 보이지 않는다. 국가번호 기본 한국어·영어 `+82`, 일본어 `+81`, 앞자리 0 제거. placeholder `10-1234-5678`(일본어 `90-1234-5678`). 오류 `휴대폰번호를 확인해 주세요.`
- 이메일 placeholder `example@email.com`, 형식 오류 `이메일 형식이 올바르지 않습니다.`
- 비밀번호 8자 이상(영문과 숫자 포함), 확인 칸, 보기 아이콘, 불일치 `비밀번호가 서로 다릅니다.`, 비밀번호 찾기는 재설정 메일.
- 실패 `이메일 또는 비밀번호가 맞지 않습니다.` / `휴대폰번호 또는 비밀번호가 맞지 않습니다.` / `요청이 많습니다. 잠시 후 다시 시도해 주세요.` / `이 로그인 방법이 아직 활성화되지 않았습니다.`
- 관리자 계정·화면 없음. 유휴 로그아웃 없음.

## 11. 보안 규칙

- Firestore: 클라이언트는 `users/{uid}/**`에서 자기 uid만 **읽기**. 모든 클라이언트 쓰기 거부. `audit`, `fx_cache`, 그 밖의 경로 read·write false. 보조 DB 전체 read·write false.
- Storage: `uploads/{uid}/{file}`은 그 uid만, 허용 contentType만 **쓰기**. 크기는 `request.auth.token.firebase.sign_in_provider == 'anonymous'`이면 100MB 이하, 아니면 1GB 이하. 클라이언트 읽기·삭제 금지. `outputs/**`는 클라이언트 read·write 모두 금지(서명 주소로만 내려받기).
- 서버는 경로가 `uploads/{uid}/`로 시작하는지 확인한다.
- 주 DB와 보조 DB 모두 삭제 보호를 켠다.
- Cloud Run은 `--no-allow-unauthenticated`, 호출 권한은 Cloud Tasks 서비스 계정에만.
- `firebase.json`의 functions ignore에 `*.local`, `.env`, `.env.*`. `functions/.env.example`에는 변수 이름만. `lib/firebase_options.dart`에는 공개 웹 설정만.

## 12. 구현하지 말 것

- 관리자 화면, 통계, 조직, 결제, 공유 링크, 공개 피드, 인트로 영상
- 일괄 변환, 번역 변환, PDF 워터마크·페이지 번호·용량 줄이기·암호, 이미지→PDF, .hwp·.hwt 출력
- 스토어 빌드, 푸시 알림, 다크 모드, 서비스 워커, 검색 화면, 기록 수정 화면, 사용법 화면
- 클라이언트의 Gemini·환율 키, 클라이언트의 엔진 직접 호출, outputs 직접 읽기, 보조 DB 직접 읽기·쓰기
- 키워드로 메뉴 고르기, AI의 형식 판정 신뢰, 시드 데이터, 가짜 환율·가짜 변환 결과
- 이미지 생성, 공개 CORS 프록시, 감사 로그에 파일명·본문 남기기
- Syncfusion 패키지, 무료 라이선스가 아닌 글꼴 파일, Cloud SQL, BigQuery

## 13. 구현 순서 (단계마다 검사 후 보고)

1. **셸:** Flutter 프로젝트, 테마, i18n(3개 언어 같은 키), 세 프레임 레이아웃, 사이드바·레일·하단 탭·그룹 탭, 헤더 버튼, 빈 메뉴 11개, 팝업 계산기, 전체화면 계산기(기본·공학·업무), 읽기 설정. `index.html` 서비스 워커 정리, `vercel.json`, `tool/vercel-build.sh`.
2. **계정:** *(여기서 Firebase 프로젝트 ID와 웹 설정을 나에게 요청)* Firestore `convertfile`·`convertfile-backup` 생성 안내, 보안 규칙, 네 가지 로그인, 계정 연결, 마이페이지(비밀번호 변경, 설정), 탈퇴(`withdraw`).
3. **PDF 도구:** `web/js/pdf_tools.js`(pdf-lib), 합치기, 편집, 인쇄, 용량 검사(1GB/100MB, 300MB 경고).
4. **변환:** `engine/`(Dockerfile, 글꼴과 LICENSE, fontsubst.xcu, 변환기), Cloud Tasks 큐, `requestConversion`, `getDownloadUrl`, 이어 올리기, 변환 기록 목록, 하루 용량 한도. 형식 순서 →PDF, →TXT, →MD, →DOCX, 이어서 →XLSX, →PPTX, →HWPX.
5. **AI:** *(여기서 Gemini API 키 등록을 나에게 요청)* `submitPrompt`, 안내 카드, general, summarize, `summarizeConversion`, AI 변환(pdf 구조화, 슬라이드, 표), OCR, AI 횟수 한도.
6. **마무리:** *(여기서 ExchangeRate-API 키 등록을 요청)* `getExchangeRates`와 환율 탭, `mirrorToBackup`·`readBackup`·`dbStatus`·`syncBackup`, 보조 DB 대체 읽기 띠, 아이콘·브랜드 프롬프트, *(여기서 GitHub 저장소와 Vercel 프로젝트를 요청)* 배포 설정, 전체 테스트.

## 14. 검사와 완료 기준

**검사 명령(단계마다):** `dart format -l 140 lib test`, `flutter analyze`(오류 0), `flutter test`, `node --check functions/index.js`, `cd engine && npm test`.

**테스트 목록:**
- 프레임 판정 3종, 형식 표(허용, 거절, 같은 형식), 용량 경계(파일 하나 1GB/100MB, PDF 도구 합계 1GB/100MB, 300MB 경고)
- PDF 합치기 순서, 칸 5→20, PDF 편집(이동, 삭제, 선택 저장, 되돌리기)
- 계산기(0으로 나누기, 공학 함수, 부가세, 영업일), 팝업 위치 제한과 유지
- 행 펼치기, 선택 토글, 읽기 설정과 큰 글자 넘침, 짧은 화면 스크롤
- 하루 용량(1GB/100MB)과 실패 시 되돌림, AI 횟수(200/30), 168시간 만료 숨김, 의도 파서, 휴대폰 로그인 주소
- 엔진: 형식 쌍별 샘플(`test/fixtures/`), 한글 깨짐 0, 암호 파일 거절, 0바이트 결과는 done 아님, 이어 올리기 재개, 30분 걸리는 큰 파일이 done까지, PDF에 무료 글꼴만 내장, 글꼴 폴더의 모든 파일에 LICENSE
- AI 품질: 메뉴별 문장 3개씩 33개를 각 3회 보내 의도 정답률 95% 이상

**완료 기준:**
- 빈 상태에서 성공과 실패를 모두 재현할 수 있다.
- 서버가 결과 파일을 확인하기 전에는 `완료`가 보이지 않는다.
- 키가 저장소, 화면, 웹 번들에 없다. 프로덕션에 개발 진단이 없다.
- 게스트 흐름과 로그인 흐름이 각각 끝까지 된다.
- 168시간 뒤 기록과 파일이 사라진다. 주 DB와 보조 DB의 건수가 같다.
- 형식 표의 모든 쌍이 샘플 파일로 성공한다.

## 15. 배포와 운영 (마지막 단계에서 나에게 안내)

```text
firebase deploy --only functions,firestore,storage
firebase functions:secrets:set GEMINI_API_KEY
firebase functions:secrets:set EXCHANGE_RATE_API_KEY
gcloud run deploy convert-engine --source engine --region asia-northeast3 --no-allow-unauthenticated \
  --memory 8Gi --cpu 4 --concurrency 1 --timeout 1800
gcloud tasks queues create convert-queue --location asia-northeast3 --max-attempts 2
웹: main 브랜치 푸시 → Vercel 자동 배포
```

운영 체크리스트(내가 콘솔에서 할 일을 정리해 줄 것):
- Firebase 요금제 Blaze, Auth 로그인 수단 3종 켜기, Auth 허용 도메인에 Vercel 주소 추가
- Firestore `convertfile`·`convertfile-backup` 생성과 삭제 보호, TTL 정책(`conversions.expireAt`, `turns.expireAt`)
- Storage 수명 주기 규칙(`uploads/`, `outputs/` 7일)
- Gemini와 Cloud Run 예산 알림
- PITR을 켤지 결정

---

이 프롬프트의 범위를 벗어나는 기능은 추가하지 말고, 막히는 곳이 있으면 현재 상태, 막힌 이유, 다음에 필요한 것을 나에게 보고하라.
