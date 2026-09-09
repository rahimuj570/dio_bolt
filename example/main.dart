import 'package:dio_bolt/dio_bolt.dart';

void main() async {
  // 1. Initialize DioBolt with readable status logging enabled
  final api = DioBolt(enableLogging: true);

  print('DioBolt initialized successfully with logging enabled!');
  print('Underlying Dio instance accessible: ${api.dio.runtimeType}');

  // 2. Universal non-throwing DioBoltResponse API
  // No try/catch needed for normal HTTP or network failures!
  final response = await api.get(
    'https://jsonplaceholder.typicode.com/posts/1',
  );

  if (response.isSuccess) {
    print('Application handler: Success (HTTP ${response.statusCode})');
  } else if (response.statusCode == 0) {
    print(
      'Application handler: Transport/network failure: ${response.message}',
    );
  } else {
    print(
      'Application handler: Server returned error HTTP ${response.statusCode}: ${response.message}',
    );
  }
}
