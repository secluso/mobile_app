//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:secluso_flutter/objectbox.g.dart' as objectbox;
import 'package:secluso_flutter/utilities/app_paths.dart';
import 'package:sqflite/sqflite.dart';

import 'entities.dart';

const bool _fdroidBuild = bool.fromEnvironment('SECLUSO_FDROID_BUILD');

abstract class _AppStoresBackend {
  Future<List<Camera>> getAllCameras();
  Future<List<Camera>> findCamerasByName(String name);
  Future<Camera?> findFirstCameraByName(String name);
  Future<int> putCamera(Camera camera);
  Future<List<int>> putManyCameras(List<Camera> cameras);
  Future<bool> removeCamera(int id);

  Future<List<Video>> getAllVideos();
  Future<List<Video>> listVideosForCamera(
    String cameraName, {
    int? limit,
    int offset = 0,
  });
  Future<List<Video>> listRecentVideos({int? limit, int offset = 0});
  Future<Video?> findFirstVideoForNotification(
    String cameraName,
    String timestampToken,
  );
  Future<bool> hasVideo(String cameraName, String videoName);
  Future<int> countVideosForCamera(String cameraName);
  Future<int> putVideo(Video video);
  Future<List<int>> putManyVideos(List<Video> videos);
  Future<void> removeVideos(List<int> ids);

  Future<List<Detection>> getAllDetections();
  Future<List<Detection>> findDetectionsByVideoFile(String videoFile);
  Future<List<Detection>> findDetectionsByCameraAndVideoFile(
    String cameraName,
    String videoFile,
  );
  Future<List<int>> putManyDetections(List<Detection> detections);
  Future<void> removeDetections(List<int> ids);

  Future<List<Meta>> getAllMetas();
  Future<int> putMeta(Meta meta);

  Future<void> close();
}

class AppCameraStore {
  AppCameraStore._(this._backend);

  final _AppStoresBackend _backend;

  Future<List<Camera>> getAllAsync() => _backend.getAllCameras();

  Future<List<Camera>> findByName(String name) =>
      _backend.findCamerasByName(name);

  Future<Camera?> findFirstByName(String name) =>
      _backend.findFirstCameraByName(name);

  Future<int> put(Camera camera) => _backend.putCamera(camera);

  Future<List<int>> putManyAsync(List<Camera> cameras) =>
      _backend.putManyCameras(cameras);

  Future<bool> remove(int id) => _backend.removeCamera(id);
}

class AppVideoStore {
  AppVideoStore._(this._backend);

  final _AppStoresBackend _backend;

  Future<List<Video>> getAllAsync() => _backend.getAllVideos();

  Future<List<Video>> listByCamera(
    String cameraName, {
    int? limit,
    int offset = 0,
  }) => _backend.listVideosForCamera(cameraName, limit: limit, offset: offset);

  Future<List<Video>> listRecent({int? limit, int offset = 0}) =>
      _backend.listRecentVideos(limit: limit, offset: offset);

  Future<Video?> findFirstForNotification(
    String cameraName,
    String timestampToken,
  ) => _backend.findFirstVideoForNotification(cameraName, timestampToken);

  Future<bool> hasVideo(String cameraName, String videoName) =>
      _backend.hasVideo(cameraName, videoName);

  Future<int> countForCamera(String cameraName) =>
      _backend.countVideosForCamera(cameraName);

  Future<int> put(Video video) => _backend.putVideo(video);

  Future<List<int>> putManyAsync(List<Video> videos) =>
      _backend.putManyVideos(videos);

  Future<void> removeMany(List<int> ids) => _backend.removeVideos(ids);
}

class AppDetectionStore {
  AppDetectionStore._(this._backend);

  final _AppStoresBackend _backend;

  Future<List<Detection>> getAllAsync() => _backend.getAllDetections();

  Future<List<Detection>> findByVideoFile(String videoFile) =>
      _backend.findDetectionsByVideoFile(videoFile);

  Future<List<Detection>> findByCameraAndVideoFile(
    String cameraName,
    String videoFile,
  ) => _backend.findDetectionsByCameraAndVideoFile(cameraName, videoFile);

  Future<List<int>> putManyAsync(List<Detection> detections) =>
      _backend.putManyDetections(detections);

  Future<void> removeMany(List<int> ids) => _backend.removeDetections(ids);
}

class AppMetaStore {
  AppMetaStore._(this._backend);

  final _AppStoresBackend _backend;

  Future<List<Meta>> getAllAsync() => _backend.getAllMetas();

  Future<int> putAsync(Meta meta) => _backend.putMeta(meta);
}

/// Holds app storage backends as a single global singleton.
class AppStores {
  static final AppStores _singleton = AppStores._internal();
  AppStores._internal();

  static bool _initialized = false;
  static Future<AppStores>? _opening;
  static bool _closing = false;

  late _AppStoresBackend _backend;
  late AppCameraStore cameraStore;
  late AppVideoStore videoStore;
  late AppDetectionStore detectionStore;
  late AppMetaStore metaStore;

  static Future<AppStores> init() async {
    if (_initialized) return _singleton;
    if (_opening != null) return _opening!;
    _opening = _initInternal().whenComplete(() => _opening = null);
    return _opening!;
  }

  static bool get isInitialized => _initialized;

  static Future<AppStores> _initInternal() async {
    _singleton._backend =
        _fdroidBuild
            ? await _SqfliteAppStoresBackend.open()
            : await _ObjectBoxAppStoresBackend.open();
    _singleton.cameraStore = AppCameraStore._(_singleton._backend);
    _singleton.videoStore = AppVideoStore._(_singleton._backend);
    _singleton.detectionStore = AppDetectionStore._(_singleton._backend);
    _singleton.metaStore = AppMetaStore._(_singleton._backend);
    _initialized = true;
    return _singleton;
  }

  static AppStores get instance {
    if (!_initialized) {
      throw StateError('AppStores.init() MUST be awaited before use.');
    }
    return _singleton;
  }

  Future<void> close() async {
    if (_closing || !_initialized) return;
    _closing = true;
    try {
      await _backend.close();
      _initialized = false;
    } finally {
      _closing = false;
    }
  }
}

class _ObjectBoxAppStoresBackend implements _AppStoresBackend {
  _ObjectBoxAppStoresBackend._({
    required objectbox.Store cameraStore,
    required objectbox.Store videoStore,
    required objectbox.Store detectionStore,
  }) : _cameraStore = cameraStore,
       _videoStore = videoStore,
       _detectionStore = detectionStore;

  final objectbox.Store _cameraStore;
  final objectbox.Store _videoStore;
  final objectbox.Store _detectionStore;

  static Future<_ObjectBoxAppStoresBackend> open() async {
    final docsDir = await AppPaths.dataDirectory();
    final cameraStore = await objectbox.openStore(
      directory: p.join(docsDir.path, 'camera-db'),
    );
    final videoStore = await objectbox.openStore(
      directory: p.join(docsDir.path, 'video-db'),
    );
    final detectionStore = await objectbox.openStore(
      directory: p.join(docsDir.path, 'detection-db'),
    );
    return _ObjectBoxAppStoresBackend._(
      cameraStore: cameraStore,
      videoStore: videoStore,
      detectionStore: detectionStore,
    );
  }

  @override
  Future<List<Camera>> getAllCameras() =>
      _cameraStore.box<Camera>().getAllAsync();

  @override
  Future<List<Camera>> findCamerasByName(String name) async {
    final query =
        _cameraStore
            .box<Camera>()
            .query(objectbox.Camera_.name.equals(name))
            .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<Camera?> findFirstCameraByName(String name) async {
    final query =
        _cameraStore
            .box<Camera>()
            .query(objectbox.Camera_.name.equals(name))
            .build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  Future<int> putCamera(Camera camera) =>
      _cameraStore.box<Camera>().putAsync(camera);

  @override
  Future<List<int>> putManyCameras(List<Camera> cameras) async {
    await _cameraStore.box<Camera>().putManyAsync(cameras);
    return cameras.map((camera) => camera.id).toList(growable: false);
  }

  @override
  Future<bool> removeCamera(int id) async =>
      _cameraStore.box<Camera>().remove(id);

  @override
  Future<List<Video>> getAllVideos() => _videoStore.box<Video>().getAllAsync();

  @override
  Future<List<Video>> listVideosForCamera(
    String cameraName, {
    int? limit,
    int offset = 0,
  }) async {
    final query =
        _videoStore
            .box<Video>()
            .query(objectbox.Video_.camera.equals(cameraName))
            .order(objectbox.Video_.id, flags: objectbox.Order.descending)
            .build()
          ..offset = offset;
    if (limit != null) {
      query.limit = limit;
    }
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Video>> listRecentVideos({int? limit, int offset = 0}) async {
    final query =
        _videoStore
            .box<Video>()
            .query()
            .order(objectbox.Video_.id, flags: objectbox.Order.descending)
            .build()
          ..offset = offset;
    if (limit != null) {
      query.limit = limit;
    }
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<Video?> findFirstVideoForNotification(
    String cameraName,
    String timestampToken,
  ) async {
    final query =
        _videoStore
            .box<Video>()
            .query(
              objectbox.Video_.camera
                  .equals(cameraName)
                  .and(objectbox.Video_.video.contains(timestampToken)),
            )
            .build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  Future<bool> hasVideo(String cameraName, String videoName) async {
    final query =
        _videoStore
            .box<Video>()
            .query(
              objectbox.Video_.camera
                  .equals(cameraName)
                  .and(objectbox.Video_.video.equals(videoName)),
            )
            .build();
    try {
      return query.findFirst() != null;
    } finally {
      query.close();
    }
  }

  @override
  Future<int> countVideosForCamera(String cameraName) async {
    final query =
        _videoStore
            .box<Video>()
            .query(objectbox.Video_.camera.equals(cameraName))
            .build();
    try {
      return query.count();
    } finally {
      query.close();
    }
  }

  @override
  Future<int> putVideo(Video video) => _videoStore.box<Video>().putAsync(video);

  @override
  Future<List<int>> putManyVideos(List<Video> videos) async {
    await _videoStore.box<Video>().putManyAsync(videos);
    return videos.map((video) => video.id).toList(growable: false);
  }

  @override
  Future<void> removeVideos(List<int> ids) async {
    if (ids.isEmpty) return;
    _videoStore.box<Video>().removeMany(ids);
  }

  @override
  Future<List<Detection>> getAllDetections() =>
      _detectionStore.box<Detection>().getAllAsync();

  @override
  Future<List<Detection>> findDetectionsByVideoFile(String videoFile) async {
    final query =
        _detectionStore
            .box<Detection>()
            .query(objectbox.Detection_.videoFile.equals(videoFile))
            .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Detection>> findDetectionsByCameraAndVideoFile(
    String cameraName,
    String videoFile,
  ) async {
    final query =
        _detectionStore
            .box<Detection>()
            .query(
              objectbox.Detection_.camera
                  .equals(cameraName)
                  .and(objectbox.Detection_.videoFile.equals(videoFile)),
            )
            .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<int>> putManyDetections(List<Detection> detections) async {
    await _detectionStore.box<Detection>().putManyAsync(detections);
    return detections.map((detection) => detection.id).toList(growable: false);
  }

  @override
  Future<void> removeDetections(List<int> ids) async {
    if (ids.isEmpty) return;
    _detectionStore.box<Detection>().removeMany(ids);
  }

  @override
  Future<List<Meta>> getAllMetas() => _cameraStore.box<Meta>().getAllAsync();

  @override
  Future<int> putMeta(Meta meta) => _cameraStore.box<Meta>().putAsync(meta);

  @override
  Future<void> close() async {
    _cameraStore.close();
    _videoStore.close();
    _detectionStore.close();
  }
}

class _SqfliteAppStoresBackend implements _AppStoresBackend {
  _SqfliteAppStoresBackend._(this._db);

  final Database _db;

  static Future<_SqfliteAppStoresBackend> open() async {
    final docsDir = await AppPaths.dataDirectory();
    final dbPath = p.join(docsDir.path, 'secluso-fdroid.sqlite');
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cameras (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            unread_messages INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE videos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            camera TEXT NOT NULL,
            video TEXT NOT NULL,
            received INTEGER NOT NULL,
            motion INTEGER NOT NULL,
            UNIQUE(camera, video)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_videos_camera_id ON videos(camera, id DESC)',
        );
        await db.execute('CREATE INDEX idx_videos_video ON videos(video)');
        await db.execute('''
          CREATE TABLE detections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            camera TEXT NOT NULL,
            video_file TEXT NOT NULL,
            confidence REAL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_detections_video_file ON detections(video_file)',
        );
        await db.execute(
          'CREATE INDEX idx_detections_camera_video ON detections(camera, video_file)',
        );
        await db.execute('''
          CREATE TABLE meta (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            db_version INTEGER NOT NULL
          )
        ''');
      },
    );
    return _SqfliteAppStoresBackend._(db);
  }

  @override
  Future<List<Camera>> getAllCameras() async {
    final rows = await _db.query('cameras', orderBy: 'id ASC');
    return rows.map(_cameraFromRow).toList(growable: false);
  }

  @override
  Future<List<Camera>> findCamerasByName(String name) async {
    final rows = await _db.query(
      'cameras',
      where: 'name = ?',
      whereArgs: [name],
      orderBy: 'id ASC',
    );
    return rows.map(_cameraFromRow).toList(growable: false);
  }

  @override
  Future<Camera?> findFirstCameraByName(String name) async {
    final rows = await _db.query(
      'cameras',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _cameraFromRow(rows.first);
  }

  @override
  Future<int> putCamera(Camera camera) => _upsertCamera(_db, camera);

  @override
  Future<List<int>> putManyCameras(List<Camera> cameras) async {
    if (cameras.isEmpty) return const <int>[];
    return _db.transaction((txn) async {
      final ids = <int>[];
      for (final camera in cameras) {
        ids.add(await _upsertCamera(txn, camera));
      }
      return ids;
    });
  }

  @override
  Future<bool> removeCamera(int id) async {
    final removed = await _db.delete(
      'cameras',
      where: 'id = ?',
      whereArgs: [id],
    );
    return removed > 0;
  }

  @override
  Future<List<Video>> getAllVideos() async {
    final rows = await _db.query('videos', orderBy: 'id ASC');
    return rows.map(_videoFromRow).toList(growable: false);
  }

  @override
  Future<List<Video>> listVideosForCamera(
    String cameraName, {
    int? limit,
    int offset = 0,
  }) async {
    final rows = await _db.query(
      'videos',
      where: 'camera = ?',
      whereArgs: [cameraName],
      orderBy: 'id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_videoFromRow).toList(growable: false);
  }

  @override
  Future<List<Video>> listRecentVideos({int? limit, int offset = 0}) async {
    final rows = await _db.query(
      'videos',
      orderBy: 'id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_videoFromRow).toList(growable: false);
  }

  @override
  Future<Video?> findFirstVideoForNotification(
    String cameraName,
    String timestampToken,
  ) async {
    final rows = await _db.query(
      'videos',
      where: 'camera = ? AND video LIKE ?',
      whereArgs: [cameraName, '%$timestampToken%'],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _videoFromRow(rows.first);
  }

  @override
  Future<bool> hasVideo(String cameraName, String videoName) async {
    final rows = await _db.query(
      'videos',
      columns: const ['id'],
      where: 'camera = ? AND video = ?',
      whereArgs: [cameraName, videoName],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<int> countVideosForCamera(String cameraName) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM videos WHERE camera = ?',
      [cameraName],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  @override
  Future<int> putVideo(Video video) => _upsertVideo(_db, video);

  @override
  Future<List<int>> putManyVideos(List<Video> videos) async {
    if (videos.isEmpty) return const <int>[];
    return _db.transaction((txn) async {
      final ids = <int>[];
      for (final video in videos) {
        ids.add(await _upsertVideo(txn, video));
      }
      return ids;
    });
  }

  @override
  Future<void> removeVideos(List<int> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await _db.delete('videos', where: 'id IN ($placeholders)', whereArgs: ids);
  }

  @override
  Future<List<Detection>> getAllDetections() async {
    final rows = await _db.query('detections', orderBy: 'id ASC');
    return rows.map(_detectionFromRow).toList(growable: false);
  }

  @override
  Future<List<Detection>> findDetectionsByVideoFile(String videoFile) async {
    final rows = await _db.query(
      'detections',
      where: 'video_file = ?',
      whereArgs: [videoFile],
      orderBy: 'id ASC',
    );
    return rows.map(_detectionFromRow).toList(growable: false);
  }

  @override
  Future<List<Detection>> findDetectionsByCameraAndVideoFile(
    String cameraName,
    String videoFile,
  ) async {
    final rows = await _db.query(
      'detections',
      where: 'camera = ? AND video_file = ?',
      whereArgs: [cameraName, videoFile],
      orderBy: 'id ASC',
    );
    return rows.map(_detectionFromRow).toList(growable: false);
  }

  @override
  Future<List<int>> putManyDetections(List<Detection> detections) async {
    if (detections.isEmpty) return const <int>[];
    return _db.transaction((txn) async {
      final ids = <int>[];
      for (final detection in detections) {
        ids.add(await _upsertDetection(txn, detection));
      }
      return ids;
    });
  }

  @override
  Future<void> removeDetections(List<int> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await _db.delete(
      'detections',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  @override
  Future<List<Meta>> getAllMetas() async {
    final rows = await _db.query('meta', orderBy: 'id ASC');
    return rows.map(_metaFromRow).toList(growable: false);
  }

  @override
  Future<int> putMeta(Meta meta) async {
    if (meta.id != 0) {
      await _db.update(
        'meta',
        {'db_version': meta.dbVersion},
        where: 'id = ?',
        whereArgs: [meta.id],
      );
      return meta.id;
    }

    final existing = await _db.query('meta', orderBy: 'id ASC', limit: 1);
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      meta.id = id;
      await _db.update(
        'meta',
        {'db_version': meta.dbVersion},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }

    final id = await _db.insert('meta', {'db_version': meta.dbVersion});
    meta.id = id;
    return id;
  }

  @override
  Future<void> close() => _db.close();

  Future<int> _upsertCamera(DatabaseExecutor executor, Camera camera) async {
    if (camera.id != 0) {
      await executor.update(
        'cameras',
        {'name': camera.name, 'unread_messages': camera.unreadMessages ? 1 : 0},
        where: 'id = ?',
        whereArgs: [camera.id],
      );
      return camera.id;
    }

    final existing = await executor.query(
      'cameras',
      columns: const ['id'],
      where: 'name = ?',
      whereArgs: [camera.name],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      camera.id = id;
      await executor.update(
        'cameras',
        {'name': camera.name, 'unread_messages': camera.unreadMessages ? 1 : 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }

    final id = await executor.insert('cameras', {
      'name': camera.name,
      'unread_messages': camera.unreadMessages ? 1 : 0,
    });
    camera.id = id;
    return id;
  }

  Future<int> _upsertVideo(DatabaseExecutor executor, Video video) async {
    if (video.id != 0) {
      await executor.update(
        'videos',
        {
          'camera': video.camera,
          'video': video.video,
          'received': video.received ? 1 : 0,
          'motion': video.motion ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [video.id],
      );
      return video.id;
    }

    final existing = await executor.query(
      'videos',
      columns: const ['id'],
      where: 'camera = ? AND video = ?',
      whereArgs: [video.camera, video.video],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      video.id = id;
      await executor.update(
        'videos',
        {
          'camera': video.camera,
          'video': video.video,
          'received': video.received ? 1 : 0,
          'motion': video.motion ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }

    final id = await executor.insert('videos', {
      'camera': video.camera,
      'video': video.video,
      'received': video.received ? 1 : 0,
      'motion': video.motion ? 1 : 0,
    });
    video.id = id;
    return id;
  }

  Future<int> _upsertDetection(
    DatabaseExecutor executor,
    Detection detection,
  ) async {
    if (detection.id != 0) {
      await executor.update(
        'detections',
        {
          'type': detection.type,
          'camera': detection.camera,
          'video_file': detection.videoFile,
          'confidence': detection.confidence,
        },
        where: 'id = ?',
        whereArgs: [detection.id],
      );
      return detection.id;
    }

    final id = await executor.insert('detections', {
      'type': detection.type,
      'camera': detection.camera,
      'video_file': detection.videoFile,
      'confidence': detection.confidence,
    });
    detection.id = id;
    return id;
  }

  static Camera _cameraFromRow(Map<String, Object?> row) {
    return Camera(
      row['name'] as String,
      unreadMessages: (row['unread_messages'] as int? ?? 0) != 0,
      id: row['id'] as int? ?? 0,
    );
  }

  static Video _videoFromRow(Map<String, Object?> row) {
    return Video(
      row['camera'] as String,
      row['video'] as String,
      (row['received'] as int? ?? 0) != 0,
      (row['motion'] as int? ?? 0) != 0,
      id: row['id'] as int? ?? 0,
    );
  }

  static Detection _detectionFromRow(Map<String, Object?> row) {
    return Detection(
      id: row['id'] as int? ?? 0,
      type: row['type'] as String,
      camera: row['camera'] as String,
      videoFile: row['video_file'] as String,
      confidence: (row['confidence'] as num?)?.toDouble(),
    );
  }

  static Meta _metaFromRow(Map<String, Object?> row) {
    return Meta(dbVersion: row['db_version'] as int? ?? 0)
      ..id = row['id'] as int? ?? 0;
  }
}
