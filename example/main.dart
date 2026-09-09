import 'package:dio_bolt/dio_bolt.dart';

void main() async {
  // 1. Initialize DioBolt
  final api = DioBolt();

  print('DioBolt initialized successfully!');
  print('Underlying Dio instance accessible: ${api.dio.runtimeType}');

  // 2. Universal non-throwing DioBoltResponse API
  // No try/catch needed for normal HTTP or network failures!
  final response = await api.get('https://jsonplaceholder.typicode.com/posts/1');

  if (response.isSuccess) {
    print('Request succeeded (HTTP ${response.statusCode})');
    print('Response payload: ${response.responseData}');
  } else if (response.statusCode == 0) {
    print('Transport/network failure: ${response.message}');
  } else {
    print('Server returned error HTTP ${response.statusCode}: ${response.message}');
    print('Error payload: ${response.responseData}');
  }
}