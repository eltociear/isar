part of isar;

abstract class _IsarConnect {
  static const _handlers = {
    ConnectAction.getVersion: _getVersion,
    ConnectAction.getSchema: _getSchema,
    ConnectAction.listInstances: _listInstances,
    ConnectAction.watchInstance: _watchInstance,
    ConnectAction.executeQuery: _executeQuery,
    ConnectAction.watchQuery: _watchQuery,
    ConnectAction.removeQuery: _removeQuery,
  };

  static var _initialized = false;
  static StreamSubscription? _querySubscription;
  static final _collectionSubscriptions = <StreamSubscription>[];

  static void initialize() {
    if (_initialized) {
      return;
    }
    _initialized = true;

    Isar.addOpenListener((_) {
      postEvent(ConnectEvent.instancesChanged.event, {});
    });

    Isar.addCloseListener((_) {
      postEvent(ConnectEvent.instancesChanged.event, {});
    });

    for (var handler in _handlers.entries) {
      registerExtension(handler.key.method, (method, parameters) async {
        try {
          final args = parameters.containsKey('args')
              ? jsonDecode(parameters['args']!)
              : <String, dynamic>{};
          final result = {'result': await handler.value(args)};
          return ServiceExtensionResponse.result(jsonEncode(result));
        } catch (e) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError,
            e.toString(),
          );
        }
      });
    }

    _printConnection();
  }

  static void _printConnection() {
    Service.getInfo().then((info) {
      final serviceUri = info.serverUri;
      if (serviceUri == null) {
        print('╔════════════════════════════════════════╗');
        print('║      ERROR STARTING ISAR CONNECT       ║');
        print('╟────────────────────────────────────────╢');
        print('║ No Dart Service seems to be connected  ║');
        print('╚════════════════════════════════════════╝');
        return;
      }
      final port = serviceUri.port;
      final path = serviceUri.path;
      print('╔════════════════════════════════════════╗');
      print('║          ISAR CONNECT STARTED          ║');
      print('╟────────────────────────────────────────╢');
      print('║ Open the Isar Inspector and enter the  ║');
      print('║ following URL to connect:              ║');
      print('╟────────────────────────────────────────╢');
      print('║   $port $path   ║');
      print('╚════════════════════════════════════════╝');
    });
  }

  static Future<dynamic> _getVersion(Map<String, dynamic> _) async {
    return isarCoreVersion;
  }

  static Future<dynamic> _getSchema(Map<String, dynamic> _) async {
    return jsonDecode(Isar.schema!);
  }

  static Future<dynamic> _listInstances(Map<String, dynamic> _) async {
    return Isar.instanceNames.toList();
  }

  static Future<bool> _watchInstance(Map<String, dynamic> params) async {
    for (var sub in _collectionSubscriptions) {
      unawaited(sub.cancel());
    }

    _collectionSubscriptions.clear();
    if (params.isEmpty) return true;

    final instanceName = params['instance']!;
    final instance = Isar.getInstance(instanceName)!;

    for (var collection in instance._collections.values) {
      _sendCollectionInfo(collection);
      final sub = collection.watchLazy().listen((_) {
        _sendCollectionInfo(collection);
      });
      _collectionSubscriptions.add(sub);
    }

    return true;
  }

  static void _sendCollectionInfo(IsarCollection<dynamic> collection) {
    final count = collection.countSync();
    final size = collection.getSizeSync(
      includeIndexes: true,
      includeLinks: true,
    );
    final collectionInfo = ConnectCollectionInfo(
      instance: collection.isar.name,
      collection: collection.name,
      size: size,
      count: count,
    );
    postEvent(
      ConnectEvent.collectionInfoChanged.event,
      collectionInfo.toJson(),
    );
  }

  static Future<List<Map<String, dynamic>>> _executeQuery(
      Map<String, dynamic> params) {
    final query = _getQuery(params);
    return query.exportJson();
  }

  static Future<bool> _watchQuery(Map<String, dynamic> params) async {
    if (_querySubscription != null) {
      unawaited(_querySubscription!.cancel());
    }

    _querySubscription = null;
    if (params.isEmpty) return true;

    final query = _getQuery(params);
    final stream = query.watchLazy();

    _querySubscription = stream.listen((event) {
      postEvent(ConnectEvent.queryChanged.event, {});
    });

    return true;
  }

  static Future<bool> _removeQuery(Map<String, dynamic> params) async {
    final query = _getQuery(params);
    await query.isar.writeTxnSync(query.deleteAll);
    return true;
  }

  static Query _getQuery(Map<String, dynamic> params) {
    final query = ConnectQuery.fromJson(params);
    final collection = Isar.getInstance(query.instance)!
        .getCollectionInternal(query.collection)!;
    return collection.buildQuery(
      filter: query.filter,
      offset: query.offset,
      limit: query.limit,
      sortBy: [if (query.sortProperty != null) query.sortProperty!],
    );
  }
}
