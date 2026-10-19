// Browser-only PDF tools on top of pdf-lib (MIT). Files never leave the device.
(function () {
  const { PDFDocument } = window.PDFLib;

  function isEncryptedError(e) {
    return e && (e.name === 'EncryptedPDFError' || /encrypt/i.test(String(e.message || e)));
  }

  async function load(bytes) {
    try {
      return await PDFDocument.load(bytes, { updateMetadata: false });
    } catch (e) {
      if (isEncryptedError(e)) throw new Error('encrypted-file');
      throw new Error('invalid-pdf');
    }
  }

  // Returns { pages, encrypted, error }.
  window.cfPdfInfo = async function (bytes) {
    try {
      const doc = await load(bytes);
      return { pages: doc.getPageCount(), encrypted: false, error: '' };
    } catch (e) {
      return { pages: 0, encrypted: e.message === 'encrypted-file', error: e.message };
    }
  };

  // Merges files in the given order.
  window.cfPdfMerge = async function (list) {
    const out = await PDFDocument.create();
    for (const bytes of list) {
      const src = await load(bytes);
      const pages = await out.copyPages(src, src.getPageIndices());
      pages.forEach((p) => out.addPage(p));
    }
    return await out.save();
  };

  // Builds a new PDF from zero-based page indices of one source (delete, move and extract are all this).
  window.cfPdfPick = async function (bytes, indices) {
    const src = await load(bytes);
    const out = await PDFDocument.create();
    const pages = await out.copyPages(src, Array.from(indices));
    pages.forEach((p) => out.addPage(p));
    return await out.save();
  };
})();
