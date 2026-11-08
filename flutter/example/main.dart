import 'package:crossindie/crossindie.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('CrossIndie example')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            Text('Your app content…'),
            SizedBox(height: 24),
            // Each banner is an independent earning slot.
            CrossIndieBanner(
              appId: 'YOUR_APP_ID',
              category: CrossIndieCategory.mobileApp,
              format: CrossIndieFormat.card,
              packageName: 'com.example.myapp', // optional
            ),
          ],
        ),
        bottomNavigationBar: const SafeArea(
          child: CrossIndieBanner(
            appId: 'YOUR_APP_ID',
            format: CrossIndieFormat.mobile, // 320 x 50
          ),
        ),
      ),
    );
  }
}
