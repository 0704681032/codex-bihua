class StrokePath {
  const StrokePath({
    required this.order,
    required this.svgPath,
    this.medianPoints = const <List<double>>[],
  });

  final int order;
  final String svgPath;
  final List<List<double>> medianPoints;

  factory StrokePath.fromJson(Map<String, dynamic> json) {
    return StrokePath(
      order: (json['order'] as num?)?.toInt() ?? 0,
      svgPath: (json['svgPath'] as String?)?.trim() ?? '',
      medianPoints: ((json['medianPoints'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<List<dynamic>>()
          .map(
            (point) => point
                .map((value) => (value as num?)?.toDouble() ?? 0)
                .toList(growable: false),
          )
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'order': order,
      'svgPath': svgPath,
      'medianPoints': medianPoints,
    };
  }
}
