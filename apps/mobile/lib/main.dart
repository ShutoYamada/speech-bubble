
//const defaultApiBaseUrl = 'http://10.0.2.2:3000'; // Android Emulator → host の定番
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'package:path_provider/path_provider.dart';

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
      title: 'Speech Bubble',
      theme: ThemeData(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Speech Bubble'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const FaceBubblePage()),
                );
              },
              child: const Text('カメラから判定'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final picker = ImagePicker();
                final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
                if (video != null) {
                  if (context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => VideoBubblePage(videoPath: video.path),
                      ),
                    );
                  }
                }
              },
              child: const Text('動画読み込み'),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoBubblePage extends StatefulWidget {
  const VideoBubblePage({super.key, required this.videoPath});
  final String videoPath;

  @override
  State<VideoBubblePage> createState() => _VideoBubblePageState();
}

class _VideoBubblePageState extends State<VideoBubblePage> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _isAnalyzing = false;
  List<FaceData> _faceDataList = [];
  double _videoDurationSec = 0;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        setState(() {
          _initialized = true;
          _videoDurationSec = _controller.value.duration.inMilliseconds / 1000.0;
          _controller.setLooping(true);
        });
        _analyzeVideo();
      });
  }

  Future<void> _analyzeVideo() async {
    setState(() => _isAnalyzing = true);

    try {
      final detector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: true,
          performanceMode: FaceDetectorMode.accurate,
        ),
      );

      final tempDir = await getTemporaryDirectory();
      final intervalSec = 0.5; // 0.5秒ごとに解析 (処理負荷軽減のため)
      final count = (_videoDurationSec / intervalSec).ceil();

      List<FaceData> results = [];

      for (int i = 0; i < count; i++) {
        final timeMs = (i * intervalSec * 1000).toInt();
        
        final fileName = await vt.VideoThumbnail.thumbnailFile(
          video: widget.videoPath,
          thumbnailPath: tempDir.path,
          imageFormat: vt.ImageFormat.JPEG,
          timeMs: timeMs,
          quality: 50,
          maxWidth: 320, // 縮小して高速化 (scaleの代わり)
        );

        if (fileName != null) {
          final inputImage = InputImage.fromFilePath(fileName);
          final faces = await detector.processImage(inputImage);
          
          if (faces.isNotEmpty) {
            // 一番大きな顔を採用
            final face = faces.reduce((a, b) => 
              (a.boundingBox.width * a.boundingBox.height) > (b.boundingBox.width * b.boundingBox.height) ? a : b
            );
             // 画像サイズ（サムネイルのサイズ）を取得する必要があるが、
             // VideoThumbnailのscaleを指定しているので、元動画のアスペクト比とscaleから推測、
             // または decodeImage する手もあるが、ここでは簡略化のため正規化座標系(0.0-1.0)に変換して保持する形をとるか、
             // 単純に バウンディングボックスを保持して、表示時に調整する。
             // inputImage.metadata?.size は file からだと取れない場合があるため、
             // file path から画像サイズを読むのが確実だが、重くなる。
             // ここでは、FaceDetectorが返す座標は画像のピクセル座標。
             // サムネイル生成時のサイズが不明だとマッピングできない。
             // VideoThumbnailは maxWidth/maxHeight 指定がない場合、オリジナルサイズ(scale適用)になる。
             // _controller.value.size はオリジナルのサイズ。
             // scale: 0.5 なので、座標を 2倍すればオリジナル座標系に戻るはず。
            
            // 口の位置（中心）を計算
            Offset mouthPos = Offset(
              face.boundingBox.center.dx,
              face.boundingBox.bottom,
            );
            
            final leftMouth = face.landmarks[FaceLandmarkType.leftMouth]?.position;
            final rightMouth = face.landmarks[FaceLandmarkType.rightMouth]?.position;
            final bottomMouth = face.landmarks[FaceLandmarkType.bottomMouth]?.position;
            
            if (leftMouth != null && rightMouth != null && bottomMouth != null) {
              final x = (leftMouth.x + rightMouth.x + bottomMouth.x) / 3.0;
              final y = (leftMouth.y + rightMouth.y + bottomMouth.y) / 3.0;
              mouthPos = Offset(x, y);
            } else if (leftMouth != null && rightMouth != null) {
              final x = (leftMouth.x + rightMouth.x) / 2.0;
              final y = (leftMouth.y + rightMouth.y) / 2.0;
              mouthPos = Offset(x, y);
            }

            results.add(FaceData(
              timestampMs: timeMs,
              boundingBox: face.boundingBox,
              mouthPosition: mouthPos,
              mouthOpen: _estimateMouthOpen(face, face.boundingBox.height),
              scale: 0.5, // 解析に使った画像のスケール
            ));
          }
        }
      }
      
      detector.close();
      
      if (mounted) {
        setState(() {
          _faceDataList = results;
          _isAnalyzing = false;
          _controller.play();
        });
      }

    } catch (e) {
      debugPrint('Analysis error: $e');
      if (mounted) {
        setState(() => _isAnalyzing = false);
        _controller.play(); // エラーでも再生はする
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  FaceData? _getCurrentFaceData() {
    if (_faceDataList.isEmpty) return null;
    final currentMs = _controller.value.position.inMilliseconds;
    
    // 直近のデータを探す
    // 単純に距離が近いもの、あるいは 直前のもの
    FaceData? best;
    int minDiff = 999999;

    for (final data in _faceDataList) {
      final diff = (data.timestampMs - currentMs).abs();
      if (diff < minDiff) {
        minDiff = diff;
        best = data;
      }
    }
    
    // あまりに離れている場合（1秒以上）は表示しない
    if (minDiff > 1000) return null;
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final faceData = _getCurrentFaceData();

    return Scaffold(
      appBar: AppBar(title: const Text('Video Analysis')),
      body: Center(
        child: _initialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    VideoPlayer(_controller),
                    
                    if (_isAnalyzing)
                      Container(
                        color: Colors.black45,
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 16),
                              Text('動画解析中...', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ),

                    if (!_isAnalyzing && faceData != null)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // 動画の表示サイズ
                          final videoW = _controller.value.size.width;
                          final videoH = _controller.value.size.height;
                          
                          // 表示領域(Stack)のサイズ
                          final boxW = constraints.maxWidth;
                          final boxH = constraints.maxHeight;

                          // VideoPlayerはAspectRatioで囲まれているので、
                          // 基本的に boxW/boxH は videoW/videoH のアスペクト比と一致するはずだが、
                          // 念のため包含関係を計算
                          
                          // 解析時のスケールが 0.5 なので、座標を 1/0.5 = 2倍すると元動画座標になる
                          final scaleFix = 1.0 / faceData.scale;
                          final originalRect = Rect.fromLTRB(
                            faceData.boundingBox.left * scaleFix,
                            faceData.boundingBox.top * scaleFix,
                            faceData.boundingBox.right * scaleFix,
                            faceData.boundingBox.bottom * scaleFix,
                          );
                          
                          final originalMouth = Offset(
                            faceData.mouthPosition.dx * scaleFix,
                            faceData.mouthPosition.dy * scaleFix,
                          );

                          // 画面上の表示倍率
                          final displayScaleX = boxW / videoW;
                          final displayScaleY = boxH / videoH;

                          final mouthX = originalMouth.dx * displayScaleX;
                          final mouthY = originalMouth.dy * displayScaleY;

                          // 吹き出しの幅 (220) の半分を引いてセンタリング
                          final bubbleLeft = mouthX - 110;
                          
                          // 下基準で配置 (bottom = Stackの底からの距離)
                          // Stackの底とは boxH。mouthY は上からの距離。
                          // よって bottom = boxH - mouthY
                          final bubbleBottom = boxH - mouthY;

                          return Positioned(
                            left: bubbleLeft,
                            bottom: bubbleBottom,
                            child: _SyncedBubble(mouthOpen: faceData.mouthOpen),
                          );
                        },
                      ),

                    VideoProgressIndicator(_controller, allowScrubbing: true),
                  ],
                ),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

class FaceData {
  final int timestampMs;
  final Rect boundingBox;
  final Offset mouthPosition;
  final bool mouthOpen;
  final double scale;

  FaceData({
    required this.timestampMs,
    required this.boundingBox,
    required this.mouthPosition,
    required this.mouthOpen,
    required this.scale,
  });
}

class _SyncedBubble extends StatelessWidget {
  final bool mouthOpen;
  const _SyncedBubble({required this.mouthOpen});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubbleWithOptionsPainter(
        color: mouthOpen ? Colors.black87 : Colors.black54,
      ),
      child: Container(
        width: 220,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), // 下にシッポ分の余白
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              mouthOpen ? '（解析）喋ってる！' : '（解析）...',
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BubbleWithOptionsPainter extends CustomPainter {
  final Color color;
  _BubbleWithOptionsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height - 14),
      const Radius.circular(12),
    );
    canvas.drawRRect(r, paint);

    final tailPath = Path()
      ..moveTo(size.width / 2 - 10, size.height - 14)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width / 2 + 10, size.height - 14)
      ..close();
    canvas.drawPath(tailPath, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleWithOptionsPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

// 共通ロジックとして切り出し
bool _estimateMouthOpen(Face face, double faceH) {
  final mouthLeft = face.landmarks[FaceLandmarkType.leftMouth]?.position;
  final mouthRight = face.landmarks[FaceLandmarkType.rightMouth]?.position;
  final mouthBottom = face.landmarks[FaceLandmarkType.bottomMouth]?.position;

  if (mouthLeft == null || mouthRight == null || mouthBottom == null) {
    return false;
  }

  final mouthWidth =
      (mouthRight.x - mouthLeft.x).abs().clamp(1.0, double.infinity);
  final mouthOpenValue =
      (mouthBottom.y - min(mouthLeft.y, mouthRight.y)).abs();

  final ratio = mouthOpenValue / mouthWidth;
  return ratio > 0.30;
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
            child: Stack(
              children: [
                Align(
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
                Positioned(
                  top: 10,
                  left: 10,
                  child: FloatingActionButton.small(
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
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

// _estimateMouthOpen はトップレベル関数または共通ユーティリティに移動済みのため、ここでは削除するか、そちらを利用するように変更しても良いが、
// 既存コードを壊さないために一旦そのまま残すか、共通関数を呼ぶように変更しても良い。
// 今回はトップレベルに定義したので、クラス内のメソッド定義は削除し、呼び出し元を変更する。
// しかしCustomPainter内から呼んでいるので、CustomPainter内での定義を削除し、トップレベル関数を参照するようにする。
// （Dartでは同名の関数があると近いスコープが優先されるが、クラスメソッドとして定義しなければトップレベルが呼ばれる）


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
