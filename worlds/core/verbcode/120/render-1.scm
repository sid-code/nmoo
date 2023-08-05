(verbcall #123 "render" args)
;(call (lambda (method path headers args body)
;        (let ((header
;               (cat "<!DOCTYPE HTML><html>"
;                    "<head><meta charset='utf8'><title>eval demo</title></head>"
;                    "<body>"))
;              (footer
;               (cat "</body></html>"))
;              (script
;               (cat "<script>document.getElementById('submit').addEventListener('click',"
;                    "function() { var code = document.getElementById('code').value;"
;                    "             fetch(location.pathname, { method: 'post',"
;                    "                          headers: { 'Content-Type': 'text/plain' },"
;                    "                          body: code })"
;                    "             .then(resp => resp.text().then(t => {"
;                    "               document.getElementById('result').innerText = t;"
;                    "             }));"
;                    "}"
;                    ");"
;                    "</script>")))
;          (list 200 (table ("Content-Type" "text/html"))
;                (cat header
;                     "<p><textarea id='code'></textarea>"
;                     "<p><button id='submit'>eval</button>"
;                     "<p><div id='result'></div>"
;                     script
;                     footer))))
;      args)
