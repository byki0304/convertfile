'use strict';
// Headless LibreOffice with a fresh profile per job (macros disabled, free-font substitution table).

const fs = require('node:fs');
const path = require('node:path');
const { run } = require('./proc');

const XCU = path.join(__dirname, '..', 'config', 'fontsubst.xcu');

function prepareProfile(workDir) {
  const profile = path.join(workDir, 'lo-profile');
  fs.mkdirSync(path.join(profile, 'user'), { recursive: true });
  fs.copyFileSync(XCU, path.join(profile, 'user', 'registrymodifications.xcu'));
  return profile;
}

/**
 * Converts inPath with a LibreOffice filter (e.g. 'pdf', 'docx:"MS Word 2007 XML"').
 * Returns the output path.
 */
async function convert(inPath, filter, outExt, workDir, { infilter } = {}) {
  const profile = prepareProfile(workDir);
  const outDir = path.join(workDir, `lo-out-${Date.now()}`);
  fs.mkdirSync(outDir, { recursive: true });
  const args = [
    `-env:UserInstallation=file://${profile}`,
    '--headless',
    '--invisible',
    '--nologo',
    '--norestore',
    '--nodefault',
    '--nolockcheck',
  ];
  if (infilter) args.push(`--infilter=${infilter}`);
  args.push('--convert-to', filter, '--outdir', outDir, inPath);
  await run('soffice', args, { env: { HOME: workDir } });
  const out = fs.readdirSync(outDir).find((f) => f.toLowerCase().endsWith(`.${outExt}`));
  if (!out) throw Object.assign(new Error('libreoffice produced no output'), { code: 'engine-failed' });
  return path.join(outDir, out);
}

const FILTERS = {
  pdf: ['pdf', 'pdf'],
  docx: ['docx:MS Word 2007 XML', 'docx'],
  xlsx: ['xlsx:Calc MS Excel 2007 XML', 'xlsx'],
  pptx: ['pptx:Impress MS PowerPoint 2007 XML', 'pptx'],
};

const to = (fmt, inPath, workDir, opts) => convert(inPath, FILTERS[fmt][0], FILTERS[fmt][1], workDir, opts);

module.exports = { convert, to, prepareProfile };
