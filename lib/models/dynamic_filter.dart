import 'package:cloud_firestore/cloud_firestore.dart';

enum FilterType {
  collection,
  attribute,
  query,
}

class QueryCondition {
  final String field;
  final String operator;
  final dynamic value;
  final String? logicalOperator;

  QueryCondition({
    required this.field,
    required this.operator,
    required this.value,
    this.logicalOperator,
  });

  factory QueryCondition.fromMap(Map<String, dynamic> map) {
    return QueryCondition(
      field: map['field'] ?? '',
      operator: map['operator'] ?? '==',
      value: map['value'],
      logicalOperator: map['logicalOperator'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'field': field,
      'operator': operator,
      'value': value,
      'logicalOperator': logicalOperator,
    };
  }
}

class DynamicFilter {
  final String id;
  final String name;
  final Map<String, String> displayName;
  final FilterType type;
  final bool isActive;
  final int order;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Collection-based filters
  final String? collection;

  // Attribute-based filters
  final String? attribute;
  final dynamic attributeValue;
  final String? operator;

  // Query-based filters
  final List<QueryCondition>? queryConditions;

  // Sorting and limiting
  final String? sortBy;
  final String? sortOrder;
  final int? limit;

  // UI customization
  final String? description;
  final String? icon;
  final String? color;

  DynamicFilter({
    required this.id,
    required this.name,
    required this.displayName,
    required this.type,
    required this.isActive,
    required this.order,
    this.createdAt,
    this.updatedAt,
    this.collection,
    this.attribute,
    this.attributeValue,
    this.operator,
    this.queryConditions,
    this.sortBy,
    this.sortOrder,
    this.limit,
    this.description,
    this.icon,
    this.color,
  });

  factory DynamicFilter.fromFirestore(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) throw Exception('Invalid filter data');

      // Parse display name safely
      Map<String, String> displayName = {};
      if (data['displayName'] is Map) {
        final displayNameMap = data['displayName'] as Map;
        displayNameMap.forEach((key, value) {
          if (key is String && value is String) {
            displayName[key] = value;
          }
        });
      }

      // Parse filter type
      FilterType filterType;
      switch (data['type']?.toString().toLowerCase()) {
        case 'collection':
          filterType = FilterType.collection;
          break;
        case 'query':
          filterType = FilterType.query;
          break;
        case 'attribute':
        default:
          filterType = FilterType.attribute;
          break;
      }

      // Parse query conditions for query-type filters
      List<QueryCondition>? queryConditions;
      if (data['queryConditions'] is List) {
        queryConditions = (data['queryConditions'] as List)
            .map((conditionData) {
              if (conditionData is Map<String, dynamic>) {
                return QueryCondition.fromMap(conditionData);
              }
              return null;
            })
            .where((condition) => condition != null)
            .cast<QueryCondition>()
            .toList();
      }

      return DynamicFilter(
        id: doc.id,
        name: data['name']?.toString() ?? '',
        displayName: displayName,
        type: filterType,
        isActive: data['isActive'] ?? false,
        order: data['order'] ?? 0,
        createdAt: data['createdAt'] is Timestamp
            ? (data['createdAt'] as Timestamp).toDate()
            : null,
        updatedAt: data['updatedAt'] is Timestamp
            ? (data['updatedAt'] as Timestamp).toDate()
            : null,
        collection: data['collection']?.toString(),
        attribute: data['attribute']?.toString(),
        attributeValue: data['attributeValue'],
        operator: data['operator']?.toString(),
        queryConditions: queryConditions,
        sortBy: data['sortBy']?.toString(),
        sortOrder: data['sortOrder']?.toString(),
        limit: data['limit'] is int ? data['limit'] : null,
        description: data['description']?.toString(),
        icon: data['icon']?.toString(),
        color: data['color']?.toString(),
      );
    } catch (e) {
      print('Error parsing DynamicFilter from Firestore: $e');
      throw Exception('Error parsing DynamicFilter from Firestore: $e');
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'displayName': displayName,
      'type': type.toString().split('.').last,
      'isActive': isActive,
      'order': order,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'collection': collection,
      'attribute': attribute,
      'attributeValue': attributeValue,
      'operator': operator,
      'queryConditions': queryConditions?.map((c) => c.toMap()).toList(),
      'sortBy': sortBy,
      'sortOrder': sortOrder,
      'limit': limit,
      'description': description,
      'icon': icon,
      'color': color,
    };
  }

  DynamicFilter copyWith({
    String? id,
    String? name,
    Map<String, String>? displayName,
    FilterType? type,
    bool? isActive,
    int? order,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? collection,
    String? attribute,
    dynamic attributeValue,
    String? operator,
    List<QueryCondition>? queryConditions,
    String? sortBy,
    String? sortOrder,
    int? limit,
    String? description,
    String? icon,
    String? color,
  }) {
    return DynamicFilter(
      id: id ?? this.id,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      type: type ?? this.type,
      isActive: isActive ?? this.isActive,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      collection: collection ?? this.collection,
      attribute: attribute ?? this.attribute,
      attributeValue: attributeValue ?? this.attributeValue,
      operator: operator ?? this.operator,
      queryConditions: queryConditions ?? this.queryConditions,
      sortBy: sortBy ?? this.sortBy,
      sortOrder: sortOrder ?? this.sortOrder,
      limit: limit ?? this.limit,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      color: color ?? this.color,
    );
  }

  @override
  String toString() {
    return 'DynamicFilter(id: $id, name: $name, type: $type, isActive: $isActive, order: $order)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DynamicFilter && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
