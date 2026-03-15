import React, { useRef, useState, useEffect } from 'react';
import { X } from 'lucide-react';

interface CameraViewProps {
  onCapture: (blob: Blob) => void;
  onClose: () => void;
}

export function CameraView({ onCapture, onClose }: CameraViewProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [stream, setStream] = useState<MediaStream | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let activeStream: MediaStream | null = null;
    
    async function startCamera() {
      try {
        // Try environment camera first
        activeStream = await navigator.mediaDevices.getUserMedia({ 
          video: { facingMode: 'environment' } 
        });
      } catch (err) {
        console.warn("Environment camera failed, trying default video", err);
        try {
          // Fallback to any available camera
          activeStream = await navigator.mediaDevices.getUserMedia({ video: true });
        } catch (fallbackErr) {
          setError('Não foi possível acessar a câmera. Verifique as permissões do navegador.');
          return;
        }
      }
      
      setStream(activeStream);
      if (videoRef.current && activeStream) {
        videoRef.current.srcObject = activeStream;
        videoRef.current.play().catch(e => console.error("Video play failed:", e));
      }
    }
    
    startCamera();

    return () => {
      if (activeStream) {
        activeStream.getTracks().forEach(track => track.stop());
      }
    };
  }, []);

  const takePhoto = () => {
    if (!videoRef.current) return;
    
    const canvas = document.createElement('canvas');
    canvas.width = videoRef.current.videoWidth;
    canvas.height = videoRef.current.videoHeight;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    
    ctx.drawImage(videoRef.current, 0, 0);
    canvas.toBlob((blob) => {
      if (blob) {
        onCapture(blob);
      }
    }, 'image/jpeg', 0.9);
  };

  return (
    <div className="fixed inset-0 bg-black z-50 flex flex-col">
      <div className="flex justify-between items-center p-4 text-white">
        <h2 className="text-lg font-medium">Câmera</h2>
        <button onClick={onClose} className="p-2 rounded-full bg-white/10 hover:bg-white/20">
          <X size={24} />
        </button>
      </div>
      
      <div className="flex-1 relative bg-black flex items-center justify-center">
        {error ? (
          <div className="text-white text-center p-4">{error}</div>
        ) : (
          <video 
            ref={videoRef} 
            autoPlay 
            playsInline 
            muted
            className="w-full h-full object-cover"
          />
        )}
      </div>
      
      <div className="p-6 pb-10 flex justify-center items-center bg-black">
        <button 
          onClick={takePhoto}
          disabled={!!error}
          className="w-20 h-20 rounded-full border-4 border-white flex items-center justify-center bg-white/20 hover:bg-white/40 transition-colors disabled:opacity-50"
        >
          <div className="w-16 h-16 rounded-full bg-white"></div>
        </button>
      </div>
    </div>
  );
}
