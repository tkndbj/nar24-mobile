import 'package:cloud_firestore/cloud_firestore.dart';

class NextStep {
  final String stepId;
  final Map<String, List<String>>? conditions;

  NextStep({
    required this.stepId,
    this.conditions,
  });

  factory NextStep.fromMap(Map<String, dynamic> data) => NextStep(
        stepId: data['stepId'] as String,
        conditions: (data['conditions'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, List<String>.from(v as List))),
      );
}

class FlowStep {
  final String id;
  final String stepType;
  final String title;
  final bool required;
  final List<NextStep> nextSteps;

  FlowStep({
    required this.id,
    required this.stepType,
    required this.title,
    required this.required,
    required this.nextSteps,
  });

  factory FlowStep.fromMap(Map<String, dynamic> data) => FlowStep(
        id: data['id'] as String,
        stepType: data['stepType'] as String,
        title: data['title'] as String,
        required: data['required'] as bool? ?? false,
        nextSteps: (data['nextSteps'] as List<dynamic>? ?? [])
            .map((e) => NextStep.fromMap(e as Map<String, dynamic>))
            .toList(),
      );
}

class ProductListingFlow {
  final String id;
  final String name;
  final String description;
  final String version;
  final bool isActive;
  final bool isDefault;
  final String startStepId;
  final Map<String, FlowStep> steps;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String createdBy;
  final int usageCount;
  final double completionRate;

  ProductListingFlow({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.isActive,
    required this.isDefault,
    required this.startStepId,
    required this.steps,
    this.createdAt,
    this.updatedAt,
    required this.createdBy,
    required this.usageCount,
    required this.completionRate,
  });

  factory ProductListingFlow.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final rawSteps = data['steps'] as Map<String, dynamic>;

    return ProductListingFlow(
      id: doc.id,
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      version: data['version'] as String? ?? '1.0.0',
      isActive: data['isActive'] as bool? ?? false,
      isDefault: data['isDefault'] as bool? ?? false,
      startStepId: data['startStepId'] as String,
      steps: rawSteps.map(
        (k, v) => MapEntry(k, FlowStep.fromMap(v as Map<String, dynamic>)),
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy'] as String? ?? '',
      usageCount: data['usageCount'] as int? ?? 0,
      completionRate: (data['completionRate'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
