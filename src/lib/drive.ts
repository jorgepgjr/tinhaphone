const CLIENT_ID = import.meta.env.VITE_GOOGLE_CLIENT_ID;
const SCOPES = 'https://www.googleapis.com/auth/drive.file';

let tokenClient: google.accounts.oauth2.TokenClient | null = null;
let accessToken: string | null = null;

export function initGoogleDrive() {
  if (!CLIENT_ID) {
    console.warn('VITE_GOOGLE_CLIENT_ID is not set. Google Drive sync will not work.');
    return;
  }

  if (window.google && window.google.accounts) {
    tokenClient = window.google.accounts.oauth2.initTokenClient({
      client_id: CLIENT_ID,
      scope: SCOPES,
      callback: (tokenResponse) => {
        if (tokenResponse && tokenResponse.access_token) {
          accessToken = tokenResponse.access_token;
        }
      },
    });
  }
}

export async function getAccessToken(): Promise<string> {
  if (accessToken) return accessToken;
  
  return new Promise((resolve, reject) => {
    if (!tokenClient) {
      reject(new Error('Google Identity Services not initialized. Check CLIENT_ID.'));
      return;
    }
    
    tokenClient.callback = (resp) => {
      if (resp.error !== undefined) {
        reject(resp);
      }
      accessToken = resp.access_token;
      resolve(resp.access_token);
    };
    
    tokenClient.requestAccessToken({ prompt: 'consent' });
  });
}

export async function loginToDrive(): Promise<string> {
  return getAccessToken();
}

export function hasToken(): boolean {
  return !!accessToken;
}

export async function uploadToDrive(blob: Blob, filename: string): Promise<string> {
  const token = await getAccessToken();
  
  const metadata = {
    name: filename,
    mimeType: blob.type,
    // Optionally specify a folder ID here: parents: ['folder_id']
  };

  const form = new FormData();
  form.append('metadata', new Blob([JSON.stringify(metadata)], { type: 'application/json' }));
  form.append('file', blob);

  const response = await fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
    },
    body: form,
  });

  if (!response.ok) {
    throw new Error(`Upload failed: ${response.statusText}`);
  }

  const data = await response.json();
  return data.id;
}
