
var editor = CodeMirror(document.body, {
  keyMap: "vim",
  mode: "scheme",
  matchBrackets: true,
  value: <<<CODE>>>
});

CodeMirror.commands.save = function(cm) {
  var http = new XMLHttpRequest();
  var url = location.href;
  var data = cm.getValue()
  http.open("POST", url, true);

  http.setRequestHeader("Content-type", "text/plain");
  http.setRequestHeader("Content-length", data.length);
  http.setRequestHeader("Connection", "close");

  http.onreadystatechange = function() {
    console.log(http)
  }
  http.send(data);
}
