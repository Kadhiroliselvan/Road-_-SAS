import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class MbTilesTileProvider extends TileProvider {
  final Database db;

  MbTilesTileProvider({required this.db});

  static Future<MbTilesTileProvider?> create(String filename) async {
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      final String path = join(dir.path, filename);
      
      if (!File(path).existsSync()) {
        debugPrint("MBTiles file not found at: $path. Attempting to copy from assets...");
        try {
          // Try to copy from assets if it exists there
          ByteData data = await rootBundle.load("assets/$filename");
          List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          await File(path).writeAsBytes(bytes, flush: true);
          debugPrint("Successfully copied MBTiles from assets to $path");
        } catch (e) {
          debugPrint("Failed to copy from assets: $e");
          return null;
        }
      }
      
      final Database db = await openDatabase(path, readOnly: true);
      return MbTilesTileProvider(db: db);
    } catch (e) {
      debugPrint("Error opening MBTiles database: $e");
      return null;
    }
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _MbTilesImageProvider(coordinates, options, db);
  }
}

class _MbTilesImageProvider extends ImageProvider<_MbTilesImageProvider> {
  final TileCoordinates coordinates;
  final TileLayer options;
  final Database db;

  _MbTilesImageProvider(this.coordinates, this.options, this.db);

  @override
  Future<_MbTilesImageProvider> obtainKey(ImageConfiguration configuration) {
    return Future.value(this);
  }

  @override
  ImageStreamCompleter loadImage(_MbTilesImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      informationCollector: () => [
        DiagnosticsProperty<_MbTilesImageProvider>('ImageProvider', key),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(_MbTilesImageProvider key, ImageDecoderCallback decode) async {
    try {
      final int z = key.coordinates.z;
      final int x = key.coordinates.x;
      // MBTiles TMS format uses flipped Y
      final int y = (1 << z) - 1 - key.coordinates.y;

      final List<Map<String, dynamic>> result = await db.query(
        'tiles',
        columns: ['tile_data'],
        where: 'zoom_level = ? AND tile_column = ? AND tile_row = ?',
        whereArgs: [z, x, y],
      );

      if (result.isNotEmpty) {
        final Uint8List tileData = result.first['tile_data'] as Uint8List;
        return await decode(await ui.ImmutableBuffer.fromUint8List(tileData));
      } else {
        // Return a transparent tile if not found
        final Uint8List transparentTile = Uint8List.fromList([
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
          0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
          0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00,
          0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
          0x89, 0x00, 0x00, 0x00, 0x01, 0x73, 0x52, 0x47,
          0x42, 0x00, 0xAE, 0xCE, 0x1C, 0xE9, 0x00, 0x00,
          0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x18, 0x57,
          0x63, 0x60, 0x60, 0x60, 0x60, 0x00, 0x00, 0x00,
          0x05, 0x00, 0x01, 0x2A, 0x14, 0x16, 0x0F, 0x00,
          0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
          0x42, 0x60, 0x82
        ]);
        return await decode(await ui.ImmutableBuffer.fromUint8List(transparentTile));
      }
    } catch (e) {
      debugPrint('Error loading tile from MBTiles: $e');
      throw Exception('Tile loading failed');
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is _MbTilesImageProvider &&
           other.coordinates == coordinates;
  }

  @override
  int get hashCode => coordinates.hashCode;
}
