// bytes must not be nullable

import 'package:isar/isar.dart';

@Collection()
class Model {
  Id? id;

  late List<byte?> prop;
}
