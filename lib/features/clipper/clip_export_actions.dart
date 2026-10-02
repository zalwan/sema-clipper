import 'dart:io';

import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

abstract interface class ClipExportActions {
  Future<bool> saveToGallery(String path);

  Future<void> share(String path);
}

final class DeviceClipExportActions implements ClipExportActions {
  @override
  Future<bool> saveToGallery(String path) async {
    final result = await SaverGallery.saveFile(
      filePath: path,
      fileName: File(path).uri.pathSegments.last,
      albumPath: 'SEMA Clipper',
      skipIfExists: false,
    );
    return result.isSuccess;
  }

  @override
  Future<void> share(String path) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'video/mp4')],
        text: 'Created with SEMA Clipper',
      ),
    );
  }
}
