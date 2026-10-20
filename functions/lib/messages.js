'use strict';
// AI home answer sentences stored in turns (ko is the reference; en and ja carry the same meaning).

const M = {
  routeAsk: (menu) => ({
    ko: `'${menu.ko}'에서 처리할 수 있습니다. 바로 변환할까요?`,
    en: `This can be handled in '${menu.en}'. Convert now?`,
    ja: `「${menu.ja}」で処理できます。今すぐ変換しますか?`,
  }),
  routeOpen: (menu) => ({
    ko: `'${menu.ko}'에서 처리할 수 있습니다.`,
    en: `This can be handled in '${menu.en}'.`,
    ja: `「${menu.ja}」で処理できます。`,
  }),
  uploadToConvert: {
    ko: '파일을 올리면 바로 변환할 수 있습니다.',
    en: 'Upload a file to convert it right away.',
    ja: 'ファイルをアップロードするとすぐに変換できます。',
  },
  pdfOnly: { ko: 'PDF 파일만 쓸 수 있습니다.', en: 'Only PDF files can be used.', ja: 'PDFファイルのみ使えます。' },
  calcFail: {
    ko: '계산 내용을 이해하지 못했습니다. 숫자와 식을 다시 말씀해 주세요.',
    en: "I couldn't understand the calculation. Please say the numbers and expression again.",
    ja: '計算内容を理解できませんでした。数字と式をもう一度お話しください。',
  },
  summarizeNeedsFile: { ko: '요약할 파일을 함께 올려 주세요.', en: 'Please attach the file to summarize.', ja: '要約するファイルを一緒にアップロードしてください。' },
  noText: { ko: '파일에서 글자를 찾지 못했습니다.', en: 'No text was found in the file.', ja: 'ファイルから文字が見つかりませんでした。' },
  generalFail: {
    ko: '답을 만들지 못했습니다. 잠시 후 다시 시도해 주세요.',
    en: "I couldn't create an answer. Please try again later.",
    ja: '回答を作成できませんでした。しばらくしてから再度お試しください。',
  },
  aiBusy: {
    ko: '지금 AI 서비스 사용 한도를 넘어 답을 만들지 못했습니다. 잠시 후 다시 시도해 주세요.',
    en: 'The AI service is over its usage limit right now, so no answer was created. Please try again later.',
    ja: '現在AIサービスの利用上限を超えているため、回答を作成できませんでした。しばらくしてから再度お試しください。',
  },
  intentFail: {
    ko: '요청을 이해하지 못했습니다. 원하는 결과 형식을 함께 말씀해 주세요.',
    en: "I couldn't understand the request. Please include the result format you want.",
    ja: 'リクエストを理解できませんでした。希望する変換形式も一緒にお話しください。',
  },
  needsConversion: {
    ko: '이 형식은 먼저 텍스트로 변환한 뒤 요약할 수 있습니다.',
    en: 'Convert this format to text first, then summarize it.',
    ja: 'この形式は先にテキストに変換してから要約できます。',
  },
  tooLargeToSummarize: {
    ko: '파일이 커서 요약할 수 없습니다. 200MB 이하 파일만 요약할 수 있습니다.',
    en: 'The file is too large to summarize. Only files up to 200MB can be summarized.',
    ja: 'ファイルが大きいため要約できません。200MB以下のファイルのみ要約できます。',
  },
  unsupported: (list) => ({
    ko: `이 메뉴에서는 ${list} 파일만 올릴 수 있습니다.`,
    en: `This menu accepts only ${list} files.`,
    ja: `このメニューでは${list}ファイルのみアップロードできます。`,
  }),
  sameFormat: (f) => ({
    ko: `이미 ${f} 파일입니다. 다른 결과 형식을 골라 주세요.`,
    en: `This is already a ${f} file. Choose a different result format.`,
    ja: `すでに${f}ファイルです。別の変換形式を選んでください。`,
  }),
};

const MENU_NAMES = {
  to_md: { ko: 'Markdown으로 변환', en: 'Convert to Markdown', ja: 'Markdownに変換' },
  to_pdf: { ko: 'PDF로 변환', en: 'Convert to PDF', ja: 'PDFに変換' },
  to_docx: { ko: 'Word로 변환', en: 'Convert to Word', ja: 'Wordに変換' },
  to_pptx: { ko: 'PowerPoint로 변환', en: 'Convert to PowerPoint', ja: 'PowerPointに変換' },
  to_xlsx: { ko: 'Excel로 변환', en: 'Convert to Excel', ja: 'Excelに変換' },
  to_hwpx: { ko: '한글로 변환', en: 'Convert to Hangul', ja: 'ハングルに変換' },
  to_txt: { ko: '텍스트로 변환', en: 'Convert to text', ja: 'テキストに変換' },
  pdf_merge: { ko: 'PDF 합치기', en: 'Merge PDFs', ja: 'PDF結合' },
  pdf_edit: { ko: 'PDF 편집', en: 'Edit PDF', ja: 'PDF編集' },
  calculator: { ko: '계산기', en: 'Calculator', ja: '電卓' },
};

const pick = (entry, lang) => entry[lang] || entry.ko;

module.exports = { M, MENU_NAMES, pick };
