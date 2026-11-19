class OfficeConfig {
  const OfficeConfig({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  factory OfficeConfig.fromJson(Map<String, dynamic> json) {
    return OfficeConfig(
      name: json['name'] as String? ?? 'Office',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 200.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
      };
}

class Employee {
  const Employee({
    required this.id,
    required this.name,
    required this.department,
    required this.designation,
    required this.companyName,
    required this.companyTimezone,
    required this.office,
  });

  final String id;
  final String name;
  final String department;
  final String designation;
  final String companyName;
  final String companyTimezone;
  final OfficeConfig office;

  factory Employee.fromJson(Map<String, dynamic> json) {
    final company = json['company'] as Map<String, dynamic>? ?? const {};
    return Employee(
      id: json['id'] as String,
      name: json['name'] as String,
      department: json['department'] as String,
      designation: json['designation'] as String? ?? '',
      companyName: company['name'] as String? ?? 'Organization',
      companyTimezone: company['timezone'] as String? ?? 'Asia/Kolkata',
      office: OfficeConfig.fromJson(json['office'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'department': department,
        'designation': designation,
        'company': {
          'name': companyName,
          'timezone': companyTimezone,
        },
        'office': office.toJson(),
      };
}
