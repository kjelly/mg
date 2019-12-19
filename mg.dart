import 'dart:io';
import "package:console/console.dart";
import 'dart:convert';
import 'package:args/args.dart';
import "package:args/command_runner.dart";
import 'package:dart_console/dart_console.dart' as dart_console;
import "package:threading/threading.dart";
import 'package:ansicolor/ansicolor.dart';
import 'package:cli_repl/cli_repl.dart';
import 'package:dcache/dcache.dart';

Future<String> getContentFromCommand(List<String> command) async {
  try {
    var result = await Process.run(
        command[0], command.getRange(1, command.length).toList(),
        runInShell: true);
    if (result.exitCode == 0) {
      var ret = result.stdout as String;
      return ret;
    } else {
      return "failed to get content";
    }
  } catch (e) {
    return Future.value("");
  }
}

Future<String> getContentFromFile(String path) async {
  try {
    var f = new File(path);
    if (f.existsSync()) {
      return f.readAsString();
    }
    return Future.value("");
  } catch (e) {
    return Future.value("");
  }
}

bool contains(String text, String pattern) {
  for (var i in pattern.split('|')) {
    if (text.contains(i)) {
      return true;
    }
  }
  return false;
}

Future<String> grepDart(String pattern, String text,
    {DateTime start = null, DateTime end = null, bool invert = false}) async {
  var ret = await runThread(() {
    var ret = text.split('\n').where((s) {
      if (invert) {
        return !contains(s, pattern);
      }
      return contains(s, pattern);
    });
    if (start != null || end != null) {
      ret = ret.where((s) {
        if (end == null) {
          DateTime t;
          try {
            t = DateTime.parse(s.split(' ').getRange(0, 2).join(' '));
          } catch (e) {
            return false;
          }
          if (t.isBefore(start)) {
            return false;
          }
          return true;
        }
        return true;
      });
    }
    return ret.join('\n');
  }) as String;
  return Future.value(ret);
}

//reload, grep, cmd, file,
void main(List<String> args) async {
  var parser = new ArgParser();
  parser.addMultiOption('file', abbr: "f");
  parser.addMultiOption('command', abbr: "c");
  var results = parser.parse(args);

  List<List<String>> commandList = [];
  List<String> fileList = [];

  for (var i in results['command']) {
    commandList.add(i.toString().split(' '));
  }
  for (var i in results['file']) {
    fileList.add(i);
  }

  Map<String, List<String>> content = {};
  Cache cache =
      new SimpleCache<String, String>(storage: new SimpleStorage(size: 10));
  var register = Map<String, String>();

  await handleReload(content, commandList, fileList);

  final console = dart_console.Console();
  var repl = new Repl(prompt: '>>> ', continuation: '... ');

  var runner = CommandRunner("dynamic_grep", "dynamic grep")
    ..addCommand(GrepCommand(content, print, cache, register))
    ..addCommand(ListCommand(content, print))
    ..addCommand(AddCmdCommand(commandList))
    ..addCommand(AddFileCommand(fileList))
    ..addCommand(ReloadCommand(content, commandList, fileList, cache));

  for (var line in repl.run()) {
    if (line == null) {
      exit(0);
    }

    var command = parseLine(line);
    if (command.length == 0) {
      continue;
    }

    console.writeLine('**************', dart_console.TextAlignment.center);
    console.writeLine('*   Output   *', dart_console.TextAlignment.center);
    console.writeLine('**************', dart_console.TextAlignment.center);

    var t1 = DateTime.now();
    try {
      await runner.run(command);
    } catch (e) {
      print('ERROR: $e');
    }

    print("time: ${DateTime.now().difference(t1)}");
  }
}

List<String> parseLine(String line) {
  var stack = List<String>();
  var output = List<String>();
  var temp = '';
  for (var i in line.trim().split('')) {
    if (i == ' ') {
      if (stack.isEmpty) {
        output.add(temp);
        temp = '';
      } else {
        temp += i;
      }
    } else if (i == "'") {
      if (stack.isEmpty) {
        stack.add("'");
      } else {
        output.add(temp);
        temp = '';
        stack.removeLast();
      }
    } else {
      temp += i;
    }
  }
  if (temp.isNotEmpty) {
    output.add(temp);
  }
  output = output.where((s) => s.isNotEmpty).toList();
  return output;
}

void handleGrep(
    ArgResults argResult,
    Map<String, List<String>> content,
    dynamic Function(String) show,
    Cache<String, String> cache,
    Map<String, String> register) async {
  var cacheKeyList = new List<String>.from(argResult.arguments);
  cacheKeyList.sort();
  var cacheKey = cacheKeyList.join(' ');

  if (cache.containsKey(cacheKey)) {
    show(cache.get(cacheKey));
    return;
  }

  var pattern = argResult.rest;
  var invertPattern = argResult['invert'];
  var keys = argResult['key'];
  var registerKey = argResult['to'];

  DateTime startTime;
  if (argResult['start'] != null) {
    try {
      startTime = DateTime.parse(argResult['start']);
    } catch (e) {
      var diff = int.tryParse(argResult['start']);
      if (diff == null) {
        startTime = null;
      } else {
        startTime = DateTime.now().subtract(Duration(hours: diff));
      }
    }
  }
  var jobs = 0;
  var worker = int.tryParse(argResult['worker']) ?? 1000;
  var greenPen = AnsiPen()..green();
  var line = greenPen('*-----------------*');

  if (pattern.length == 0) {
    show("Please provide pattern.");
    return;
  }

  if (content.keys.length == 0) {
    print("No data");
  } else {}

  if (argResult['from'] != "") {
    var c = '';
    if (register.containsKey(argResult['from'])) {
      c = register[argResult['from']];
    }

    var futureString = Future.value(c);
    for (var p in pattern) {
      futureString = futureString.then((c) {
        return grepDart(p, c, start: startTime);
      });
    }
    for (var p in invertPattern) {
      futureString = futureString.then((c) {
        return grepDart(p, c, start: startTime, invert: true);
      });
    }
    for (var p in pattern) {
      futureString = futureString.then((c) {
        return applyColor(c, p, AnsiPen()..red());
      });
    }
    show(await futureString);
    return;
  }

  for (var i in content.keys) {
    if (!containKeys(i, keys)) {
      continue;
    }
    for (var c in content[i]) {
      while (jobs > worker) {
        await Future.delayed(Duration(milliseconds: 1));
      }

      jobs += 1;
      var futureString = Future.value(c);
      for (var p in pattern) {
        futureString = futureString.then((c) {
          return grepDart(p, c, start: startTime);
        });
      }
      for (var p in invertPattern) {
        futureString = futureString.then((c) {
          return grepDart(p, c, start: startTime, invert: true);
        });
      }
      for (var p in pattern) {
        futureString = futureString.then((c) {
          return applyColor(c, p, AnsiPen()..red());
        });
      }
      futureString.then((c) {
        if (c.isNotEmpty) {
          var output = '''
$line
path: $i
content:
$c
$line
              ''';
          show(output);
          cache.set(cacheKey, output);
          if (registerKey != "") {
            register[registerKey] = output;
          }
        }
        jobs -= 1;
      });
    }
  }
  while (jobs > 0) {
    await Future.delayed(Duration(milliseconds: 1));
  }
}

List<String> split(String s, int offset) {
  List<String> ret = [];
  var parts = s.split('\n');

  for (var i = 0; i < parts.length; i += offset) {
    if ((i + offset) > parts.length) {
      ret.add(parts.getRange(i, parts.length).join('\n'));
      break;
    }
    ret.add(parts.getRange(i, i + offset).join('\n'));
  }
  return ret;
}

void handleReload(Map<String, List<String>> content,
    List<List<String>> commandList, List<String> fileList,
    {int length = 2000}) async {
  var jobs = 0;
  var offset = length;

  for (var i in commandList) {
    jobs += 1;
    getContentFromCommand(i).then((s) {
      jobs -= 1;
      if (s == 'failed to get content') {
        print('Failed to load. cmd: $i');
      } else {
        content[i.join(' ')] = split(s, offset);
      }
    });
  }
  for (var i in fileList) {
    jobs += 1;
    getContentFromFile(i).then((s) {
      jobs -= 1;
      if (s.length > 0) {
        content[i] = split(s, offset);
      } else {
        print('Failed to load. file: $i');
      }
    });
  }

  var progress = ProgressBar();
  while (jobs > 0) {
    progress.update(
        100 - ((jobs / (commandList.length + fileList.length)) * 100).round());
    await Future.delayed(Duration(milliseconds: 1));
  }
  progress.update(100);
}

Future<String> applyColor(String text, String pattern, AnsiPen pen) async {
  return await runThread(() {
    var lst = text.split(pattern);
    return lst.join(pen(pattern));
  }) as String;
}

Future<dynamic> runThread(dynamic Function() func) async {
  dynamic ret;
  var lock = Lock();
  var thread = new Thread(() async {
    await lock.acquire();
    ret = func();
    await lock.release();
  });
  await thread.start();
  await Future.delayed(Duration(milliseconds: 1));
  await thread.join();
  await lock.acquire();
  await lock.release();
  return Future.value(ret);
}

bool containKeys(String s, List<String> keys) {
  if (keys == null) {
    return true;
  }
  for (var i in keys) {
    if (!s.contains(i)) {
      return false;
    }
  }
  return true;
}

String grepActorFunction(String args_string) {
  var args = jsonDecode(args_string);
  var text = args['text'] as String;
  var invert = args['invert'] as bool;
  var pattern = args['pattern'] as String;
  var start = args['startTime'] as DateTime;
  var end = null;

  return text.split('\n').where((s) {
    if (invert) {
      return !s.contains(pattern);
    }
    return s.contains(pattern);
  }).where((s) {
    if (start == null && end == null) {
      return true;
    } else if (end == null) {
      DateTime t;
      try {
        t = DateTime.parse(s.split(' ').getRange(0, 2).join(' '));
      } catch (e) {
        return false;
      }
      if (t.isBefore(start)) {
        return false;
      }
      return true;
    }
    return true;
  }).join('\n');
}

class GrepCommand extends Command {
  final name = "grep";
  final description = "grep pattern from source. Use `|` for `or`;";
  Map<String, List<String>> content;
  dynamic Function(String) show;
  Cache cache;
  Map<String,String> register;

  GrepCommand(this.content, this.show, this.cache, this.register) {
    argParser.addOption('start',
        abbr: 's', help: "'2019-01-02 13:13:13' or 4 for four hours ago");
    argParser.addMultiOption('key', abbr: 'k');
    argParser.addMultiOption('invert', abbr: 'v');
    argParser.addOption('worker', abbr: 'w', defaultsTo: "100");
    argParser.addOption('from', abbr: 'f', defaultsTo: "");
    argParser.addOption('to', abbr: 't', defaultsTo: "a");
  }

  void run() async {
    await handleGrep(argResults, content, print, cache, register);
  }
}

class ReloadCommand extends Command {
  final name = "reload";
  final description = "reload all source";
  Map<String, List<String>> content;
  List<List<String>> commandList;
  List<String> fileList;
  Cache cache;

  ReloadCommand(this.content, this.commandList, this.fileList, this.cache) {
    argParser.addOption('size', abbr: 's', defaultsTo: "1000");
  }

  void run() async {
    cache.clear();
    var size = int.tryParse(argResults['size']) ?? 1000;
    await handleReload(content, commandList, fileList, length: size);
  }
}

class ListCommand extends Command {
  final name = "list";
  final description = "list all source";
  Map<String, List<String>> content;
  dynamic Function(String) show;

  ListCommand(this.content, this.show) {}

  void run() async {
    for (var i in content.keys) {
      show(i);
    }
  }
}

class AddCmdCommand extends Command {
  final name = "cmd";
  final description = "add command to source.";
  List<List<String>> commandList;

  AddCmdCommand(this.commandList) {}

  void run() async {
    commandList.add(argResults.rest);
  }
}

class AddFileCommand extends Command {
  final name = "file";
  final description = "add command to source.";
  List<String> fileList;

  AddFileCommand(this.fileList) {}

  void run() async {
    fileList.add(argResults.rest.join());
  }
}
