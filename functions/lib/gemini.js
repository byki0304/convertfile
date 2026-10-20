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

function errorReason(textBody) {
  try {
    return String(JSON.parse(textBody).error?.message || '').slice(0, 300);
  } catch {
    return String(textBody).slice(0, 300);
  }
}

/** POSTs generateContent with a time limit and logs model, status and duration (never the key or prompt). */
async function post({ apiKey, model, body, timeoutMs }) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;
  const t0 = Date.now();
  let res;
  let textBody;
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
    textBody = await res.text();
  } catch (e) {
    const timeout = e.name === 'TimeoutError' || e.name === 'AbortError';
    console.warn(JSON.stringify({ gemini: model, status: timeout ? 'timeout' : 'network', ms: Date.now() - t0 }));
    throw new AiError(timeout ? 'ai-timeout' : 'ai-failed', timeout ? `timeout ${timeoutMs}ms` : e.message);
  }
  const log = { gemini: model, status: res.status, ms: Date.now() - t0 };
  if (res.ok) console.log(JSON.stringify(log));
  else console.warn(JSON.stringify({ ...log, reason: errorReason(textBody) }));
  return { res, textBody };
}

async function callOnce({ apiKey, model, system, parts, schema, thinking, timeoutMs = 120000 }) {
  const generationConfig = { responseMimeType: 'application/json', responseSchema: schema };
  if (thinking) generationConfig.thinkingConfig = { thinkingLevel: 'low' };
  const body = { contents: [{ role: 'user', parts }], generationConfig };
  if (system) body.systemInstruction = { parts: [{ text: system }] };
  const { res, textBody } = await post({ apiKey, model, body, timeoutMs });
  if (!res.ok) {
    if (res.status === 400 && /thinking/i.test(textBody)) throw new AiError('thinking-unsupported');
    throw new AiError(res.status === 429 ? 'ai-rate-limited' : 'ai-failed', `${res.status} ${errorReason(textBody)}`);
  }
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
async function generateJson({ apiKey, model, system, parts, schema, validate, timeoutMs }) {
  if (!apiKey) throw new AiError('ai-unavailable');
  let thinking = true;
  let lastErr;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const v = await callOnce({ apiKey, model, system, parts, schema, thinking, timeoutMs });
      if (validate) validate(v);
      return v;
    } catch (e) {
      lastErr = e;
      if (e.code === 'thinking-unsupported' && thinking) {
        thinking = false;
        attempt--;
        continue;
      }
      if (e.code === 'ai-rate-limited' || e.code === 'ai-timeout') break;
    }
  }
  throw new AiError(lastErr?.code === 'ai-bad-json' ? 'ai-bad-json' : 'ai-failed', lastErr?.detail);
}

/**
 * Free-text answer. With `search` (default) Gemini may use Google Search grounding for current information
 * (news, weather, prices). Returns { text, sources: [{ title, uri }], queries: [string] }.
 */
async function generateGrounded({ apiKey, model, system, prompt, search = true, timeoutMs = 45000 }) {
  if (!apiKey) throw new AiError('ai-unavailable');
  let thinking = true;
  for (let attempt = 0; attempt < 2; attempt++) {
    const body = { contents: [{ role: 'user', parts: [{ text: prompt }] }] };
    if (search) body.tools = [{ google_search: {} }];
    if (thinking) body.generationConfig = { thinkingConfig: { thinkingLevel: 'low' } };
    if (system) body.systemInstruction = { parts: [{ text: system }] };
    const { res, textBody } = await post({ apiKey, model, body, timeoutMs });
    if (!res.ok) {
      if (thinking && res.status === 400 && /thinking/i.test(textBody)) {
        thinking = false;
        attempt--;
        continue;
      }
      if (attempt === 0 && res.status >= 500) continue;
      throw new AiError(res.status === 429 ? 'ai-rate-limited' : 'ai-failed', `${res.status} ${errorReason(textBody)}`);
    }
    let json;
    try {
      json = JSON.parse(textBody);
    } catch {
      throw new AiError('ai-failed', 'bad envelope');
    }
    const cand = json.candidates?.[0];
    const text = (cand?.content?.parts || [])
      .filter((p) => !p.thought)
      .map((p) => p.text || '')
      .join('')
      .trim();
    if (!text) {
      if (attempt === 0) continue;
      throw new AiError('ai-failed', 'empty');
    }
    const meta = cand.groundingMetadata || {};
    const seen = new Set();
    const sources = [];
    for (const c of meta.groundingChunks || []) {
      const uri = c.web?.uri;
      if (!uri || seen.has(uri)) continue;
      seen.add(uri);
      sources.push({ title: String(c.web.title || uri).slice(0, 200), uri });
      if (sources.length >= 5) break;
    }
    const queries = (meta.webSearchQueries || []).map((q) => String(q).slice(0, 200)).slice(0, 3);
    return { text, sources, queries };
  }
  throw new AiError('ai-failed');
}

const clip = (text, n = 30000) => String(text || '').slice(0, n);

module.exports = { AiError, SCHEMAS, generateJson, generateGrounded, clip };
