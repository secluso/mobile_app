//! SPDX-License-Identifier: GPL-3.0-or-later

import 'app_stores.dart';
import 'migrations.dart';
import 'entities.dart';
import 'package:secluso_flutter/utilities/logger.dart';

Future<void> runMigrations() async {
  final metaStore = AppStores.instance.metaStore;
  List<Meta> metas = await metaStore.getAllAsync();
  Meta? meta;

  if (metas.isEmpty) {
    meta = Meta(dbVersion: 0);
    meta.id = await metaStore.putAsync(meta);
    Log.d("Assuming legacy user. Performing all migrations");
  } else {
    meta = metas.first;
  }

  final currentVersion = meta.dbVersion;
  final latestVersion = migrations.length;
  for (int i = currentVersion; i < latestVersion; i++) {
    Log.d("Applying migration ${i + 1}...");
    await migrations[i]();
    meta.dbVersion = i + 1;
    meta.id = await metaStore.putAsync(meta);
    Log.d("Updated DB version to ${meta.dbVersion}");
  }

  if (currentVersion == latestVersion) {
    Log.d("Already up to date. No migrations needed.");
  } else {
    Log.d("Migrations complete.");
  }
}
