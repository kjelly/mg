
import "package:threading/threading.dart";
import 'dart:io';
DateTime parseTime(String s) {
  if (s == null) {
    return null;
  }
  DateTime t = null;
  try {
    t = DateTime.parse(s);
  } catch (e) {
    var diff = int.tryParse(s);
    if (diff == null) {
      t = null;
    } else {
      t = DateTime.now().subtract(Duration(hours: diff));
    }
  }
  return t;
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

bool contains(String text, String pattern, {bool regex = false}) {
  if (regex) {
    return RegExp(pattern).hasMatch(text);
  }
  for (var i in pattern.split('|')) {
    if (text.contains(i)) {
      return true;
    }
  }
  return false;
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


