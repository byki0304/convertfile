// Small browser helpers called from Dart through dart:js_interop.
(function () {
  let dropHandler = null;

  window.cfSetDropHandler = function (fn) {
    dropHandler = fn || null;
  };

  document.addEventListener('dragover', function (e) {
    e.preventDefault();
    if (e.dataTransfer) e.dataTransfer.dropEffect = dropHandler ? 'copy' : 'none';
  });

  document.addEventListener('drop', function (e) {
    e.preventDefault();
    if (dropHandler && e.dataTransfer && e.dataTransfer.files.length) dropHandler(e.dataTransfer.files);
  });

  // Resolves with a FileList, or null when the dialog is cancelled. Files are not read into memory.
  window.cfPickFiles = function (accept, multiple) {
    return new Promise(function (resolve) {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = accept;
      input.multiple = !!multiple;
      input.style.display = 'none';
      document.body.appendChild(input);
      let settled = false;
      const finish = function (v) {
        if (settled) return;
        settled = true;
        input.remove();
        resolve(v);
      };
      input.addEventListener('change', function () {
        finish(input.files && input.files.length ? input.files : null);
      });
      input.addEventListener('cancel', function () {
        finish(null);
      });
      input.click();
    });
  };

  window.cfDownloadBytes = function (bytes, name, mime) {
    const url = URL.createObjectURL(new Blob([bytes], { type: mime }));
    const a = document.createElement('a');
    a.href = url;
    a.download = name;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () {
      URL.revokeObjectURL(url);
    }, 60000);
  };

  window.cfOpenDownload = function (url) {
    const a = document.createElement('a');
    a.href = url;
    a.rel = 'noopener';
    document.body.appendChild(a);
    a.click();
    a.remove();
  };

  let recognizer = null;

  window.cfSpeechSupported = function () {
    return !!(window.SpeechRecognition || window.webkitSpeechRecognition);
  };

  window.cfSpeechStart = function (lang, onText, onEnd) {
    const Ctor = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!Ctor) return false;
    if (recognizer) recognizer.abort();
    recognizer = new Ctor();
    recognizer.lang = lang;
    recognizer.interimResults = true;
    recognizer.continuous = false;
    recognizer.onresult = function (ev) {
      let text = '';
      for (let i = 0; i < ev.results.length; i++) text += ev.results[i][0].transcript;
      onText(text);
    };
    recognizer.onerror = function () {
      onEnd();
    };
    recognizer.onend = function () {
      recognizer = null;
      onEnd();
    };
    recognizer.start();
    return true;
  };

  window.cfSpeechStop = function () {
    if (recognizer) recognizer.stop();
  };
})();
