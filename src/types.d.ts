declare namespace google {
  namespace accounts {
    namespace oauth2 {
      interface TokenClientConfig {
        client_id: string;
        scope: string;
        callback: (tokenResponse: TokenResponse) => void;
      }

      interface TokenClient {
        requestAccessToken(overrideConfig?: { prompt?: string }): void;
        callback: (tokenResponse: TokenResponse) => void;
      }

      interface TokenResponse {
        access_token: string;
        expires_in: number;
        hd: string;
        prompt: string;
        token_type: string;
        scope: string;
        state: string;
        error: string;
        error_description: string;
        error_uri: string;
      }

      function initTokenClient(config: TokenClientConfig): TokenClient;
    }
  }
}
