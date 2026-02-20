class Suggestion {
  final String id;         // Search result “objectID” (e.g. “products_abc123”)
  final String name;       // productName
  final double? price;     // optional: use for subtitle
  final String? imageUrl;

  Suggestion({
    required this.id,
    required this.name,
    this.price,
    this.imageUrl,
  });
}
