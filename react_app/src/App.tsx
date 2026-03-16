import React, { useState, useEffect } from 'react';
import { Camera, Cloud, CloudOff, CloudUpload, Trash2, RefreshCw, AlertCircle, CheckCircle2, X, ExternalLink } from 'lucide-react';
import { CameraView } from './components/CameraView';
import { getPhotos, savePhoto, updatePhotoStatus, deletePhoto, clearSyncedPhotos, Photo } from './lib/db';
import { initGoogleDrive, uploadToDrive, loginToDrive, hasToken } from './lib/drive';

export default function App() {
  const [photos, setPhotos] = useState<Photo[]>([]);
  const [showCamera, setShowCamera] = useState(false);
  const [autoDelete, setAutoDelete] = useState(false);
  const [isSyncing, setIsSyncing] = useState(false);
  const [clientIdConfigured, setClientIdConfigured] = useState(true);
  const [isConnected, setIsConnected] = useState(false);
  const [showSetupModal, setShowSetupModal] = useState(false);

  useEffect(() => {
    loadPhotos();
    
    // Check if Google Client ID is configured
    if (!import.meta.env.VITE_GOOGLE_CLIENT_ID) {
      setClientIdConfigured(false);
    } else {
      // Load Google Identity Services script dynamically if not present
      if (!document.querySelector('script[src="https://accounts.google.com/gsi/client"]')) {
        const script = document.createElement('script');
        script.src = "https://accounts.google.com/gsi/client";
        script.async = true;
        script.defer = true;
        script.onload = () => {
          initGoogleDrive();
          setIsConnected(hasToken());
        };
        document.head.appendChild(script);
      } else {
        initGoogleDrive();
        setIsConnected(hasToken());
      }
    }
  }, []);

  const loadPhotos = async () => {
    const loaded = await getPhotos();
    // Sort by timestamp descending
    setPhotos(loaded.sort((a, b) => b.timestamp - a.timestamp));
  };

  const handleConnectDrive = async () => {
    if (!clientIdConfigured) {
      setShowSetupModal(true);
      return;
    }

    try {
      await loginToDrive();
      setIsConnected(true);
    } catch (error) {
      console.error("Failed to connect to Google Drive", error);
      alert("Falha ao conectar ao Google Drive. Verifique as permissões.");
    }
  };

  const handleCapture = async (blob: Blob) => {
    await savePhoto(blob);
    setShowCamera(false);
    loadPhotos();
  };

  const syncPhoto = async (photo: Photo) => {
    if (!clientIdConfigured) {
      setShowSetupModal(true);
      return;
    }

    try {
      await updatePhotoStatus(photo.id, 'syncing');
      loadPhotos();
      
      const filename = `vault_${new Date(photo.timestamp).toISOString().replace(/[:.]/g, '-')}.jpg`;
      const driveId = await uploadToDrive(photo.blob, filename);
      
      setIsConnected(true); // If upload succeeds, we are definitely connected
      
      if (autoDelete) {
        await deletePhoto(photo.id);
      } else {
        await updatePhotoStatus(photo.id, 'synced', driveId);
      }
    } catch (error) {
      console.error("Sync error:", error);
      await updatePhotoStatus(photo.id, 'error');
    } finally {
      loadPhotos();
    }
  };

  const syncAllPending = async () => {
    if (isSyncing) return;
    setIsSyncing(true);
    
    const pendingPhotos = photos.filter(p => p.status === 'pending' || p.status === 'error');
    for (const photo of pendingPhotos) {
      await syncPhoto(photo);
    }
    
    setIsSyncing(false);
  };

  const handleClearSynced = async () => {
    if (window.confirm('Tem certeza que deseja apagar todas as fotos sincronizadas do dispositivo?')) {
      await clearSyncedPhotos();
      loadPhotos();
    }
  };

  const handleDelete = async (id: string) => {
    if (window.confirm('Apagar esta foto permanentemente?')) {
      await deletePhoto(id);
      loadPhotos();
    }
  };

  return (
    <div className="min-h-screen bg-neutral-50 text-neutral-900 pb-24">
      {/* Header */}
      <header className="bg-white shadow-sm sticky top-0 z-10">
        <div className="max-w-3xl mx-auto px-4 py-4 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
          <h1 className="text-xl font-semibold flex items-center gap-2">
            <Cloud className="text-indigo-600" />
            Cofre Sync
          </h1>
          <div className="flex flex-wrap items-center gap-4">
            {!isConnected ? (
              <button 
                onClick={handleConnectDrive}
                className="text-sm font-medium bg-blue-600 text-white px-3 py-1.5 rounded-lg hover:bg-blue-700 transition-colors flex items-center gap-2"
              >
                <Cloud size={16} />
                Conectar Drive
              </button>
            ) : (
              <span className="text-sm font-medium text-emerald-600 flex items-center gap-1 bg-emerald-50 px-3 py-1.5 rounded-lg">
                <CheckCircle2 size={16} />
                Drive Conectado
              </span>
            )}
            <label className="flex items-center gap-2 text-sm text-neutral-600 cursor-pointer">
              <input 
                type="checkbox" 
                checked={autoDelete} 
                onChange={(e) => setAutoDelete(e.target.checked)}
                className="rounded text-indigo-600 focus:ring-indigo-500"
              />
              Auto-delete
            </label>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-3xl mx-auto p-4">
        {/* Actions Bar */}
        <div className="flex justify-between items-center mb-6">
          <div className="text-sm text-neutral-500">
            {photos.length} foto{photos.length !== 1 ? 's' : ''} local
          </div>
          <div className="flex gap-2">
            <button 
              onClick={handleClearSynced}
              disabled={!photos.some(p => p.status === 'synced')}
              className="px-3 py-1.5 text-sm font-medium text-red-600 bg-red-50 rounded-lg hover:bg-red-100 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              Limpar Sincronizados
            </button>
            <button 
              onClick={syncAllPending}
              disabled={isSyncing || !photos.some(p => p.status === 'pending' || p.status === 'error')}
              className="px-3 py-1.5 text-sm font-medium text-white bg-indigo-600 rounded-lg hover:bg-indigo-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors flex items-center gap-2"
            >
              {isSyncing ? <RefreshCw size={16} className="animate-spin" /> : <CloudUpload size={16} />}
              Sincronizar
            </button>
          </div>
        </div>

        {/* Gallery Grid */}
        {photos.length === 0 ? (
          <div className="text-center py-20 text-neutral-400">
            <Camera size={48} className="mx-auto mb-4 opacity-20" />
            <p>Nenhuma foto no cofre.</p>
            <p className="text-sm">Toque no botão abaixo para capturar.</p>
          </div>
        ) : (
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4">
            {photos.map(photo => (
              <PhotoCard 
                key={photo.id} 
                photo={photo} 
                onSync={() => syncPhoto(photo)}
                onDelete={() => handleDelete(photo.id)}
              />
            ))}
          </div>
        )}
      </main>

      {/* FAB */}
      <button 
        onClick={() => setShowCamera(true)}
        className="fixed bottom-6 right-6 w-14 h-14 bg-indigo-600 text-white rounded-full shadow-lg flex items-center justify-center hover:bg-indigo-700 hover:scale-105 transition-all active:scale-95 z-40"
      >
        <Camera size={24} />
      </button>

      {/* Camera Overlay */}
      {showCamera && (
        <CameraView 
          onCapture={handleCapture} 
          onClose={() => setShowCamera(false)} 
        />
      )}

      {/* Setup Modal */}
      {showSetupModal && (
        <div className="fixed inset-0 bg-black/60 z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-md w-full p-6 shadow-xl relative">
            <button 
              onClick={() => setShowSetupModal(false)}
              className="absolute top-4 right-4 text-neutral-400 hover:text-neutral-600"
            >
              <X size={24} />
            </button>
            
            <div className="flex items-center gap-3 text-amber-600 mb-4">
              <AlertCircle size={28} />
              <h2 className="text-xl font-semibold text-neutral-900">Configuração Necessária</h2>
            </div>
            
            <div className="space-y-4 text-neutral-600 text-sm">
              <p>
                Para que o botão de login funcione, o Google exige que este aplicativo tenha uma "Identidade" (Client ID). Sem isso, o Google bloqueia a tentativa de login por segurança.
              </p>
              
              <div className="bg-neutral-50 p-4 rounded-lg border border-neutral-200">
                <h3 className="font-semibold text-neutral-900 mb-2">Como configurar em 3 passos:</h3>
                <ol className="list-decimal list-inside space-y-2">
                  <li>Acesse o <a href="https://console.cloud.google.com/" target="_blank" rel="noreferrer" className="text-indigo-600 hover:underline inline-flex items-center gap-1">Google Cloud Console <ExternalLink size={12}/></a></li>
                  <li>Crie credenciais do tipo <strong>ID do cliente OAuth</strong> (Aplicação Web).</li>
                  <li>Adicione a URL deste app nas <strong>Origens JavaScript autorizadas</strong>.</li>
                </ol>
              </div>
              
              <p>
                Após gerar o Client ID, adicione-o no painel de <strong>Secrets</strong> (Configurações) ou no arquivo <code>.env</code> como <code>VITE_GOOGLE_CLIENT_ID</code>.
              </p>
            </div>
            
            <button 
              onClick={() => setShowSetupModal(false)}
              className="mt-6 w-full py-2.5 bg-neutral-900 text-white rounded-lg font-medium hover:bg-neutral-800 transition-colors"
            >
              Entendi
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

function PhotoCard({ photo, onSync, onDelete }: { photo: Photo, onSync: () => void, onDelete: () => void }) {
  const [url, setUrl] = useState<string>('');

  useEffect(() => {
    const objectUrl = URL.createObjectURL(photo.blob);
    setUrl(objectUrl);
    return () => URL.revokeObjectURL(objectUrl);
  }, [photo.blob]);

  const statusConfig = {
    pending: { icon: <CloudOff size={14} />, color: 'bg-neutral-500', text: 'Pendente' },
    syncing: { icon: <RefreshCw size={14} className="animate-spin" />, color: 'bg-blue-500', text: 'Sincronizando' },
    synced: { icon: <Cloud size={14} />, color: 'bg-emerald-500', text: 'Sincronizado' },
    error: { icon: <AlertCircle size={14} />, color: 'bg-red-500', text: 'Erro' },
  };

  const config = statusConfig[photo.status];

  return (
    <div className="relative group rounded-xl overflow-hidden bg-neutral-200 aspect-square shadow-sm">
      {url && <img src={url} alt="Vault item" className="w-full h-full object-cover" />}
      
      {/* Status Badge */}
      <div className={`absolute top-2 left-2 px-2 py-1 rounded-md text-xs font-medium text-white flex items-center gap-1 shadow-sm backdrop-blur-sm ${config.color}/90`}>
        {config.icon}
        <span className="hidden sm:inline">{config.text}</span>
      </div>

      {/* Actions Overlay */}
      <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center gap-3">
        {(photo.status === 'pending' || photo.status === 'error') && (
          <button 
            onClick={onSync}
            className="p-2 bg-white text-indigo-600 rounded-full hover:scale-110 transition-transform shadow-sm"
            title="Tentar Sincronizar"
          >
            <CloudUpload size={18} />
          </button>
        )}
        <button 
          onClick={onDelete}
          className="p-2 bg-white text-red-600 rounded-full hover:scale-110 transition-transform shadow-sm"
          title="Apagar"
        >
          <Trash2 size={18} />
        </button>
      </div>
    </div>
  );
}
