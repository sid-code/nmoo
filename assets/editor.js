/* jshint esversion:6, loopfunc:true*/
(function() {
  const escapeHTML = (str) => {
    var div = document.createElement('div');
    div.appendChild(document.createTextNode(str));
    return div.innerHTML;
  };

  const getMObject = (token, objid, callback, errback) => {
    const xhr = new XMLHttpRequest();
    xhr.onreadystatechange = () => {
      if (xhr.readyState == 4) {
        if (xhr.status == 200) {
          callback(JSON.parse(xhr.responseText));
        } else {
          errback(xhr.status, xhr.responseText);
        }
      }
    };

    token = encodeURIComponent(token);
    objid = encodeURIComponent(objid);
    xhr.open("GET", `/objdata?token=${token}&objid=${objid}`);
    xhr.send();
  };

  const sendVerbCode = (token, objid, verbid, code, callback, errback) => {
    const xhr = new XMLHttpRequest();
    xhr.onreadystatechange = () => {
      if (xhr.readyState == 4) {
        if (xhr.status == 200) {
          callback(xhr.responseText);
        } else {
          errback(xhr.status, xhr.responseText);
        }
      }
    };

    token = encodeURIComponent(token);
    objid = encodeURIComponent(objid);
    verbid = encodeURIComponent(verbid);
    xhr.open("POST", `/codeupdate?token=${token}&objid=${objid}&verbid=${verbid}`);
    xhr.send(code);
  };

  const errField = document.getElementById("errors");
  const setError = (msg) => {
    errField.innerHTML = msg;
  }

  const redraw = (hash) => {
    const hashData = hash.slice(1);

    const parts = hashData.split("/");
    if (parts.length < 2) {
      document.write("oops");
    } else if (parts.length <= 3) {
      const [token, objid, verbid] = parts;
      drawObjectPage(token, objid, verbid);
    }
  };

  const status = {
    token: null,
    objid: null,
    verbid: null,

    modified: false,
  };

  //CodeMirror.keyMap.vim.fallthrough = ["basic", "subpar"];

  const drawObjectPage = (token, objid, verbid) => {
    status.token = token;
    status.objid = objid;

    getMObject(token, objid, (objdata) => {

      const header = document.getElementById("header");
      const uiContainer = document.getElementById("ui-container");
      const verbsContainer = document.getElementById("verbs-container");
      verbsContainer.innerHTML = "";


      header.innerText = `${objdata.name} (#${objid})`;

      for (const verb in objdata.verbs) {
        const verbEl = document.createElement("div");
        const verbdata = objdata.verbs[verb];

        verbEl.classList.add("verb");
        verbEl.innerText = `${verb}: ${verbdata.names}`;

        verbEl.addEventListener("click", ((id) => () => {
          if (status.modified) {
            const confirmed = confirm("You have unsaved changes. Are you sure you want to navigate away?");
            if (!confirmed) return;
          }

          location.hash = `${token}/${objid}/${id}`;
          verbCodeEditor.setValue(objdata.verbs[id].code.trimLeft());
          verbCodeEditor.focus();

          status.verbid = id;
          status.modified = false;
        })(verb));

        if (verb && verbid == verb && objdata.verbs.hasOwnProperty(verb)) {
          verbEl.click();
        }

        verbsContainer.appendChild(verbEl);
      }


      const errField = document.getElementById("errors");
      setError("");
    }, (errcode, msg) => {
      setError(`Error: ${escapeHTML(errcode)}<br>${escapeHTML(msg)}`);
    });
  };

  const save = () => {
    console.log(`saving ${status.objid} ${status.verbid}`);
    const code = verbCodeEditor.getValue();

    sendVerbCode(status.token, status.objid, status.verbid, code, (resp) => {
      status.modified = false;
      setError("");
    }, (errcode, msg) => {
      setError(msg);
    });
  };

  var verbCodeEditorEl, verbCodeEditor;

  window.addEventListener("DOMContentLoaded", () => {
    verbCodeEditorEl = document.getElementById("editor");

    verbCodeEditor = CodeMirror.fromTextArea(verbCodeEditorEl, {
      mode: "scheme",
      keyMap: "vim",
      matchBrackets: true,
    });

    CodeMirror.commands.save = save;
    CodeMirror.on(verbCodeEditor, "keypress", (e) => {
      if (e.ctrlKey && e.keyCode === 83) {
        save();
      }
    });

    CodeMirror.on(verbCodeEditor, "change", () => {
      status.modified = true;
    });

    verbCodeEditor.refresh();

    redraw(location.hash);
  });

  window.addEventListener("hashchange", () => {
    redraw(location.hash);
  });

})();
