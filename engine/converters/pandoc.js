'use strict';

const { run } = require('./proc');

/** Markdown (GFM) → DOCX. */
async function mdToDocx(inPath, outPath) {
  await run('pandoc', ['-f', 'gfm', '-t', 'docx', '-o', outPath, inPath]);
  return outPath;
}

module.exports = { mdToDocx };
