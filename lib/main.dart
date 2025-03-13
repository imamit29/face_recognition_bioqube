import 'package:face_recognition/face_recognitionApp.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(FaceRecognitionApp(cameras: cameras));
}