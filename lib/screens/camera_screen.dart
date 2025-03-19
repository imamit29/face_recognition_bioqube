import 'dart:io';
import 'package:face_recognition/components/scan_animation.dart';
import 'package:face_recognition/screens/verified_screen.dart';
import 'package:face_recognition/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

/// Main screen for camera and face detection.
class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>  with SingleTickerProviderStateMixin {
  CameraController? controller;
  final FaceDetector faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableClassification: true,
      enableContours: false,  // Reduce false positives
      minFaceSize: 0.3,       // Ignore very small faces
    ),
  );

  int step = 0;
  Timer? verificationTimer;
  bool isVerified = false;
  int timeLeft = 20;
  bool isProcessing = false;
  int frameSkipCounter = 0;
  double scanPosition = 100;
  late AnimationController _animationController;
  late Animation<double> _scanAnimation;
  String lastInstruction = ""; // Track last spoken instruction
  int frameInterval = 3;
  bool scanComplete = false;
  late TtsService _ttsService;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _ttsService = TtsService();
    _initializeAnimation();
    _ttsService.speak(getInstruction());
  }


  /// Requests necessary permissions for camera access.
  Future<void> _requestPermissions() async {
    PermissionStatus cameraStatus = await Permission.camera.status;

    if (cameraStatus.isPermanentlyDenied) {
      openAppSettings();
      return;
    }

    if (cameraStatus.isDenied) {
      Map<Permission, PermissionStatus> statuses = await [Permission.camera].request();

      if (statuses[Permission.camera]!.isGranted) {
        _initializeCamera();
      } else {
        openAppSettings();
      }
    } else {
      _initializeCamera();
    }
  }


  /// Initializes scanning animation.
  _initializeAnimation(){
    // Create animation controller for scanning effect
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    )..repeat(reverse: true);

    // Move scan line from top to bottom
    _scanAnimation = Tween<double>(begin: 20, end: 450).animate(_animationController);

  }


  /// Initializes the camera and starts image processing.
  Future<void> _initializeCamera() async {
    try {
      final frontCamera = widget.cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
      );

      controller = CameraController(
        frontCamera,
        ResolutionPreset.high,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller!.initialize();
      if (!mounted) return;
      setState(() {});

      controller!.startImageStream((CameraImage image) {
        if (!isProcessing && frameSkipCounter % 3 == 0) {
          isProcessing = true;
          _processImage(image).then((_) => isProcessing = false);
        }
        frameSkipCounter++;
      });

      _startVerificationTimer();
    } catch (e) {
      print("❌ Camera initialization error: $e");
      Future.delayed(Duration(seconds: 2), () => _initializeCamera()); // Retry after delay
    }
  }



  /// Starts a countdown timer for verification.
  void _startVerificationTimer() {
    verificationTimer?.cancel();  // Ensure no duplicate timers
    timeLeft = 20;

    verificationTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (timeLeft <= 0) {
        _resetVerification();
        timer.cancel();  // Stop the timer when time runs out
      } else {
        if (mounted) {  // Ensure widget is still in the tree
          setState(() => timeLeft--);
        }
      }
    });
  }


  /// Resets verification progress.
  void _resetVerification() {
    verificationTimer?.cancel();
    setState(() {
      step = 0;
      isVerified = false;
      timeLeft = 20;
    });
    _startVerificationTimer();
  }


  /// Processes camera images for face recognition.
  Future<void> _processImage(CameraImage image) async {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.values[controller!.description.sensorOrientation ~/ 90],
          format: InputImageFormat.yuv420,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final faces = await faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        _ttsService.speak("No face detected. Please adjust your position.");
        return;
      }

      if (faces.length > 1) {
        _ttsService.speak("Multiple faces detected. Please ensure only one face is visible.");
        return;
      }

      // Find the largest face (ignore false positives)
      Face? largestFace = faces.reduce((curr, next) =>
      curr.boundingBox.height * curr.boundingBox.width >
          next.boundingBox.height * next.boundingBox.width
          ? curr
          : next);

      if (largestFace == null) {
        _ttsService.speak("No face detected. Please adjust your position.");
        return;
      }

      Face face = largestFace;

      // Ensure face remains within a valid range before applying checks
      if (face.boundingBox.height < 30 || face.boundingBox.width < 30) {
        _ttsService.speak("Face not fully visible. Move slightly up.");
        return;
      }

      // Eye openness detection
      bool eyesOpen = face.leftEyeOpenProbability != null &&
          face.rightEyeOpenProbability != null &&
          face.leftEyeOpenProbability! > 0.5 &&
          face.rightEyeOpenProbability! > 0.5;

      // Blink detection
      bool blinkDetected = face.leftEyeOpenProbability != null &&
          face.rightEyeOpenProbability != null &&
          face.leftEyeOpenProbability! < 0.2 &&
          face.rightEyeOpenProbability! < 0.2;

      // Smile detection
      bool smileDetected = face.smilingProbability != null && face.smilingProbability! > 0.5;

      // Yaw (left/right movement) detection
      bool moveLeft = face.headEulerAngleY != null && face.headEulerAngleY! > 10;
      bool moveRight = face.headEulerAngleY != null && face.headEulerAngleY! < -10;

      // Pitch (up/down movement) detection
      bool moveUp = face.headEulerAngleX != null && face.headEulerAngleX! > 10;
      bool moveDown = face.headEulerAngleX != null && face.headEulerAngleX! < -5; // Reduced threshold

      // Roll (tilt movement) detection
      bool headTiltDetected = face.headEulerAngleZ != null && face.headEulerAngleZ!.abs() > 10;

      _checkLivelinessSequence(blinkDetected, smileDetected, eyesOpen, moveLeft, moveRight, moveUp, moveDown, headTiltDetected);
    } catch (e) {
      print("❌ Error processing image: $e");
    }
  }

  /// Checks if the face actions match the required sequence.
  void _checkLivelinessSequence(bool blink, bool smile, bool eyesOpen, bool left, bool right, bool up, bool down, bool tilt) {
    Map<int, bool> stepActions = {
      0: eyesOpen,
      1: blink,
      2: smile,
      3: left,
      4: right,
      5: up,
      6: down,
      7: tilt,
    };

    if (stepActions[step] == true) {
      setState(() => step++);
      _ttsService.speak(getInstruction());

      if (step == stepActions.length) {
        isVerified = true;
        verificationTimer?.cancel();
        _startCountdownToCapture();
      }
    }
  }

  /// Returns the current instruction based on the step.
  String getInstruction() {
    switch (step) {
      case 0:
        return "Keep your eyes open";
      case 1:
        return "Blink your eyes";
      case 2:
        return "Smile";
      case 3:
        return "Look left";
      case 4:
        return "Look right";
      case 5:
        return "Move your head up";
      case 6:
        return "Move your head down slightly";
      case 7:
        return "Tilt your head to the side";
      default:
        return "Verification Complete, Please wait while capturing image";
    }
  }


  void _startCountdownToCapture() {
    timeLeft = 3;
    Timer.periodic(Duration(seconds: 1), (timer) {
      if (timeLeft <= 1) {
        timer.cancel();
        _captureAndSaveImage();
      } else {
        setState(() => timeLeft--);
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Face Recognition')),
        body: SizedBox(
          height: double.infinity,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand, // Makes the stack cover the entire screen
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: EdgeInsets.all(20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStepIndicator(0, "1"),
                        _buildStepLine(0),
                        _buildStepIndicator(1, "2"),
                        _buildStepLine(1),
                        _buildStepIndicator(2, "3"),
                        _buildStepLine(2),
                        _buildStepIndicator(3, "4"),
                        _buildStepLine(3),
                        _buildStepIndicator(4, "5"),
                        _buildStepLine(4),
                        _buildStepIndicator(5, "6"),
                        _buildStepLine(5),
                        _buildStepIndicator(6, "7"),
                        _buildStepLine(6),
                        _buildStepIndicator(7, "8"),
                      ],
                    ),),
                  Container(
                    margin: EdgeInsets.only(left: 20, bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Face Registration", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black)),
                        Text("Please ${isVerified ? "wait capturing in: $timeLeft sec ⏳" : getInstruction()}", style: TextStyle(fontSize: 16, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Expanded(child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (controller != null && controller!.value.isInitialized)
                        Transform.scale(
                          scaleX: -1,
                          child: CameraPreview(controller!),
                        ),
                      Align(
                        alignment: Alignment.topCenter,
                        child: Column(
                          children: [
                            SizedBox(height: 40),

                          ],
                        ),
                      ),
                    ],
                  ),)
                ],
              ),


              // 🔹 Camera Focus Icon (Centered)
              Center(
                child: Image.asset(
                  'assets/ic_focus.png', // 📸 Focus icon
                  width: MediaQuery.of(context).size.width * 0.7, // Responsive width
                  height: MediaQuery.of(context).size.width * 0.7, // Keep it square
                ),
              ),


              // 🔹 Scanning Animation (Inside Focus Box)
              ScanAnimation(scanAnimation: _scanAnimation),


              isVerified?Container():Positioned(
                bottom: 10,
                left: 10,
                child: Card(
                  color: timeLeft > 3 ? Colors.white : Colors.red,
                  child: Padding(padding: EdgeInsets.all(10),
                    child: Column(
                      children: [
                        SizedBox(width: 80,),
                        Text(
                          "⏳ $timeLeft sec",
                          style: TextStyle(fontSize: 16, color: timeLeft > 3 ? Colors.red : Colors.white, fontWeight:  FontWeight.bold),
                        ),
                      ],
                    ),),
                ),
              )
            ],
          ),
        )
    );
  }

  Future<void> _captureAndSaveImage() async {
    if (controller == null || !controller!.value.isInitialized) return;
    try {
      final XFile imageFile = await controller!.takePicture();
      final Directory? directory = await getExternalStorageDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String path = '${directory!.path}/verified_image_$timestamp.jpg';

      final File newImage = File(path);
      await newImage.writeAsBytes(await imageFile.readAsBytes());

      print("✅ Image saved at: $path");

      Navigator.pop(context);

      // Navigate to the preview screen
      Navigator.push( context, MaterialPageRoute( builder: (context) => ImagePreviewScreen(imagePath: path)), ).then((value) => setState(() {
        // _resetVerification();
      }));

    } catch (e) {
      print("❌ Error saving image: $e");
    }
  }

  // ✅ Step Indicator (Filled, Outlined, or Done)
  Widget _buildStepIndicator(int stepIndex, String label) {
    bool isCompleted = step > stepIndex;
    bool isActive = step == stepIndex;
    bool isLastStep = stepIndex == 7 && step == 8; // ✅ Step 4 Completion Check

    return Container(
      width: 25,
      height: 25,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCompleted || isLastStep ? Colors.blue : (isActive ? Colors.blue : Colors.grey.shade300),
        border: Border.all(color: isCompleted || isLastStep ? Colors.blue : Colors.grey.shade400, width: 2),
      ),
      child: isCompleted || isLastStep
          ? Icon(Icons.check, color: Colors.white, size: 10) // ✅ Show Checkmark Icon
          : Text(
        label,
        style: TextStyle(
          color: isActive ? Colors.white : Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // 📏 Stepper Line (Between Steps)
  Widget _buildStepLine(int stepIndex) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.all(5),
        height: 4,
        color: step > stepIndex ? Colors.blue : Colors.grey.shade300, // ✅ Change color when completed
      ),
    );
  }


  @override
  void dispose() {
    // Stop the verification timer
    verificationTimer?.cancel();

    // Stop the camera image stream (if running)
    if (controller != null && controller!.value.isStreamingImages) {
      controller!.stopImageStream(); // ✅ Stops camera stream
    }

    // Dispose of the camera controller
    controller?.dispose();

    // Close the face detector
    faceDetector.close();

    // Dispose of the animation controller
    _animationController.dispose();

    // Dispose of the flutterTts
    _ttsService.dispose();
    super.dispose();
  }


}