import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class CameraScreen extends StatefulWidget {
  final Function(XFile) onCapture;

  const CameraScreen({Key? key, required this.onCapture}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInit = false;
  bool _isTakingPicture = false;
  int _selectedCameraIndex = 0;

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
      print('Erro na Câmera: $e');
    }
  }

  Future<void> _startCamera(CameraDescription camera) async {
    final previousController = _controller;

    final newController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    await previousController?.dispose();

    if (mounted) {
      setState(() {
        _controller = newController;
      });
    }

    try {
      await newController.initialize();
      if (mounted) {
        setState(() {
          _isInit = true;
        });
      }
    } catch (e) {
      print('Erro ao inicializar câmera: $e');
    }
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
      widget.onCapture(photo);
      // Give visual feedback and reset taking picture state smoothly
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto tirada com sucesso!'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      print('Erro ao tirar foto: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isTakingPicture = false;
        });
      }
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
          Positioned.fill(child: CameraPreview(_controller!)),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Placeholder to balance the row
                  const SizedBox(width: 50, height: 50),
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
