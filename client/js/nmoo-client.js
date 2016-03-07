
$(function() {

  var term = $("#terminal").terminal(function(command, term) {
    var split = command.trim().split(/ /g);
    var cmd = split.shift(), args = split;
    if (cmd === "connect") {
      var host = args[0], port = args[1], name = args[2], pass = args[3];
      
      if (!term.socket) {
        if (!host || !port) {
          return term.echo("Usage: " + cmd + " <host> <port> [<name> <pass>]");
        }
        
        term.socket = connect(host, port, name, pass, term);
      } else {
        term.echo("Ignoring arguments, using existing connection.");
        term.echo("Press Ctrl-D and type disconnect to end the connection.");
        term.socket.onopen();
      }
    }
    
    if (cmd === "disconnect") {
      if (!term.socket) {
        term.echo("Not connected.");
      } else {
        term.socket.close();
        delete term.socket;
      }
    }
  }, {
    greetings: "nmoo WebSocket client",
    name: "nmoo",
    height: 500,
    prompt: "prompt> "
  });
  term.echo("Type 'connect <host> <port>' to connect");

  $(".CodeMirror").focus(function() { term.focus(false); });
});

function connect(host, port, name, pass, term) {
  var url = "ws://" + host + ":" + port;
  var socket = new WebSocket(url, ["base64"]);

  var capturing = false;
  var capture = "";
  var editing = "";

  function ssend(msg) {
    console.log("Intercepted " + msg)
    socket.send(btoa(msg + "\n"));
  }

  term.echo("Attempting to connect to " + url + "...");
  socket.onmessage = function(msg) {
    var realMsg = atob(msg.data).slice(0, -1);
    var lines = realMsg.split("\n");
    lines.forEach(function(line) {
      realOnmessage(line);
    });
  };
  function realOnmessage(line) {
    if (capturing) {
      if (line.trim() == "{/verbcode}") {
        capturing = false;
        console.log(capture)

        var editor = CodeMirror(document.body, {
          keyMap: "vim",
          mode: "scheme",
          matchBrackets: true,
          value: capture,
          theme: "base16-dark"
        });
        
        CodeMirror.commands.save = function(cm) {
          var data = cm.getValue();
          $(editor.getWrapperElement()).remove();
          var lines = data.trim().split("\n");
          ssend("@program " + editing);
          editing = "";

          lines.forEach(function(line) {
            ssend(line);
          });

          ssend(".");
        }

        $(".cm-container").append($(".CodeMirror"));

      } else {
        capture += line + "\n"
      }
    } else {
      if (line.trim() == "{verbcode}") {
        capturing = true
        capture = ""
      } else {
        term.echo(line); 
      }
    }
  };

  _ssend = ssend;

  socket.onopen = function() {
    if (name && pass) {
      term.echo("Sending login credentials for " + name);
      ssend("connect " + name + " " + pass);
    }

    term.push(function(command, term) {
      var split = command.trim().split(/ /g);
      var cmdName = split.shift(), args = split;
      if (cmdName == "vedit") {
        ssend("@list " + args[0] + " tags")
        editing = args[0]
      } else {
        ssend(command)
      }
    }, {
      name: "nmoo",
      prompt: "> "
    });

    socket.onclose = function() {
      delete term.socket;
      term.echo("Connection lost.");
      term.pop();
    };
    
  };

  socket.onerror = function(err) {
    delete term.socket;
    console.log(err);
    term.error("WebSocket error - Check host/port");
  };

  return socket;
}
