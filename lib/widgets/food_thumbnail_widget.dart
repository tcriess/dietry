import 'package:flutter/material.dart';
import 'dart:convert' show base64Decode;
import 'package:dietry/models/food_item.dart';
import 'package:dietry/services/app_logger.dart';
import 'package:dietry/services/food_image_service.dart';

/// Widget to display a food thumbnail with image or letter avatar fallback.
/// Shows cached image if available, otherwise fetches it asynchronously.
class FoodThumbnailWidget extends StatefulWidget {
  final FoodItem food;
  final FoodImageService imageService;
  final Map<String, String?> imageCache;

  const FoodThumbnailWidget({
    super.key,
    required this.food,
    required this.imageService,
    required this.imageCache,
  });

  @override
  State<FoodThumbnailWidget> createState() => _FoodThumbnailWidgetState();
}

class _FoodThumbnailWidgetState extends State<FoodThumbnailWidget> {
  late Future<String?> _imageFuture;

  @override
  void initState() {
    super.initState();
    // Use cached image if available, otherwise fetch it
    if (widget.imageCache.containsKey(widget.food.id)) {
      _imageFuture = Future.value(widget.imageCache[widget.food.id]);
    } else {
      _imageFuture = widget.imageService.fetchImage(widget.food.id).then((image) {
        widget.imageCache[widget.food.id] = image;
        return image;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.food.hasImage) {
      // No image, show letter avatar
      return CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          widget.food.name[0].toUpperCase(),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    // Image available, load and display it
    return FutureBuilder<String?>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Loading state
          return CircleAvatar(
            backgroundColor: Colors.grey.shade300,
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          // Error or no image, fall back to letter avatar
          appLogger.d('FoodThumbnailWidget: Failed to load image for ${widget.food.name}');
          return CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              widget.food.name[0].toUpperCase(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }

        // Display image thumbnail
        try {
          final imageBytes = base64Decode(snapshot.data!);
          return CircleAvatar(
            backgroundImage: MemoryImage(imageBytes),
            backgroundColor: Colors.grey.shade300,
          );
        } catch (e) {
          appLogger.e('FoodThumbnailWidget: Error decoding image for ${widget.food.name}: $e');
          // Fallback to letter avatar if decoding fails
          return CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              widget.food.name[0].toUpperCase(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }
      },
    );
  }
}
