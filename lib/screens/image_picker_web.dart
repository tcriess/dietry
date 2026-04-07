// Web stub for image_picker
// On web, we use HTML file input
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert' show base64Encode;

/// Web-compatible image picker stub
class ImagePicker {
  /// Pick an image from the web file input
  Future<XFile?> pickImage({required ImageSource source}) async {
    final input = html.FileUploadInputElement()
      ..accept = 'image/*'
      ..style.display = 'none';

    html.document.body!.append(input);

    final completer = Completer<XFile?>();

    input.onChange.listen((_) async {
      try {
        final files = input.files;
        if (files != null && files.isNotEmpty) {
          final file = files.first;
          final reader = html.FileReader();

          reader.onLoadEnd.listen((_) {
            try {
              final result = reader.result;
              if (result is List<int>) {
                final bytes = Uint8List.fromList(result);
                final xfile = XFile.fromData(
                  bytes,
                  mimeType: file.type,
                  name: file.name,
                );
                completer.complete(xfile);
              } else {
                completer.complete(null);
              }
            } catch (e) {
              completer.complete(null);
            }
          });

          reader.onError.listen((_) {
            completer.complete(null);
          });

          reader.readAsArrayBuffer(file);
        } else {
          completer.complete(null);
        }
      } catch (e) {
        completer.complete(null);
      } finally {
        // Clean up the input element
        try {
          input.remove();
        } catch (_) {}
      }
    });

    // Timeout in case nothing happens
    Future.delayed(const Duration(minutes: 5)).then((_) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      try {
        input.remove();
      } catch (_) {}
    });

    input.click();
    return completer.future;
  }
}

/// Web-compatible file representation
class XFile {
  final Uint8List _bytes;
  final String mimeType;
  final String name;
  final String path;

  XFile({
    required Uint8List bytes,
    required this.mimeType,
    required this.name,
    this.path = '',
  }) : _bytes = bytes;

  factory XFile.fromData(
    Uint8List bytes, {
    required String? mimeType,
    required String name,
    String path = '',
  }) {
    return XFile(
      bytes: bytes,
      mimeType: mimeType ?? 'application/octet-stream',
      name: name,
      path: path,
    );
  }

  Future<Uint8List> readAsBytes() async => _bytes;

  String get base64 => base64Encode(_bytes);
}

/// Image source enum for consistency
enum ImageSource { gallery, camera }
