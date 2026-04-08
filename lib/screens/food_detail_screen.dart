import 'package:flutter/material.dart';
import 'dart:convert' show base64Decode;
import '../models/food_item.dart';
import '../services/neon_database_service.dart';
import '../services/food_image_service.dart';
import '../services/app_logger.dart';
import '../l10n/app_localizations.dart';
import 'add_food_entry_screen.dart';

/// Detailed view of a food item from the database.
/// Shows nutrition info, image, and provides a button to log this food as an entry.
class FoodDetailScreen extends StatefulWidget {
  final FoodItem food;
  final NeonDatabaseService dbService;

  const FoodDetailScreen({
    super.key,
    required this.food,
    required this.dbService,
  });

  @override
  State<FoodDetailScreen> createState() => _FoodDetailScreenState();
}

class _FoodDetailScreenState extends State<FoodDetailScreen> {
  late FoodImageService _imageService;

  @override
  void initState() {
    super.initState();
    _imageService = FoodImageService(widget.dbService);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.food.name),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image header
            if (widget.food.hasImage)
              _buildImageHeader()
            else
              _buildLetterHeader(),
            const SizedBox(height: 16),

            // Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Food name and metadata
                  Text(
                    widget.food.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (widget.food.brand != null || widget.food.category != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        [
                          if (widget.food.brand != null) widget.food.brand,
                          if (widget.food.category != null) widget.food.category,
                        ].join(' • '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                      ),
                    ),
                  const SizedBox(height: 20),

                  // Nutrition table
                  Text(
                    l?.nutritionInfo ?? 'Nutrition Info',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _buildNutritionTable(context, l),
                  const SizedBox(height: 20),

                  // Serving sizes
                  if (widget.food.servingSize != null || widget.food.portions.isNotEmpty)
                    _buildServingSizes(context, l),

                  // Source/barcode
                  if (widget.food.source != null || widget.food.barcode != null) ...[
                    const SizedBox(height: 20),
                    _buildMetadata(context),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddFoodEntryScreen(
                dbService: widget.dbService,
                selectedDate: DateTime.now(),
                preselectedFood: widget.food,
              ),
            ),
          );
        },
        label: Text(l?.logFood ?? 'Log Food'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildImageHeader() {
    return FutureBuilder<String?>(
      future: _imageService.fetchImage(widget.food.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 200,
            color: Colors.grey.shade200,
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          try {
            final imageBytes = base64Decode(snapshot.data!);
            return Image.memory(
              imageBytes,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            );
          } catch (e) {
            appLogger.e('FoodDetailScreen: Error decoding image: $e');
            return _buildLetterHeader();
          }
        }

        return _buildLetterHeader();
      },
    );
  }

  Widget _buildLetterHeader() {
    return Container(
      height: 200,
      width: double.infinity,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Center(
        child: Text(
          widget.food.name[0].toUpperCase(),
          style: TextStyle(
            fontSize: 80,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }

  Widget _buildNutritionTable(BuildContext context, AppLocalizations? l) {
    final data = [
      ('Calories', '${widget.food.calories.toStringAsFixed(1)} kcal'),
      ('Protein', '${widget.food.protein.toStringAsFixed(1)}g'),
      ('Fat', '${widget.food.fat.toStringAsFixed(1)}g'),
      ('Carbs', '${widget.food.carbs.toStringAsFixed(1)}g'),
      if (widget.food.fiber != null) ('Fiber', '${widget.food.fiber!.toStringAsFixed(1)}g'),
      if (widget.food.sugar != null) ('Sugar', '${widget.food.sugar!.toStringAsFixed(1)}g'),
      if (widget.food.sodium != null) ('Sodium', '${widget.food.sodium!.toStringAsFixed(1)}mg'),
      if (widget.food.saturatedFat != null)
        ('Saturated Fat', '${widget.food.saturatedFat!.toStringAsFixed(1)}g'),
    ];

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(1),
      },
      children: [
        for (final (label, value) in data)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildServingSizes(BuildContext context, AppLocalizations? l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Serving Sizes',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (widget.food.servingSize != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${widget.food.servingSize!.toStringAsFixed(0)} ${widget.food.servingUnit ?? 'g'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        if (widget.food.portions.isNotEmpty)
          ...widget.food.portions.map(
            (portion) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${portion.name}: ${portion.amountG.toStringAsFixed(0)}g',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMetadata(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.food.source != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Source: ${widget.food.source}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (widget.food.barcode != null)
          Text(
            'Barcode: ${widget.food.barcode}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
