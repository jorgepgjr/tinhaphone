import { openDB, DBSchema, IDBPDatabase } from 'idb';
import { v4 as uuidv4 } from 'uuid';

export type SyncStatus = 'pending' | 'syncing' | 'synced' | 'error';

export interface Photo {
  id: string;
  blob: Blob;
  timestamp: number;
  status: SyncStatus;
  driveFileId?: string;
}

interface PhotoDB extends DBSchema {
  photos: {
    key: string;
    value: Photo;
    indexes: { 'by-status': string };
  };
}

let dbPromise: Promise<IDBPDatabase<PhotoDB>>;

export async function getDB() {
  if (!dbPromise) {
    dbPromise = openDB<PhotoDB>('photo-vault-db', 1, {
      upgrade(db) {
        const store = db.createObjectStore('photos', { keyPath: 'id' });
        store.createIndex('by-status', 'status');
      },
    });
  }
  return dbPromise;
}

export async function savePhoto(blob: Blob): Promise<Photo> {
  const db = await getDB();
  const photo: Photo = {
    id: uuidv4(),
    blob,
    timestamp: Date.now(),
    status: 'pending',
  };
  await db.put('photos', photo);
  return photo;
}

export async function getPhotos(): Promise<Photo[]> {
  const db = await getDB();
  return db.getAllFromIndex('photos', 'by-status');
}

export async function updatePhotoStatus(id: string, status: SyncStatus, driveFileId?: string) {
  const db = await getDB();
  const photo = await db.get('photos', id);
  if (photo) {
    photo.status = status;
    if (driveFileId) photo.driveFileId = driveFileId;
    await db.put('photos', photo);
  }
}

export async function deletePhoto(id: string) {
  const db = await getDB();
  await db.delete('photos', id);
}

export async function clearSyncedPhotos() {
  const db = await getDB();
  const tx = db.transaction('photos', 'readwrite');
  const index = tx.store.index('by-status');
  let cursor = await index.openCursor('synced');
  
  while (cursor) {
    await cursor.delete();
    cursor = await cursor.continue();
  }
  await tx.done;
}
