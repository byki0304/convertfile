# ConvertFile

AI 문서 변환 작업대. Flutter 웹 PWA(Vercel) + Firebase(Auth, Firestore, Storage, Cloud Functions) + Cloud Run 변환 엔진.

| 폴더 | 내용 |
|---|---|
| `lib/` | Flutter 웹 앱 (Riverpod, 세 프레임 레이아웃, 한국어·English·日本語) |
| `web/` | `index.html`, PWA 매니페스트, 아이콘, pdf-lib 래퍼(`web/js`) |
| `functions/` | Cloud Functions (Node 22, `asia-northeast3`) |
| `engine/` | Cloud Run 변환 엔진 (LibreOffice + H2Orestart + Pandoc + 무료 글꼴) |
| `tool/` | `vercel-build.sh`, `make_icons.py` |

## 로컬 확인

```bash
flutter pub get
flutter test
flutter run -d chrome

cd functions && npm install && npm run check && npm test
cd engine && npm install && npm test
```

`engine/lib/`의 `file_rules.js`, `gemini.js`, `text_extract.js`는 `functions/lib/`의 복사본입니다. 원본을 고치면 함께 복사하세요(엔진 테스트가 두 파일이 같은지 확인합니다).

## 배포 (한 번만 하는 설정)

키 값은 코드, 문서, `.env`, 커밋에 쓰지 않습니다. Secret Manager에만 넣습니다.

```bash
firebase functions:secrets:set GEMINI_API_KEY
firebase functions:secrets:set EXCHANGE_RATE_API_KEY
```

1. Firebase 요금제 Blaze. Auth 로그인 수단(익명, Google, 이메일/비밀번호)을 켜고, 허용 도메인에 Vercel 주소를 추가합니다.
2. Firestore 데이터베이스 `convertfile`, `convertfile-backup`을 `asia-northeast3`에 만들고 삭제 보호를 켭니다.
3. Storage 수명 주기와 CORS:
   ```bash
   gcloud storage buckets update gs://convertfile-9b293.firebasestorage.app --lifecycle-file=storage.lifecycle.json --cors-file=storage.cors.json
   ```
   Vercel 주소가 정해지면 `storage.cors.json`의 origin에 추가합니다.
4. 서명 주소 발급을 위해 Functions 실행 서비스 계정에 `Service Account Token Creator` 역할을 줍니다.
5. Cloud Tasks 큐:
   ```bash
   gcloud tasks queues create convert-queue --location=asia-northeast3 --max-attempts=1
   ```
6. 엔진 배포 (인증 필요, 시크릿은 Secret Manager에서 주입):
   ```bash
   cd engine
   gcloud run deploy convert-engine --source . --region asia-northeast3 --no-allow-unauthenticated \
     --memory 4Gi --cpu 2 --timeout 1800 --concurrency 1 --max-instances 10 \
     --set-secrets GEMINI_API_KEY=GEMINI_API_KEY:latest \
     --set-env-vars STORAGE_BUCKET=convertfile-9b293.firebasestorage.app
   gcloud run services add-iam-policy-binding convert-engine --region asia-northeast3 \
     --member serviceAccount:557200943471-compute@developer.gserviceaccount.com --role roles/run.invoker
   ```
   엔진 서비스 계정에는 Firestore, Storage 권한과 `GEMINI_API_KEY` 시크릿 접근 권한이 필요합니다.
7. `functions/.env`(커밋하지 않음, 비밀 값 아님)에 `ENGINE_URL=https://convert-engine-557200943471.asia-northeast3.run.app`, `TASKS_INVOKER_SA=557200943471-compute@developer.gserviceaccount.com`을 적습니다. 엔진 배포 후 출력된 주소가 다르면 그 주소로 바꿉니다. Functions가 이 계정 이름으로 작업을 만들 수 있도록 같은 계정에 `Service Account User` 역할도 줍니다.
8. 배포:
   ```bash
   firebase deploy --only functions,firestore,storage
   ```
9. Vercel: GitHub 저장소를 연결하면 `main` 푸시마다 `vercel.json` 설정(빌드 `bash tool/vercel-build.sh`, 출력 `build/web`)으로 배포됩니다.

## 글꼴

엔진과 화면 모두 무료 라이선스(SIL OFL 1.1, Apache-2.0) 글꼴만 씁니다. 자세한 목록은 `engine/fonts/LICENSE.md`.
