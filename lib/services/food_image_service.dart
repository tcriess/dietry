import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'app_logger.dart';
import 'neon_database_service.dart';

/// Service to manage food images (upload, fetch, delete).
/// Images are stored as base64 in the food_images table.
class FoodImageService {
  final NeonDatabaseService _db;

  FoodImageService(this._db);

  /// Fetch base64 image string for a food. Returns null if no image.
  Future<String?> fetchImage(String foodId) async {
    try {
      appLogger.d('FoodImageService.fetchImage: Starting fetch for food $foodId');

      // Query the food_images table for this food
      final response = await _db.client
          .from('food_images')
          .select('image_data')
          .eq('food_id', foodId)
          .maybeSingle();

      appLogger.d('FoodImageService.fetchImage: Response type: ${response.runtimeType}');

      if (response == null) {
        appLogger.d('FoodImageService.fetchImage: No image found for food $foodId (null response)');
        return null;
      }

      // Handle response as a Map
      final imageData = response['image_data'] as String?;

      if (imageData == null) {
        appLogger.w('FoodImageService.fetchImage: image_data is null in response');
        return null;
      }

      appLogger.i('FoodImageService.fetchImage: Image fetched successfully (${imageData.length} chars base64)');
      return imageData;
    } catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains('0 rows') ||
          errorStr.contains('no rows') ||
          errorStr.contains('PgError') ||
          errorStr.contains('HTTP 406')) {
        appLogger.d('FoodImageService.fetchImage: No image found for food $foodId');
        return null;
      }
      appLogger.e('FoodImageService.fetchImage: Error fetching image for food $foodId: $e', error: e);
      return null;
    }
  }

  /// Compress, base64-encode, and upsert image.
  /// Target: max 512×512px, quality 80, JPEG.
  /// Throws if compression fails.
  Future<void> saveImage(String foodId, Uint8List rawBytes) async {
    try {
      appLogger.i('FoodImageService: Compressing image for food $foodId');

      // Compress the image
      final compressed = await FlutterImageCompress.compressWithList(
        rawBytes,
        minHeight: 512,
        minWidth: 512,
        quality: 80,
        format: CompressFormat.jpeg,
      );

      appLogger.i('FoodImageService: Compressed (${rawBytes.length} → ${compressed.length} bytes)');

      // Encode to base64
      final base64Image = base64Encode(compressed);
      appLogger.d('FoodImageService: Base64 encoded (${base64Image.length} chars)');

      // Upsert: check if image exists, then update or insert
      try {
        final existingImage = await _db.client
            .from('food_images')
            .select('id')
            .eq('food_id', foodId)
            .maybeSingle();

        if (existingImage != null) {
          // Image exists, update it
          appLogger.d('FoodImageService: Image exists, updating...');
          await _db.dioClient.patch(
            '/food_images?food_id=eq.$foodId',
            data: {
              'image_data': base64Image,
              'content_type': 'image/jpeg',
              'updated_at': DateTime.now().toIso8601String(),
            },
            options: Options(headers: {'Prefer': 'return=minimal'}),
          );
          appLogger.i('FoodImageService: Image updated for food $foodId');
        } else {
          // Image doesn't exist, insert it
          appLogger.d('FoodImageService: Image does not exist, inserting...');
          await _db.dioClient.post(
            '/food_images',
            data: {
              'food_id': foodId,
              'image_data': base64Image,
              'content_type': 'image/jpeg',
            },
            options: Options(headers: {'Prefer': 'return=minimal'}),
          );
          appLogger.i('FoodImageService: Image inserted for food $foodId');
        }
      } catch (upsertError) {
        appLogger.e('FoodImageService: Upsert error: $upsertError', error: upsertError);
        rethrow;
      }

      // Update food_database.has_image flag
      await _db.dioClient.patch(
        '/food_database?id=eq.$foodId',
        data: {'has_image': true},
        options: Options(headers: {'Prefer': 'return=minimal'}),
      );

      appLogger.i('FoodImageService: Saved image for food $foodId');
    } catch (e) {
      appLogger.e('FoodImageService.saveImage error: $e');
      rethrow;
    }
  }

  /// Delete image for a food.
  Future<void> deleteImage(String foodId) async {
    try {
      appLogger.i('FoodImageService: Deleting image for food $foodId');

      await _db.dioClient.delete(
        '/food_images?food_id=eq.$foodId',
        options: Options(headers: {'Prefer': 'return=minimal'}),
      );

      // Update food_database.has_image flag
      await _db.dioClient.patch(
        '/food_database?id=eq.$foodId',
        data: {'has_image': false},
        options: Options(headers: {'Prefer': 'return=minimal'}),
      );

      appLogger.i('FoodImageService: Deleted image for food $foodId');
    } catch (e) {
      appLogger.e('FoodImageService.deleteImage error: $e');
      rethrow;
    }
  }
}
