/// Model for food and meal template tags
class Tag {
  final String id;
  final String name;
  final String slug;

  const Tag({required this.id, required this.name, required this.slug});

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
    id: json['id'] as String,
    name: json['name'] as String,
    slug: json['slug'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'slug': slug,
  };

  /// Convert name to URL-friendly slug
  /// Example: "Very Tasty" → "very-tasty"
  static String toSlug(String name) =>
    name.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '-');

  @override
  String toString() => 'Tag(id: $id, name: $name, slug: $slug)';

  @override
  bool operator ==(Object other) =>
    identical(this, other) ||
    other is Tag &&
      runtimeType == other.runtimeType &&
      id == other.id &&
      slug == other.slug;

  @override
  int get hashCode => id.hashCode ^ slug.hashCode;
}
