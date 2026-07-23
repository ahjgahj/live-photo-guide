import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_photo_guide/pages/home_page.dart';
import 'package:live_photo_guide/pages/camera_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const LivePhotoGuideApp());
}

class LivePhotoGuideApp extends StatelessWidget {
  const LivePhotoGuideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '摄影大师',
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
      routes: {
        '/camera': (context) => const CameraPage(),
      },
    );
  }
}
