'use strict';
// Gemini REST generateContent with JSON + responseSchema. Shared by functions/ and engine/.

class AiError extends Error {
  constructor(code, detail) {
    super(code);
    this.code = code;
    this.detail = detail;
  }
}

const S = {
  str: (extra = {}) => ({ type: 'STRING', ...extra }),
  int: () => ({ type: 'INTEGER' }),
  arr: (items) => ({ type: 'ARRAY', items }),
  obj: (properties, required = [], order) => ({
    type: 'OBJECT',
    properties,
    required,
    propertyOrdering: order || Object.keys(properties),
  }),
};

const SCHEMAS = {
  home: S.obj(
    {
      targetMenu: S.str({
        enum: ['to_md', 'to_pdf', 'to_docx', 'to_pptx', 'to_xlsx', 'to_hwpx', 'to_txt', 'pdf_merge', 'pdf_edit', 'calculator', 'summarize', 'general'],
      }),
      summaryText: S.str(),
      answerText: S.str(),
      calcMode: S.str({ enum: ['basic', 'scientific', 'fx', 'business'] }),
      calcInput: S.str(),
      fxCurrency: S.str({ enum: ['USD', 'EUR', 'JPY', 'CNY', 'GBP', 'HKD', 'SGD', 'AUD'] }),
    },
    ['targetMenu', 'summaryText'],
  ),
  summary: S.obj({ lines: S.arr(S.str()), keywords: S.arr(S.str()) }, ['lines']),
  slides: S.obj({ slides: S.arr(S.obj({ title: S.str(), bullets: S.arr(S.str()), notes: S.str() }, ['title'])) }, ['slides']),
  tables: S.obj(
    { tables: S.arr(S.obj({ sheetName: S.str(), headers: S.arr(S.str()), rows: S.arr(S.arr(S.str())) }, ['headers', 'rows'])) },
    ['tables'],
  ),
  blocks: S.obj(
    {
      blocks: S.arr(
        S.obj(
          {
            type: S.str({ enum: ['heading', 'paragraph', 'list', 'table'] }),
            level: S.int(),
            text: S.str(),
            items: S.arr(S.str()),
            rows: S.arr(S.arr(S.str())),
          },
          ['type'],
        ),
      ),
    },
    ['blocks'],
  ),
  ocr: S.obj({ pages: S.arr(S.obj({ page: S.int(), text: S.str() }, ['page', 'text'])) }, ['pages']),
};

async function callOnce({ apiKey, model, system, parts, schema, thinking }) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;
  const generationConfig = { responseMimeType: 'application/json', responseSchema: schema };
  if (thinking) generationConfig.thinkingConfig = { thinkingLevel: 'low' };
  const body = { contents: [{ role: 'user', parts }], generationConfig };
  if (system) body.systemInstruction = { parts: [{ text: system }] };
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
    body: JSON.stringify(body),
  });
  const textBody = await res.text();
  if (!res.ok) throw new AiError(res.status === 400 && /thinking/i.test(textBody) ? 'thinking-unsupported' : 'ai-failed', `${res.status}`);
  let json;
  try {
    json = JSON.parse(textBody);
  } catch {
    throw new AiError('ai-failed', 'bad envelope');
  }
  const out = (json.candidates?.[0]?.content?.parts || []).map((p) => p.text || '').join('');
  try {
    return JSON.parse(out);
  } catch {
    throw new AiError('ai-bad-json');
  }
}

/**
 * Calls Gemini and returns parsed JSON. Tries thinking=low first; if the model rejects thinking, retries without it.
 * A broken JSON answer is asked once more. `validate` may throw to force that retry.
 */
async function generateJson({ apiKey, model, system, parts, schema, validate }) {
  if (!apiKey) throw new AiError('ai-unavailable');
  let thinking = true;
  let lastErr;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const v = await callOnce({ apiKey, model, system, parts, schema, thinking });
      if (validate) validate(v);
      return v;
    } catch (e) {
      lastErr = e;
      if (e.code === 'thinking-unsupported' && thinking) {
        thinking = false;
        attempt--;
        continue;
      }
    }
  }
  throw new AiError(lastErr?.code === 'ai-bad-json' ? 'ai-bad-json' : 'ai-failed', lastErr?.detail);
}

const clip = (text, n = 30000) => String(text || '').slice(0, n);

module.exports = { AiError, SCHEMAS, generateJson, clip };
