import 'package:dio_bolt/dio_bolt.dart';

class User {
  final int id;
  final String name;

  User({required this.id, required this.name});

  factory User.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return User(
      id: map['id'] as int,
      name: map['name'] as String,
    );
  }
}

void main() async {
  // 1. Initialize DioBolt
  final api = DioBolt();

  print('DioBolt initialized successfully!');
  print('Underlying Dio instance accessible: ${api.dio.runtimeType}');

  // 2. Level 1: Raw / Flexible API returning DioBoltResponse
  // final response = await api.get('/users');
  // if (response.isSuccess) {
  //   print(response.responseData);
  // }

  // 3. Level 2: Typed convenience API returning Future<T>
  // final user = await api.getAs<User>(
  //   '/users/1',
  //   fromJson: User.fromJson,
  // );
  // print('User name: ${user.name}');
}