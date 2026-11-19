import '../../../../core/dio_api_service/interface/api_service_interface.dart';
import '../../domain/models/employee.dart';

class DashboardRemoteDataSource {
  DashboardRemoteDataSource(this._api);

  final IApiService _api;

  Future<Employee> fetchEmployee() async {
    final response = await _api.get('/employee/me');
    return Employee.fromJson(response.data as Map<String, dynamic>);
  }
}
