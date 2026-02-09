
//const defaultApiBaseUrl = 'http://10.0.2.2:3000'; // Android Emulator → host の定番
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

late final List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const FaceBubblePage(),
      theme: ThemeData(useMaterial3: true),
    );
  }
}

class FaceBubblePage extends StatefulWidget {
  const FaceBubblePage({super.key});

  @override
  State<FaceBubblePage> createState() => _FaceBubblePageState();
}

class _FaceBubblePageState extends State<FaceBubblePage> {
  CameraController? _camera;
  late final FaceDetector _detector;

  bool _isBusy = false;
  List<Face> _faces = [];
  Size? _imageSize; // 入力画像サイズ（回転前）
  int _rotationDegrees = 0;

  @override
  void initState() {
    super.initState();

    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: false,
        performanceMode: FaceDetectorMode.fast,
      ),
    );

    _initCamera();
  }

  Future<void> _initCamera() async {
    // 前面カメラ優先（無ければ0番）
    final front = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    final camera = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await camera.initialize();

    // 端末の向きに応じて回転が変わる。ひとまず portraitUp 前提に寄せる
    _rotationDegrees = _getRotationDegrees(front.sensorOrientation);

    await camera.startImageStream(_processCameraImage);

    setState(() => _camera = camera);
  }

  int _getRotationDegrees(int sensorOrientation) {
    // Emulator/端末でズレることがあるので、まずはこれで動くところまで
    // 必要に応じて later に調整
    return sensorOrientation; // 90/270 が多い
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy) return;
    _isBusy = true;

    try {
      final inputImage = _toInputImage(image);
      final faces = await _detector.processImage(inputImage);

      setState(() {
        _faces = faces;
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      });
    } catch (e) {
      debugPrint('MLKit error: $e');
    } finally {
      _isBusy = false;
    }
  }

  InputImage _toInputImage(CameraImage image) {
    if (Platform.isAndroid) {
      // Android: Convert to NV21 separately to fix "InputImageConverterError"
      // caused by padding (bytesPerRow > width) or plane overlap.
      //
      // NV21 format:
      // - Y plane: width * height
      // - UV plane: width * height / 2 (interleaved V, U)
      final width = image.width;
      final height = image.height;

      // Y Plane
      final yPlane = image.planes[0];
      final yStride = yPlane.bytesPerRow;
      final yBytes = yPlane.bytes;

      // U/V Planes
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];
      final uvStride = uPlane.bytesPerRow;
      final uvPixelStride = uPlane.bytesPerPixel ?? 2;
      final uBytes = uPlane.bytes;
      final vBytes = vPlane.bytes;

      final WriteBuffer buffer = WriteBuffer();

      // 1) Copy Y plane (removing padding)
      for (int row = 0; row < height; row++) {
        final srcOffset = row * yStride;
        buffer.putUint8List(yBytes.sublist(srcOffset, srcOffset + width));
      }

      // 2) Copy UV plane (interleaved)
      // NV21 expects V first, then U. (V, U, V, U...)
      // On Android Camera2 API, 'vPlane.bytes' often points to the V byte of the first pixel,
      // and checking pixelStride=2 means it is interleaved.
      // We copy row by row.
      final uvHeight = height ~/ 2;
      final uvWidth = width; // In bytes (for interleaved V-U, it matches width of Y row in bytes effectively)

      for (int row = 0; row < uvHeight; row++) {
        final srcOffset = row * uvStride;
        if (uvPixelStride == 2) {
          // Optimization: V plane usually contains V,U,V,U...
          // We can just copy the line from V plane?
          // We need width bytes.
          buffer.putUint8List(vBytes.sublist(srcOffset, srcOffset + uvWidth));
        } else {
          // Fallback: manually interleave if not interleaved (planar)
          // (Rare for standard Android camera, but for safety)
          for (int x = 0; x < width ~/ 2; x++) {
            // NV21: V, U
            final v = vBytes[srcOffset + x * uvPixelStride];
            final u = uBytes[srcOffset + x * uvPixelStride];
            buffer.putUint8(v);
            buffer.putUint8(u);
          }
        }
      }

      final bytes = buffer.done().buffer.asUint8List();

      final metadata = InputImageMetadata(
        size: Size(width.toDouble(), height.toDouble()),
        rotation: _rotationFromDegrees(_rotationDegrees),
        format: InputImageFormat.nv21, // Explicitly NV21
        bytesPerRow: width, // Now packed, so stride = width
      );

      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    } else {
      // iOS / Buffer concatenation fallback
      final WriteBuffer buffer = WriteBuffer();
      for (final plane in image.planes) {
        buffer.putUint8List(plane.bytes);
      }
      final bytes = buffer.done().buffer.asUint8List();

      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _rotationFromDegrees(_rotationDegrees),
        format: InputImageFormat.bgra8888, // iOS 'camera' default is often BGRA
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    }
  }

  InputImageRotation _rotationFromDegrees(int degrees) {
    switch (degrees % 360) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    _detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(camera),

          // 吹き出し表示（モック）
          if (_imageSize != null)
            CustomPaint(
              painter: _BubblePainter(
                faces: _faces,
                imageSize: _imageSize!,
                isFrontCamera: camera.description.lensDirection == CameraLensDirection.front,
              ),
            ),

          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'faces: ${_faces.length}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({
    required this.faces,
    required this.imageSize,
    required this.isFrontCamera,
  });

  final List<Face> faces;
  final Size imageSize;
  final bool isFrontCamera;

  @override
  void paint(Canvas canvas, Size size) {
    // カメラ映像（Preview）の表示サイズ size と、解析に渡した imageSize の座標系が違うので、
    // “ざっくり”スケール変換。ここは後で調整ポイント。
    final sx = size.width / imageSize.width;
    final sy = size.height / imageSize.height;

    for (final face in faces) {
      final rect = face.boundingBox;

      // 画面座標へ
      double left = rect.left * sx;
      double top = rect.top * sy;
      double right = rect.right * sx;
      double bottom = rect.bottom * sy;

      // 前面カメラは左右反転でそれっぽく合うことが多い
      if (isFrontCamera) {
        final newLeft = size.width - right;
        final newRight = size.width - left;
        left = newLeft;
        right = newRight;
      }

      final faceW = max(1.0, right - left);
      final faceH = max(1.0, bottom - top);

      final mouthOpen = _estimateMouthOpen(face, faceH);

      // 吹き出し位置：顔の上
      final bubbleX = left + faceW * 0.5;
      final bubbleY = top - 24;

      final text = mouthOpen
          ? '（モック）いま喋ってるっぽい'
          : '（モック）…';

      _drawBubble(canvas, Offset(bubbleX, bubbleY), text, active: mouthOpen);
    }
  }

bool _estimateMouthOpen(Face face, double faceH) {
  final mouthLeft = face.landmarks[FaceLandmarkType.leftMouth]?.position;
  final mouthRight = face.landmarks[FaceLandmarkType.rightMouth]?.position;
  final mouthBottom = face.landmarks[FaceLandmarkType.bottomMouth]?.position;

  if (mouthLeft == null || mouthRight == null || mouthBottom == null) {
    return false;
  }

  // 口の横幅
  final mouthWidth =
      (mouthRight.x - mouthLeft.x).abs().clamp(1.0, double.infinity);

  // 口の縦開きっぽさ（下にどれだけ下がっているか）
  final mouthOpenValue =
      (mouthBottom.y - min(mouthLeft.y, mouthRight.y)).abs();

  // 正規化（顔サイズ or 口幅）
  final ratio = mouthOpenValue / mouthWidth;

  // しきい値（要チューニング）
  return ratio > 0.30;
}

  void _drawBubble(Canvas canvas, Offset anchor, String text, {required bool active}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: 220);

    final padding = 10.0;
    final w = tp.width + padding * 2;
    final h = tp.height + padding * 2;

    final r = RRect.fromRectAndRadius(
      Rect.fromCenter(center: anchor.translate(0, -h / 2), width: w, height: h),
      const Radius.circular(14),
    );

    final paint = Paint()
      ..color = active ? Colors.black87 : Colors.black54;

    canvas.drawRRect(r, paint);

    // しっぽ
    final tail = Path()
      ..moveTo(anchor.dx, r.bottom)
      ..lineTo(anchor.dx - 10, r.bottom + 14)
      ..lineTo(anchor.dx + 10, r.bottom)
      ..close();
    canvas.drawPath(tail, paint);

    tp.paint(canvas, Offset(r.left + padding, r.top + padding));
  }

  @override
  bool shouldRepaint(covariant _BubblePainter oldDelegate) {
    return oldDelegate.faces != faces || oldDelegate.imageSize != imageSize;
  }
}
