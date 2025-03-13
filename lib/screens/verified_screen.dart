import 'dart:io';
import 'package:flutter/material.dart';

class ImagePreviewScreen extends StatelessWidget {
  final String imagePath;

  const ImagePreviewScreen({Key? key, required this.imagePath}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Image Preview')),
      body: Center(
        child: imagePath.isNotEmpty
            ? Image.file(File(imagePath)) // Display the saved image
            : const Text("❌ No image available"),
      ),
    );
  }
}
