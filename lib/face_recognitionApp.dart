import 'package:face_recognition/screens/camera_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

/// Root widget of the application.
class FaceRecognitionApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const FaceRecognitionApp({Key? key, required this.cameras}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CameraScreen(cameras: cameras),
    );
  }
}


