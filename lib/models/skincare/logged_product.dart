/// Product state used by the unified skincare intelligence layer.
///
/// Keep this model free of provider-specific PHI. If a future white-label or
/// HIPAA-scoped backend stores this data remotely, encrypt notes and image
/// references at rest and avoid putting direct identifiers in free-text fields.
class LoggedProduct {
  final String id;
  final String name;
  final String brand;
  final ProductCategory category;
  final ProductStatus status;
  final List<String> keyIngredients;
  final List<String> concernsTargeted;
  final DateTime startDate;
  final DateTime? endDate;
  final String frequency;
  final String instructions;
  final String notes;
  final int? rating;
  final String? photoPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LoggedProduct({
    required this.id,
    required this.name,
    this.brand = '',
    this.category = ProductCategory.other,
    this.status = ProductStatus.active,
    this.keyIngredients = const [],
    this.concernsTargeted = const [],
    required this.startDate,
    this.endDate,
    this.frequency = '',
    this.instructions = '',
    this.notes = '',
    this.rating,
    this.photoPath,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LoggedProduct.empty({required String id, DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    return LoggedProduct(
      id: id,
      name: '',
      startDate: timestamp,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  factory LoggedProduct.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return LoggedProduct(
      id: _readString(json['id']),
      name: _readString(json['name']),
      brand: _readString(json['brand']),
      category: ProductCategoryX.fromJson(json['category']),
      status: ProductStatusX.fromJson(json['status']),
      keyIngredients: _readStringList(json['keyIngredients']),
      concernsTargeted: _readStringList(json['concernsTargeted']),
      startDate: _readDate(json['startDate']) ?? now,
      endDate: _readDate(json['endDate']),
      frequency: _readString(json['frequency']),
      instructions: _readString(json['instructions']),
      notes: _readString(json['notes']),
      rating: _readInt(json['rating']),
      photoPath: _readNullableString(json['photoPath']),
      createdAt: _readDate(json['createdAt']) ?? now,
      updatedAt: _readDate(json['updatedAt']) ?? now,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'brand': brand,
    'category': category.jsonValue,
    'status': status.jsonValue,
    'keyIngredients': keyIngredients,
    'concernsTargeted': concernsTargeted,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'frequency': frequency,
    'instructions': instructions,
    'notes': notes,
    'rating': rating,
    'photoPath': photoPath,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  LoggedProduct copyWith({
    String? id,
    String? name,
    String? brand,
    ProductCategory? category,
    ProductStatus? status,
    List<String>? keyIngredients,
    List<String>? concernsTargeted,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    String? frequency,
    String? instructions,
    String? notes,
    int? rating,
    bool clearRating = false,
    String? photoPath,
    bool clearPhotoPath = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LoggedProduct(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      category: category ?? this.category,
      status: status ?? this.status,
      keyIngredients: keyIngredients ?? this.keyIngredients,
      concernsTargeted: concernsTargeted ?? this.concernsTargeted,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : endDate ?? this.endDate,
      frequency: frequency ?? this.frequency,
      instructions: instructions ?? this.instructions,
      notes: notes ?? this.notes,
      rating: clearRating ? null : rating ?? this.rating,
      photoPath: clearPhotoPath ? null : photoPath ?? this.photoPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum ProductCategory {
  cleanser,
  toner,
  essence,
  serum,
  peptide,
  retinoid,
  exfoliant,
  moisturizer,
  sunscreen,
  mask,
  device,
  supplement,
  other,
}

extension ProductCategoryX on ProductCategory {
  String get jsonValue => name;

  static ProductCategory fromJson(Object? value) =>
      _enumFromName(ProductCategory.values, value, ProductCategory.other);
}

enum ProductStatus { active, paused, completed, discontinued, planned }

extension ProductStatusX on ProductStatus {
  String get jsonValue => name;

  static ProductStatus fromJson(Object? value) =>
      _enumFromName(ProductStatus.values, value, ProductStatus.active);
}

T _enumFromName<T extends Enum>(List<T> values, Object? value, T fallback) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return fallback;
  final normalized = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
  for (final candidate in values) {
    final candidateName = candidate.name.toLowerCase();
    if (candidateName == normalized) return candidate;
  }
  return fallback;
}

String _readString(Object? value) => value?.toString().trim() ?? '';

String? _readNullableString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _readDate(Object? value) {
  if (value is DateTime) return value;
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

List<String> _readStringList(Object? value) {
  if (value is! Iterable) return const [];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
