import 'package:flutter/material.dart';

class ScanAnimation extends StatelessWidget {
  final Animation<double> scanAnimation;

  const ScanAnimation({Key? key, required this.scanAnimation}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scanAnimation,
      builder: (context, child) {
        double focusSize = MediaQuery.of(context).size.width * 0.6; // Keep consistent size
        double focusTop = (MediaQuery.of(context).size.height / 2) - (focusSize / 2);
        double focusBottom = focusTop + focusSize;

        return Positioned(
          top: scanAnimation.value.clamp(focusTop, focusBottom - 10), // Keep inside focus box
          left: MediaQuery.of(context).size.width * 0.2, // Centered width
          right: MediaQuery.of(context).size.width * 0.2, // Centered width
          child: Container(
            height: 5,
            margin: EdgeInsets.symmetric(horizontal: 15),
            width: focusSize * 0.8, // Ensure it stays inside focus
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.blue, Colors.blueAccent]),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      },
    );
  }
}
