// Web stub for image_picker
// On web, we use HTML file input
import 'package:web/web.dart' as web;
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert' show base64Encode;
import 'dart:js_interop';

/// Convert a JS ArrayBuffer to Dart Uint8List using dart:js_interop
Uint8List _jsArrayBufferToUint8List(JSObject arrayBuffer) {
  // Cast ArrayBuffer to Uint8Array and convert to Dart List
  // The readAsArrayBuffer result in FileReader can be directly converted
  try {
    // Try to interpret the result as a list of numbers
    final jsArray = arrayBuffer as JSArray<JSNumber>;
    final dartList = jsArray.toDart;
    final intList = dartList.map((e) => e.toDartInt).toList();
    return Uint8List.fromList(intList);
  } catch (_) {
    // Fallback: return empty list if conversion fails
    return Uint8List(0);
  }
}

/// Web-compatible image picker stub
class ImagePicker {
  /// Pick an image from the web file input
  Future<XFile?> pickImage({required ImageSource source}) async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'image/*'
      ..style.display = 'none';

    web.document.body!.appendChild(input);

    final completer = Completer<XFile?>();

    input.onChange.listen((_) async {
      try {
        final files = input.files;
        if (files != null && files.length > 0) {
          final file = files.item(0) as web.File;
          final reader = web.FileReader();

          // Use a Completer wrapper to handle the loadend event
          reader.onloadend = (web.ProgressEvent event) {
            try {
              // Convert ArrayBuffer result to Uint8List
              final jsResult = reader.result as JSObject;

              // Use dart:js_interop to convert to Dart list
              final uint8List = _jsArrayBufferToUint8List(jsResult);

              final xfile = XFile.fromData(
                uint8List,
                mimeType: file.type,
                name: file.name,
              );
              completer.complete(xfile);
            } catch (e) {
              completer.complete(null);
            }
            return null;
          }.toJS as web.EventHandler;

          // Handle error event
          reader.onerror = (web.ProgressEvent event) {
            completer.complete(null);
            return null;
          }.toJS as web.EventHandler;

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
