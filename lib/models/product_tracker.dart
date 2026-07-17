class TrackedProduct {
  final String id;
  final String name;
  final String brand;
  final String keyIngredients; // e.g. "Niacinamide, Hyaluronic Acid"
  final DateTime startDate;
  final DateTime? endDate; // null if still using
  final String notes;
  final int rating;
  final String? photoPath;

  TrackedProduct({
    required this.id,
    required this.name,
    required this.brand,
    required this.keyIngredients,
    required this.startDate,
    this.endDate,
    this.notes = '',
    this.rating = 0,
    this.photoPath,
  });

  TrackedProduct copyWith({
    String? id,
    String? name,
    String? brand,
    String? keyIngredients,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    String? notes,
    int? rating,
    String? photoPath,
    bool clearPhoto = false,
  }) {
    return TrackedProduct(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      keyIngredients: keyIngredients ?? this.keyIngredients,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      notes: notes ?? this.notes,
      rating: rating ?? this.rating,
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'brand': brand,
    'keyIngredients': keyIngredients,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'notes': notes,
    'rating': rating,
    'photoPath': photoPath,
  };

  factory TrackedProduct.fromJson(Map<String, dynamic> json) => TrackedProduct(
    id: json['id'],
    name: json['name'],
    brand: json['brand'],
    keyIngredients: json['keyIngredients'],
    startDate: DateTime.parse(json['startDate']),
    endDate: json['endDate'] != null ? DateTime.parse(json['endDate']) : null,
    notes: json['notes'] ?? '',
    rating: json['rating'] as int? ?? 0,
    photoPath: json['photoPath'] as String?,
  );
}
