// lib/models/filter_state.dart

class FilterState {
  String? selectedCategory;
  String? selectedSubcategory;
  String searchTerm = "";
  String sortOption = "date";
  bool showDeals = false;
  bool showFeatured = false;
  String? specialFilter;

  FilterState({
    this.selectedCategory,
    this.selectedSubcategory,
    this.searchTerm = "",
    this.sortOption = "date",
    this.showDeals = false,
    this.showFeatured = false,
    this.specialFilter,
  });

  // Optionally, you can add utility methods (copyWith, toString, etc.) here:
  // FilterState copyWith(...) { ... }
}
