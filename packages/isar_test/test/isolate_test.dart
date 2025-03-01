@TestOn('vm')

import 'dart:isolate';

import 'package:isar/isar.dart';
import 'package:test/test.dart';

import 'util/common.dart';
import 'util/sync_async_helper.dart';

part 'isolate_test.g.dart';

@Collection()
class TestModel {
  Id? id;

  String? value;

  @override
  // ignore: hash_and_equals
  bool operator ==(Object other) {
    return other is TestModel && other.id == id && other.value == value;
  }
}

final TestModel _obj1 = TestModel()
  ..id = 1
  ..value = 'Model 1';
final TestModel _obj2 = TestModel()
  ..id = 2
  ..value = 'Model 2';
final TestModel _obj3 = TestModel()
  ..id = 3
  ..value = 'Model 3';

Future<void> _isolateFunc(SendPort port) async {
  final isar = Isar.openSync(
    [TestModelSchema],
    name: 'test',
  );

  final current = isar.testModels.where().findAllSync();
  assert(current[0] == _obj1 && current[1] == _obj2, 'Did not find objects');

  isar.writeTxnSync(() {
    isar.testModels.deleteSync(2);
    isar.testModels.putSync(_obj3);
  });

  assert(!(await isar.close()), 'Instance was closed incorrectly');

  port.send(true);
}

void main() {
  isarTest('Isolate test', () async {
    final isar = await openTempIsar([TestModelSchema], name: 'test');

    await isar.tWriteTxn(() async {
      await isar.testModels.tPutAll([_obj1, _obj2]);
    });

    final port = ReceivePort();
    await Isolate.spawn(
      _isolateFunc,
      port.sendPort,
      onError: port.sendPort,
    );
    final result = await port.first;
    expect(result, true);

    await qEqual(isar.testModels.where().tFindAll(), [_obj1, _obj3]);

    expect(await isar.close(), true);
  });
}
