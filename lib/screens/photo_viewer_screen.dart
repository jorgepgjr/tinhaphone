import 'package:flutter/material.dart';
import 'dart:io';
import '../models/photo.dart';
import '../services/db_service.dart';

class PhotoViewerScreen extends StatefulWidget {
  final List<Photo> photos;
  final int initialIndex;

  const PhotoViewerScreen({
    Key? key,
    required this.photos,
    required this.initialIndex,
  }) : super(key: key);

  @override
  _PhotoViewerScreenState createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late PageController _pageController;
  late List<Photo> _photos;
  final DbService _dbService = DbService();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _photos = List.from(widget.photos);
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _deleteCurrentPhoto() async {
    if (_photos.isEmpty) return;
    
    final index = _pageController.page?.round() ?? 0;
    final photo = _photos[index];
    
    setState(() {
      _photos.removeAt(index);
    });
    
    await _dbService.deletePhoto(photo.id);
    
    final scaffoldMessenger = _scaffoldMessengerKey.currentState!;
    scaffoldMessenger.clearSnackBars();
    
    bool isUndone = false;
    
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: const Text('Foto excluída'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () async {
            isUndone = true;
            await _dbService.savePhoto(photo);
            if (mounted) {
              setState(() {
                _photos.insert(index, photo);
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_pageController.hasClients) {
                  _pageController.jumpToPage(index);
                }
              });
            }
          },
        ),
      ),
    ).closed.then((reason) async {
      if (!isUndone) {
        final file = File(photo.localPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    });

    if (_photos.isEmpty) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _photos.isEmpty
          ? const Center(
              child: Text(
                'Nenhuma foto',
                style: TextStyle(color: Colors.white),
              ),
            )
          : PageView.builder(
              controller: _pageController,
              itemCount: _photos.length,
              itemBuilder: (context, index) {
                final photo = _photos[index];
                return InteractiveViewer(
                  child: Center(
                    child: Image.file(
                      File(photo.localPath),
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: _photos.isEmpty
          ? null
          : BottomAppBar(
              color: Colors.black,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.white, size: 28),
                    onPressed: _deleteCurrentPhoto,
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
