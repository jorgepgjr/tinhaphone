import 'package:flutter_test/flutter_test.dart';
import 'package:tinhaphone/models/photo.dart';

void main() {
  test('preserva o identificador da foto enviada ao Prisma', () {
    final photo = Photo(
      id: 'local-1',
      localPath: '/tmp/foto.jpg',
      timestamp: 123,
      status: SyncStatus.synced,
      prismaPhotoId: 42,
    );

    final restored = Photo.fromMap(photo.toMap());
    expect(restored.prismaPhotoId, 42);
    expect(restored.status, SyncStatus.synced);
  });
}
