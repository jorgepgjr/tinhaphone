import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/photo.dart';
import '../services/db_service.dart';
import 'photo_viewer_screen.dart';

Future<String> _applyWatermarkToImage(Map<String, dynamic> params) async {
  final String imagePath = params['imagePath'];
  final Uint8List watermarkBytes = params['watermarkBytes'];

  final originalBytes = await File(imagePath).readAsBytes();
  final originalImage = img.decodeImage(originalBytes);
  if (originalImage == null) return imagePath;

  final watermarkImage = img.decodeImage(watermarkBytes);
  if (watermarkImage == null) return imagePath;

  final watermarkWidth = (originalImage.width * 0.25).toInt();
  final resizedWatermark = img.copyResize(
    watermarkImage,
    width: watermarkWidth,
  );

  final paddingX = (originalImage.width * 0.05).toInt();
  final paddingY = (originalImage.height * 0.05).toInt();
  final dstX = originalImage.width - resizedWatermark.width - paddingX;
  final dstY = originalImage.height - resizedWatermark.height - paddingY;

  img.compositeImage(originalImage, resizedWatermark, dstX: dstX, dstY: dstY);

  final resultBytes = img.encodeJpg(originalImage);
  await File(imagePath).writeAsBytes(resultBytes);

  return imagePath;
}

class CameraScreen extends StatefulWidget {
  final Future<Photo> Function(XFile) onCapture;

  const CameraScreen({super.key, required this.onCapture});

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInit = false;
  bool _isTakingPicture = false;
  bool _showBlink = false;
  int _selectedCameraIndex = 0;
  Photo? _lastPhoto;

  double _currentZoomLevel = 1.0;
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _baseZoomLevel = 1.0;
  double _activeZoomMode = 1.0;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception('Nenhuma câmera encontrada');
      }

      // Try looking for the back camera first
      _selectedCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (_selectedCameraIndex == -1) {
        _selectedCameraIndex = 0;
      }

      await _startCamera(_cameras[_selectedCameraIndex]);
    } catch (e) {
      debugPrint('Erro na Câmera: $e');
    }
  }

  Future<void> _startCamera(CameraDescription camera) async {
    final previousController = _controller;

    final newController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await previousController?.dispose();

    if (mounted) {
      setState(() {
        _controller = newController;
      });
    }

    try {
      await newController.initialize();

      _maxAvailableZoom = await newController.getMaxZoomLevel();
      _minAvailableZoom = await newController.getMinZoomLevel();

      _currentZoomLevel = 1.0.clamp(_minAvailableZoom, _maxAvailableZoom);

      try {
        await newController.setZoomLevel(_currentZoomLevel);
        await newController.setFlashMode(FlashMode.off);
      } catch (e) {
        debugPrint('Erro ao definir config inicial (zoom/flash): $e');
      }

      if (mounted) {
        setState(() {
          _isInit = true;
        });
      }
    } catch (e) {
      debugPrint('Erro ao inicializar câmera: $e');
    }
  }

  Future<void> _setZoom(double zoom) async {
    if (_controller == null || !_isInit) return;
    final clampedZoom = zoom.clamp(_minAvailableZoom, _maxAvailableZoom);
    if (clampedZoom != _currentZoomLevel) {
      setState(() {
        _currentZoomLevel = clampedZoom;
      });
      await _controller!.setZoomLevel(clampedZoom);
    }
  }

  Future<void> _handleZoomButton(double mode) async {
    if (_controller == null || !_isInit) return;

    setState(() {
      _activeZoomMode = mode;
    });

    if (mode == 0.5) {
      if (_minAvailableZoom <= 0.6) {
        _setZoom(mode);
      } else {
        // Switch to the ultra wide camera (usually the last back camera in the list)
        final ultraWideIndex = _cameras.lastIndexWhere((c) => c.lensDirection == CameraLensDirection.back);
        if (ultraWideIndex != -1 && ultraWideIndex != _selectedCameraIndex) {
          setState(() {
            _isInit = false;
            _selectedCameraIndex = ultraWideIndex;
          });
          await _startCamera(_cameras[_selectedCameraIndex]);
        }
      }
    } else if (mode == 1.0) {
      final firstBackIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      if (_selectedCameraIndex != firstBackIndex && firstBackIndex != -1) {
        setState(() {
          _isInit = false;
          _selectedCameraIndex = firstBackIndex;
        });
        await _startCamera(_cameras[_selectedCameraIndex]);
      } else {
        _setZoom(1.0);
      }
    } else {
      _setZoom(mode);
    }
  }

  Widget _buildZoomButton(double mode, String label) {
    final bool isSelected = (_activeZoomMode - mode).abs() < 0.1;
    return GestureDetector(
      onTap: () => _handleZoomButton(mode),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber : Colors.black54,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  void _switchCamera() {
    if (_cameras.length < 2 || _isTakingPicture) return;

    setState(() {
      _isInit = false;
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    });

    _startCamera(_cameras[_selectedCameraIndex]);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isTakingPicture) {
      return;
    }

    setState(() {
      _isTakingPicture = true;
    });

    try {
      final XFile photo = await _controller!.takePicture();

      if (mounted) {
        setState(() {
          _showBlink = true;
          _isTakingPicture = false; // Unblock UI immediately
        });
        Future.delayed(const Duration(milliseconds: 10), () {
          if (mounted) {
            setState(() {
              _showBlink = false;
            });
          }
        });
      }

      // Process watermark and save to DB without blocking the UI
      _processPhotoInBackground(photo);
    } catch (e) {
      debugPrint('Erro ao tirar foto: $e');
      if (mounted) {
        setState(() {
          _isTakingPicture = false;
        });
      }
    }
  }

  Future<void> _processPhotoInBackground(XFile photo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final applyWatermark = prefs.getBool('apply_watermark') ?? true;

      if (applyWatermark) {
        try {
          final ByteData watermarkData = await rootBundle.load(
            'lib/assets/guri.png',
          );
          final Uint8List watermarkBytes = watermarkData.buffer.asUint8List();

          await compute(_applyWatermarkToImage, {
            'imagePath': photo.path,
            'watermarkBytes': watermarkBytes,
          });
        } catch (e) {
          debugPrint('Erro ao aplicar marca d\'água: $e');
        }
      }

      final photoObj = await widget.onCapture(photo);

      if (mounted) {
        setState(() {
          _lastPhoto = photoObj;
        });
      }
    } catch (e) {
      debugPrint('Erro no processamento da foto em background: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInit || _controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onScaleStart: (details) {
                _baseZoomLevel = _currentZoomLevel;
              },
              onScaleUpdate: (details) async {
                if (_controller == null || !_isInit) return;

                final zoomLevel = (_baseZoomLevel * details.scale).clamp(
                  _minAvailableZoom,
                  _maxAvailableZoom,
                );

                if (zoomLevel != _currentZoomLevel) {
                  setState(() {
                    _currentZoomLevel = zoomLevel;
                    if (zoomLevel >= 2.0) _activeZoomMode = 2.0;
                    else if (zoomLevel <= 0.6) _activeZoomMode = 0.5;
                    else _activeZoomMode = 1.0;
                  });
                  await _controller!.setZoomLevel(_currentZoomLevel);
                }
              },
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1 / _controller!.value.aspectRatio,
                  child: CameraPreview(_controller!),
                ),
              ),
            ),
          ),
          if (_showBlink)
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.8)),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          if (_maxAvailableZoom > _minAvailableZoom)
            Positioned(
              bottom: 120,
              left: 20,
              right: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_cameras.isNotEmpty &&
                      _cameras[_selectedCameraIndex].lensDirection !=
                          CameraLensDirection.front)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildZoomButton(0.5, '.5x'),
                        const SizedBox(width: 16),
                        _buildZoomButton(1.0, '1x'),
                        if (_maxAvailableZoom >= 2.0) ...[
                          const SizedBox(width: 16),
                          _buildZoomButton(2.0, '2x'),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _lastPhoto != null
                      ? GestureDetector(
                          onTap: () async {
                            final dbService = DbService();
                            final photos = await dbService.getPhotos();
                            final initialIndex = photos.indexWhere(
                              (p) => p.id == _lastPhoto!.id,
                            );

                            if (!mounted) return;

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PhotoViewerScreen(
                                  photos: photos,
                                  initialIndex: initialIndex != -1
                                      ? initialIndex
                                      : 0,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.rectangle,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white, width: 2),
                              image: DecorationImage(
                                image: FileImage(File(_lastPhoto!.localPath)),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox(width: 50, height: 50),
                  GestureDetector(
                    onTap: _takePicture,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Center(
                        child: Container(
                          width: _isTakingPicture ? 60 : 70,
                          height: _isTakingPicture ? 60 : 70,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_cameras.length > 1)
                    IconButton(
                      icon: const Icon(
                        Icons.flip_camera_ios,
                        color: Colors.white,
                        size: 36,
                      ),
                      onPressed: _switchCamera,
                    )
                  else
                    const SizedBox(width: 50, height: 50),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
