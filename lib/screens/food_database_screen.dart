import 'dart:convert' show base64Decode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart' if (dart.library.html) 'image_picker_web.dart';
import 'package:dietry_cloud/dietry_cloud.dart';
import '../models/food_item.dart';
import '../models/food_portion.dart';
import '../models/tag.dart';
import '../services/food_database_service.dart';
import '../services/food_image_service.dart';
import '../services/tag_service.dart';
import '../services/neon_database_service.dart';
import '../services/app_logger.dart';
import '../app_features.dart';
import '../l10n/app_localizations.dart';
import '../widgets/food_thumbnail_widget.dart';
import '../widgets/tag_editor.dart';
import 'food_detail_screen.dart';

/// Screen zur Verwaltung eigener Lebensmittel in der Datenbank.
///
/// Listet alle privaten (eigenen) Einträge mit Edit/Delete.
/// Wenn [pickerMode] = true: Tippen auf einen Eintrag gibt ihn als Pop-Ergebnis zurück
/// (für Auswahl in AddFoodEntryScreen).
/// Wenn [pickerMode] = false: Tippen öffnet ein Detail-Page (Browsing-Modus).
class FoodDatabaseScreen extends StatefulWidget {
  final NeonDatabaseService dbService;
  final bool pickerMode;

  const FoodDatabaseScreen({
    super.key,
    required this.dbService,
    this.pickerMode = true,
  });

  @override
  State<FoodDatabaseScreen> createState() => _FoodDatabaseScreenState();
}

class _FoodDatabaseScreenState extends State<FoodDatabaseScreen> {
  List<FoodItem> _foods = [];
  bool _isLoading = true;
  final Map<String, String?> _imageCache = {}; // Cache fetched images
  late FoodImageService _imageService;

  @override
  void initState() {
    super.initState();
    _imageService = FoodImageService(widget.dbService);
    _loadFoods();
  }

  Future<void> _loadFoods() async {
    appLogger.d('_loadFoods: Starting to load foods from database');
    setState(() => _isLoading = true);
    try {
      final service = FoodDatabaseService(widget.dbService);
      final foods = await service.getMyFoods();
      appLogger.d('_loadFoods: Loaded ${foods.length} foods');
      for (final f in foods) {
        if (f.hasImage) {
          appLogger.d('_loadFoods: Food ${f.name} has hasImage=true');
        }
      }
      if (mounted) setState(() => _foods = foods);
    } catch (e) {
      appLogger.e('_loadFoods: Error loading foods: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editFood(FoodItem food) async {
    appLogger.d('_editFood: Opening dialog for ${food.name}, hasImage=${food.hasImage}');
    final result = await showDialog<FoodItem>(
      context: context,
      builder: (context) => FoodEditDialog(food: food, dbService: widget.dbService),
    );
    if (result == null) {
      appLogger.d('_editFood: Dialog cancelled');
      return;
    }

    appLogger.d('_editFood: Dialog returned food ${result.name}, hasImage=${result.hasImage}');

    try {
      final service = FoodDatabaseService(widget.dbService);
      await service.updateFood(result);
      appLogger.d('_editFood: Food updated, hasImage=${result.hasImage}');
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.foodUpdated(result.name)),
            backgroundColor: Colors.green,
          ),
        );
      }
      appLogger.d('_editFood: Reloading foods from database');
      _loadFoods();
    } catch (e) {
      appLogger.e('_editFood: Error updating food: $e');
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorPrefix(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleFavourite(FoodItem food) async {
    final newValue = !food.isFavourite;
    // Optimistic update
    setState(() {
      final idx = _foods.indexWhere((f) => f.id == food.id);
      if (idx != -1) _foods[idx] = food.copyWith(isFavourite: newValue);
    });
    try {
      await FoodDatabaseService(widget.dbService)
          .toggleFoodFavourite(food.id, isFavourite: newValue);
    } catch (e) {
      // Revert on error
      setState(() {
        final idx = _foods.indexWhere((f) => f.id == food.id);
        if (idx != -1) _foods[idx] = food;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteFood(FoodItem food) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l.deleteFoodTitle),
          content: Text(l.deleteFoodConfirm(food.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    try {
      final service = FoodDatabaseService(widget.dbService);
      await service.deleteFood(food.id);
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.foodDeleted), backgroundColor: Colors.green),
        );
      }
      _loadFoods();
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorPrefix(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addFood() async {
    final result = await showDialog<FoodItem>(
      context: context,
      builder: (context) => FoodEditDialog(food: null, dbService: widget.dbService),
    );
    if (result == null) return;

    try {
      final service = FoodDatabaseService(widget.dbService);
      final created = await service.createFood(result);
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.foodAdded(created.name)),
            backgroundColor: Colors.green,
          ),
        );
      }
      _loadFoods();
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorPrefix(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.foodDatabaseTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFoods,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addFood,
        tooltip: l.add,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _foods.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.no_food, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        l.entriesEmpty,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.foodDatabaseEmpty,
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88, top: 8, left: 4, right: 4),
                  itemCount: _foods.length,
                  itemBuilder: (context, index) {
                    final food = _foods[index];
                    final isSmallScreen = MediaQuery.of(context).size.width < 500;

                    return GestureDetector(
                      onTap: () {
                        if (widget.pickerMode) {
                          Navigator.of(context).pop(food);
                        } else {
                          // Navigate to food detail screen (not yet created)
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => FoodDetailScreen(
                                food: food,
                                dbService: widget.dbService,
                              ),
                            ),
                          );
                        }
                      },
                      child: Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Thumbnail
                              FoodThumbnailWidget(
                                food: food,
                                imageService: _imageService,
                                imageCache: _imageCache,
                              ),
                              const SizedBox(width: 12),

                              // Content
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Name + Status badge
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            food.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (food.isPublic && !isSmallScreen)
                                          Container(
                                            margin: const EdgeInsets.only(left: 8),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: food.isApproved
                                                  ? Colors.green.shade100
                                                  : Colors.orange.shade100,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  food.isApproved ? Icons.public : Icons.pending_outlined,
                                                  size: 12,
                                                  color: food.isApproved
                                                      ? Colors.green.shade700
                                                      : Colors.orange.shade700,
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  food.isApproved ? l.statusPublic : l.statusPending,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: food.isApproved
                                                        ? Colors.green.shade700
                                                        : Colors.orange.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),

                                    // Nutrition info
                                    Text(
                                      '${food.calories.toInt()} kcal • '
                                      'P ${food.protein.toStringAsFixed(0)}g • '
                                      'F ${food.fat.toStringAsFixed(0)}g • '
                                      'C ${food.carbs.toStringAsFixed(0)}g'
                                      '${food.category != null ? ' • ${food.category}' : ''}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),

                                    // Public status badge on small screens
                                    if (food.isPublic && isSmallScreen) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: food.isApproved
                                              ? Colors.green.shade100
                                              : Colors.orange.shade100,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              food.isApproved ? Icons.public : Icons.pending_outlined,
                                              size: 10,
                                              color: food.isApproved
                                                  ? Colors.green.shade700
                                                  : Colors.orange.shade700,
                                            ),
                                            const SizedBox(width: 2),
                                            Text(
                                              food.isApproved ? l.statusPublic : l.statusPending,
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: food.isApproved
                                                    ? Colors.green.shade700
                                                    : Colors.orange.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Actions
                              if (!isSmallScreen)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        food.isFavourite ? Icons.star : Icons.star_border,
                                        size: 20,
                                        color: food.isFavourite
                                            ? Colors.amber.shade600
                                            : Colors.grey.shade400,
                                      ),
                                      tooltip: food.isFavourite
                                          ? 'Aus Favoriten entfernen'
                                          : 'Als Favorit markieren',
                                      onPressed: () => _toggleFavourite(food),
                                      padding: EdgeInsets.zero,
                                      constraints:
                                          const BoxConstraints(minWidth: 32, minHeight: 32),
                                    ),
                                    if (AppFeatures.microNutrients)
                                      IconButton(
                                        icon: const Icon(Icons.science_outlined, size: 20),
                                        tooltip: 'Mikronährstoffe',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                        onPressed: () {
                                          final jwt = widget.dbService.jwt;
                                          final userId = widget.dbService.userId;
                                          if (jwt == null || userId == null) return;
                                          premiumFeatures.showFoodDatabaseMicrosSheet(
                                            context: context,
                                            foodId: food.id,
                                            foodName: food.name,
                                            userId: userId,
                                            authToken: jwt,
                                            apiUrl: NeonDatabaseService.dataApiUrl,
                                          );
                                        },
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 20),
                                      tooltip: l.edit,
                                      onPressed: () => _editFood(food),
                                      padding: EdgeInsets.zero,
                                      constraints:
                                          const BoxConstraints(minWidth: 32, minHeight: 32),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                      tooltip: l.delete,
                                      onPressed: () => _deleteFood(food),
                                      padding: EdgeInsets.zero,
                                      constraints:
                                          const BoxConstraints(minWidth: 32, minHeight: 32),
                                    ),
                                  ],
                                )
                              else
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    switch (value) {
                                      case 'favourite':
                                        _toggleFavourite(food);
                                      case 'micros':
                                        final jwt = widget.dbService.jwt;
                                        final userId = widget.dbService.userId;
                                        if (jwt == null || userId == null) return;
                                        premiumFeatures.showFoodDatabaseMicrosSheet(
                                          context: context,
                                          foodId: food.id,
                                          foodName: food.name,
                                          userId: userId,
                                          authToken: jwt,
                                          apiUrl: NeonDatabaseService.dataApiUrl,
                                        );
                                      case 'edit':
                                        _editFood(food);
                                      case 'delete':
                                        _deleteFood(food);
                                    }
                                  },
                                  itemBuilder: (BuildContext context) => [
                                    PopupMenuItem(
                                      value: 'favourite',
                                      child: Row(
                                        children: [
                                          Icon(
                                            food.isFavourite ? Icons.star : Icons.star_border,
                                            color: food.isFavourite
                                                ? Colors.amber.shade600
                                                : Colors.grey.shade600,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(food.isFavourite
                                              ? 'Aus Favoriten entfernen'
                                              : 'Als Favorit markieren'),
                                        ],
                                      ),
                                    ),
                                    if (AppFeatures.microNutrients)
                                      PopupMenuItem(
                                        value: 'micros',
                                        child: Row(
                                          children: const [
                                            Icon(Icons.science_outlined),
                                            SizedBox(width: 8),
                                            Text('Mikronährstoffe'),
                                          ],
                                        ),
                                      ),
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: const [
                                          Icon(Icons.edit_outlined),
                                          SizedBox(width: 8),
                                          Text('Bearbeiten'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: const [
                                          Icon(Icons.delete_outline, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Löschen', style: TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

/// Dialog zum Erstellen oder Bearbeiten eines Lebensmittels.
/// [food] == null → neues Lebensmittel anlegen.
class FoodEditDialog extends StatefulWidget {
  final FoodItem? food;
  final NeonDatabaseService dbService;

  const FoodEditDialog({super.key, required this.food, required this.dbService});

  @override
  State<FoodEditDialog> createState() => FoodEditDialogState();
}

class FoodEditDialogState extends State<FoodEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _fatController;
  late final TextEditingController _carbsController;
  late final TextEditingController _categoryController;
  late final TextEditingController _brandController;
  late final TextEditingController _fiberController;
  late final TextEditingController _sugarController;
  late final TextEditingController _sodiumController;
  late final TextEditingController _saturatedFatController;
  final List<({TextEditingController name, TextEditingController amount})> _portionRows = [];
  late bool _isPublic;
  late bool _isLiquid;

  // Image handling
  Uint8List? _selectedImageBytes;
  String? _existingImageBase64;
  bool _isLoadingImage = false;
  bool _isUploadingImage = false;
  bool _imageUploadSuccess = false;
  late FoodImageService _imageService;

  // Tags handling
  late List<Tag> _editingTags;
  late TagService _tagService;

  bool get _isEdit => widget.food != null;

  @override
  void initState() {
    super.initState();
    final f = widget.food;
    appLogger.d('FoodEditDialogState.initState: food=${f?.name}, hasImage=${f?.hasImage}');
    _nameController = TextEditingController(text: f?.name ?? '');
    _caloriesController = TextEditingController(
        text: f != null ? f.calories.toStringAsFixed(0) : '');
    _proteinController = TextEditingController(
        text: f != null ? f.protein.toStringAsFixed(1) : '');
    _fatController =
        TextEditingController(text: f != null ? f.fat.toStringAsFixed(1) : '');
    _carbsController = TextEditingController(
        text: f != null ? f.carbs.toStringAsFixed(1) : '');
    _categoryController = TextEditingController(text: f?.category ?? '');
    _brandController = TextEditingController(text: f?.brand ?? '');
    _fiberController = TextEditingController(
        text: f?.fiber != null ? f!.fiber!.toStringAsFixed(1) : '');
    _sugarController = TextEditingController(
        text: f?.sugar != null ? f!.sugar!.toStringAsFixed(1) : '');
    _sodiumController = TextEditingController(
        text: f?.sodium != null ? f!.sodium!.toStringAsFixed(1) : '');
    _saturatedFatController = TextEditingController(
        text: f?.saturatedFat != null ? f!.saturatedFat!.toStringAsFixed(1) : '');
    for (final p in (widget.food?.portions ?? [])) {
      _portionRows.add((
        name: TextEditingController(text: p.name),
        amount: TextEditingController(
            text: p.amountG % 1 == 0 ? p.amountG.toInt().toString() : p.amountG.toString()),
      ));
    }
    _isPublic = f?.isPublic ?? false;
    _isLiquid = f?.isLiquid ?? false;

    // Initialize image service and load existing image if editing
    _imageService = FoodImageService(widget.dbService);
    if (_isEdit && f!.hasImage) {
      appLogger.d('FoodEditDialogState.initState: Starting image load, hasImage=true');
      _loadExistingImage();
    } else {
      appLogger.d('FoodEditDialogState.initState: Skipping image load (isEdit=$_isEdit, hasImage=${f?.hasImage})');
    }

    // Initialize tag service and load existing tags if editing
    _tagService = TagService(widget.dbService);
    _editingTags = [];
    if (_isEdit) {
      _loadExistingTags();
    }
  }

  Future<void> _loadExistingTags() async {
    if (!_isEdit || widget.food == null) return;
    appLogger.d('_loadExistingTags: Loading tags for food ${widget.food!.id}');
    try {
      final tags = await _tagService.getFoodPublicTags(widget.food!.id);
      if (mounted) {
        setState(() => _editingTags = tags);
      }
      appLogger.d('_loadExistingTags: ${tags.length} tags loaded');
    } catch (e, stackTrace) {
      appLogger.w('_loadExistingTags: Failed to load tags: $e', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _loadExistingImage() async {
    if (!mounted) return;
    appLogger.d('_loadExistingImage: Loading existing image for food ${widget.food!.id}');
    setState(() => _isLoadingImage = true);
    try {
      final image = await _imageService.fetchImage(widget.food!.id);
      if (image != null) {
        appLogger.d('_loadExistingImage: Image loaded successfully, size: ${image.length} bytes');
      } else {
        appLogger.d('_loadExistingImage: No image found');
      }
      if (mounted) {
        setState(() => _existingImageBase64 = image);
      }
    } catch (e, stackTrace) {
      appLogger.w('_loadExistingImage: Failed to load image: $e', error: e, stackTrace: stackTrace);
      // Silently fail — image load is not critical
    } finally {
      if (mounted) {
        setState(() => _isLoadingImage = false);
      }
    }
  }

  Future<void> _pickImage() async {
    appLogger.d('_pickImage: Starting image picker, kIsWeb: $kIsWeb');
    final picker = ImagePicker();
    try {
      appLogger.d('_pickImage: Calling picker.pickImage with gallery source');
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        appLogger.d('_pickImage: File selected: ${pickedFile.path}, mimeType: ${pickedFile.mimeType}');
        try {
          final bytes = await pickedFile.readAsBytes();
          appLogger.d('_pickImage: Successfully read ${bytes.length} bytes');
          setState(() {
            _selectedImageBytes = bytes;
            _existingImageBase64 = null; // Clear existing if picking new
          });
          appLogger.d('_pickImage: Image state updated successfully');
        } catch (readError) {
          appLogger.e('_pickImage: Error reading file bytes: $readError', error: readError);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Fehler beim Lesen der Datei: $readError'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        appLogger.d('_pickImage: No file selected (user cancelled)');
      }
    } on PlatformException catch (e, stackTrace) {
      appLogger.e('_pickImage: Platform error during image selection: ${e.code} - ${e.message}', error: e, stackTrace: stackTrace);

      // Check if this is the Linux file chooser issue
      final isLinuxFileChooserError = e.code == 'channel-error' &&
          e.message?.contains('FileSelectorApi.showFileChooser') == true;

      if (mounted) {
        String errorMsg = 'Fehler beim Laden des Bildes';
        if (isLinuxFileChooserError) {
          errorMsg = 'Bilderauswahl auf Linux nicht verfügbar. '
              'Bitte stellen Sie sicher, dass ein Standard-Dateimanager installiert ist.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e, stackTrace) {
      appLogger.e('_pickImage: Error during image selection: $e', error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Laden des Bildes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteImage() async {
    if (!_isEdit || widget.food == null) {
      appLogger.w('_deleteImage: Invalid state - not editing or food is null');
      return;
    }
    appLogger.d('_deleteImage: Deleting image for food ${widget.food!.id}');
    try {
      await _imageService.deleteImage(widget.food!.id);
      appLogger.i('_deleteImage: Image deleted successfully');
      if (mounted) {
        setState(() {
          _existingImageBase64 = null;
          _selectedImageBytes = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bild gelöscht'), backgroundColor: Colors.green),
        );
      }
    } catch (e, stackTrace) {
      appLogger.e('_deleteImage: Failed to delete image: $e', error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Löschen: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _uploadImageIfSelected(String foodId) async {
    if (_selectedImageBytes == null) {
      appLogger.d('_uploadImageIfSelected: No image selected, skipping upload');
      return;
    }
    if (!mounted) {
      appLogger.d('_uploadImageIfSelected: Widget not mounted, skipping upload');
      return;
    }

    appLogger.d('_uploadImageIfSelected: Starting upload for food $foodId, image size: ${_selectedImageBytes!.length} bytes');
    setState(() => _isUploadingImage = true);
    try {
      await _imageService.saveImage(foodId, _selectedImageBytes!);
      _imageUploadSuccess = true;
      appLogger.i('_uploadImageIfSelected: Image uploaded successfully');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bild hochgeladen'), backgroundColor: Colors.green),
        );
      }
    } catch (e, stackTrace) {
      _imageUploadSuccess = false;
      appLogger.e('_uploadImageIfSelected: Upload failed: $e', error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Hochladen: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingImage = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbsController.dispose();
    _categoryController.dispose();
    _brandController.dispose();
    _fiberController.dispose();
    _sugarController.dispose();
    _sodiumController.dispose();
    _saturatedFatController.dispose();
    for (final row in _portionRows) {
      row.name.dispose();
      row.amount.dispose();
    }
    super.dispose();
  }

  void _save() async {
    appLogger.d('_save: Starting save process, isEdit: $_isEdit');
    if (!_formKey.currentState!.validate()) {
      appLogger.d('_save: Form validation failed');
      return;
    }

    final now = DateTime.now();
    final foodId = widget.food?.id ?? '';

    // Track if image was uploaded or already exists
    bool hasImage = widget.food?.hasImage ?? false;

    // If editing and image is selected, upload it before closing
    if (_isEdit && _selectedImageBytes != null) {
      appLogger.d('_save: Image selected for upload, uploading before closing');
      _imageUploadSuccess = false;
      await _uploadImageIfSelected(foodId);
      if (_imageUploadSuccess) {
        hasImage = true;
      }
    }

    // If deleting an image, hasImage should be false
    if (_existingImageBase64 == null && widget.food?.hasImage == true && _selectedImageBytes == null) {
      hasImage = false;
    }

    final food = FoodItem(
      id: foodId,
      userId: widget.food?.userId,
      name: _nameController.text.trim(),
      calories: double.parse(_caloriesController.text),
      protein: double.parse(_proteinController.text),
      fat: double.parse(_fatController.text),
      carbs: double.parse(_carbsController.text),
      fiber: double.tryParse(_fiberController.text),
      sugar: double.tryParse(_sugarController.text),
      sodium: double.tryParse(_sodiumController.text),
      saturatedFat: double.tryParse(_saturatedFatController.text),
      servingSize: null,
      servingUnit: null,
      portions: _portionRows
          .where((r) => r.name.text.trim().isNotEmpty && r.amount.text.isNotEmpty)
          .map((r) => FoodPortion(
                name: r.name.text.trim(),
                amountG: double.tryParse(r.amount.text) ?? 0,
              ))
          .where((p) => p.amountG > 0)
          .toList(),
      category:
          _categoryController.text.trim().isNotEmpty ? _categoryController.text.trim() : null,
      brand: _brandController.text.trim().isNotEmpty ? _brandController.text.trim() : null,
      barcode: widget.food?.barcode,
      isPublic: _isPublic,
      isApproved: false,  // Immer zurücksetzen – Admin muss erneut freigeben
      isFavourite: widget.food?.isFavourite ?? false,
      isLiquid: _isLiquid,
      hasImage: hasImage,
      source: widget.food?.source ?? 'Custom',
      createdAt: widget.food?.createdAt ?? now,
      updatedAt: now,
    );

    // Save tags if editing and tags were modified
    if (_isEdit && _editingTags.isNotEmpty) {
      appLogger.d('_save: Saving ${_editingTags.length} public tags for food ${food.id}');
      await _tagService.setFoodPublicTags(food.id, _editingTags);
    } else if (_isEdit && _editingTags.isEmpty) {
      appLogger.d('_save: Clearing tags for food ${food.id}');
      await _tagService.setFoodPublicTags(food.id, []);
    }

    if (mounted) {
      appLogger.d('_save: Closing dialog with food: ${food.name}, hasImage: ${food.hasImage}');
      Navigator.of(context).pop(food);
    }
  }

  Widget _numField({
    required TextEditingController controller,
    required String label,
    required String suffix,
    required String requiredMsg,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
      validator: (v) =>
          (v == null || v.isEmpty) ? requiredMsg : null,
    );
  }

  Uint8List _decodeBase64(String base64String) {
    return base64Decode(base64String);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(_isEdit ? l.editEntryTitle : l.newFood),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isEdit && widget.food!.isApproved) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Dieser Eintrag ist öffentlich freigegeben. '
                            'Nach dem Speichern muss er erneut von einem Admin bestätigt werden.',
                            style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Nährwerte pro 100 g bzw. 100 ml angeben',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 16),

                // Name
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: l.foodName,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? l.requiredField : null,
                ),
                const SizedBox(height: 12),

                // Image picker section
                if (_isLoadingImage)
                  const Center(child: CircularProgressIndicator())
                else
                  Column(
                    children: [
                      // Image preview or placeholder
                      Container(
                        width: double.infinity,
                        height: 150,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade100,
                        ),
                        child: _selectedImageBytes != null
                            ? Image.memory(_selectedImageBytes!, fit: BoxFit.cover)
                            : _existingImageBase64 != null
                                ? Image.memory(
                                    _decodeBase64(_existingImageBase64!),
                                    fit: BoxFit.cover,
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.image_not_supported,
                                          size: 48, color: Colors.grey.shade400),
                                      const SizedBox(height: 8),
                                      Text('Kein Bild',
                                          style: TextStyle(color: Colors.grey.shade600)),
                                    ],
                                  ),
                      ),
                      const SizedBox(height: 10),

                      // Image action buttons
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isUploadingImage ? null : _pickImage,
                            icon: const Icon(Icons.photo_camera),
                            label: const Text('Bild wählen'),
                          ),
                          const SizedBox(width: 8),
                          if (_existingImageBase64 != null || _selectedImageBytes != null)
                            ElevatedButton.icon(
                              onPressed: _isUploadingImage ? null : _deleteImage,
                              icon: const Icon(Icons.delete),
                              label: const Text('Löschen'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade100,
                                foregroundColor: Colors.red.shade900,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),

                // Kalorien & Protein
                Row(
                  children: [
                    Expanded(
                        child: _numField(
                            controller: _caloriesController,
                            label: l.foodCaloriesPer100,
                            suffix: 'kcal',
                            requiredMsg: l.requiredField)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _numField(
                            controller: _proteinController,
                            label: l.foodProteinPer100,
                            suffix: 'g',
                            requiredMsg: l.requiredField)),
                  ],
                ),
                const SizedBox(height: 10),

                // Fett & KH
                Row(
                  children: [
                    Expanded(
                        child: _numField(
                            controller: _fatController,
                            label: l.foodFatPer100,
                            suffix: 'g',
                            requiredMsg: l.requiredField)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _numField(
                            controller: _carbsController,
                            label: l.foodCarbsPer100,
                            suffix: 'g',
                            requiredMsg: l.requiredField)),
                  ],
                ),
                const SizedBox(height: 10),

                // Optional: Saturated Fat & Sugar
                Row(
                  children: [
                    Expanded(
                        child: TextFormField(
                          controller: _saturatedFatController,
                          decoration: InputDecoration(
                            labelText: l.nutrientSaturatedFat,
                            suffixText: 'g',
                            helperText: l.ofWhichFat,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        )),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextFormField(
                          controller: _sugarController,
                          decoration: InputDecoration(
                            labelText: l.nutrientSugar,
                            suffixText: 'g',
                            helperText: l.ofWhichCarbs,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        )),
                  ],
                ),
                const SizedBox(height: 10),

                // Optional: Fiber & Salt
                Row(
                  children: [
                    Expanded(
                        child: TextFormField(
                          controller: _fiberController,
                          decoration: InputDecoration(
                            labelText: l.nutrientFiber,
                            suffixText: 'g',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        )),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextFormField(
                          controller: _sodiumController,
                          decoration: InputDecoration(
                            labelText: l.nutrientSalt,
                            suffixText: 'g',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        )),
                  ],
                ),
                const SizedBox(height: 10),

                // Kategorie
                TextFormField(
                  controller: _categoryController,
                  decoration: InputDecoration(
                    labelText: l.foodCategory,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),

                // Marke
                TextFormField(
                  controller: _brandController,
                  decoration: InputDecoration(
                    labelText: l.foodBrand,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                // Portionsgrößen
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      l.foodPortionsTitle,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _portionRows.add((
                            name: TextEditingController(),
                            amount: TextEditingController(),
                          ));
                        });
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l.add),
                    ),
                  ],
                ),
                if (_portionRows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      l.foodPortionsEmpty,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                  )
                else
                  ...List.generate(_portionRows.length, (i) {
                    final row = _portionRows[i];
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: row.name,
                              decoration: const InputDecoration(
                                labelText: 'Bezeichnung',
                                hintText: 'z.B. 1 Scheibe',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: row.amount,
                              decoration: const InputDecoration(
                                labelText: 'Gramm',
                                suffixText: 'g',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                row.name.dispose();
                                row.amount.dispose();
                                _portionRows.removeAt(i);
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 4),

                // Öffentlich / Privat
                SwitchListTile(
                  value: _isPublic,
                  onChanged: (v) => setState(() => _isPublic = v),
                  title: Text(l.foodPublic),
                  subtitle: Text(
                    _isPublic ? l.foodPublicOn : l.foodPublicOff,
                  ),
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    _isPublic ? Icons.public : Icons.lock_outline,
                    color: _isPublic ? Colors.green : Colors.grey,
                  ),
                ),

                // Flüssigkeit
                SwitchListTile(
                  value: _isLiquid,
                  onChanged: (v) => setState(() => _isLiquid = v),
                  title: Text(l.foodIsLiquid),
                  subtitle: Text(l.foodIsLiquidHint),
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    _isLiquid ? Icons.water_drop : Icons.water_drop_outlined,
                    color: _isLiquid ? Colors.lightBlue : Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),

                // Tags (public tags, only for owner)
                Text(
                  'Tags',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                TagEditor(
                  tags: _editingTags,
                  onChanged: (tags) => setState(() => _editingTags = tags),
                  tagService: _tagService,
                  readOnly: false,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green, foregroundColor: Colors.white),
          child: Text(_isEdit ? l.save : l.add),
        ),
      ],
    );
  }
}
