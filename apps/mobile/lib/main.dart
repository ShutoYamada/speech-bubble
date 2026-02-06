import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const defaultApiBaseUrl = 'http://10.0.2.2:3000'; // Android Emulator → host の定番

Future<String> fetchHello() async {
  // まずは固定でOK。環境変数切替は後で対応するのが安全。
  final uri = Uri.parse('$defaultApiBaseUrl/api/hello');
  final res = await http.get(uri);
  if (res.statusCode != 200) {
    throw Exception('API error: ${res.statusCode} ${res.body}');
  }
  final json = jsonDecode(res.body) as Map<String, dynamic>;
  return json['message'] as String;
}

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Flutter(Android) + Hono (compose)')),
        body: Center(
          child: FutureBuilder<String>(
            future: fetchHello(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const CircularProgressIndicator();
              }
              if (snapshot.hasError) return Text('Error: ${snapshot.error}');
              return Text(snapshot.data ?? '(no data)');
            },
          ),
        ),
      ),
    );
  }
}