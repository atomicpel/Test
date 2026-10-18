import 'dart:io';

import 'package:cycle_app/prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('данные сохраняются в файл и читаются обратно', () async {
    final dir = await Directory.systemTemp.createTemp('prefs');
    final p = await Prefs.openAt(dir);
    expect(p.getString('a'), isNull);
    await p.setString('a', 'привет');
    await p.setInt('n', 42);
    // много записей подряд не должны ломать файл
    await Future.wait([for (var i = 0; i < 20; i++) p.setInt('i', i)]);
    final q = await Prefs.openAt(dir);
    expect(q.getString('a'), 'привет');
    expect(q.getInt('n'), 42);
    expect(q.getInt('i'), 19);
    await dir.delete(recursive: true);
  });
}
