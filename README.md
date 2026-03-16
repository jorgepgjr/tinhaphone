# Tinhaphone - Flutter iOS App

Este é um aplicativo de Cofre de Fotos (Photo Vault) construído em Flutter, projetado exclusivamente para rodar no formato "Retrato" (Portrait) no iOS. Ele permite capturar fotos e sincronizá-las diretamente com o seu Google Drive.

---

## 🔒 Como configurar a Integração com o Google Drive

Para testar o Sync com o Google Drive, você precisa configurar um projeto no Google Cloud e adicionar as credenciais nativas no aplicativo. Siga os passos abaixo:

### Passo 1: Configurar o Google Cloud Console
1. Acesse o [Google Cloud Console](https://console.cloud.google.com).
2. Crie um novo projeto ou selecione um existente.
3. No menu lateral, vá em **APIs & Services > Library** (Biblioteca).
4. Pesquise por **Google Drive API** e clique em **Habilitar** (Enable).

### Passo 2: Configurar a Tela de Consentimento OAuth (OAuth consent screen)
1. Vá em **APIs & Services > OAuth consent screen**.
2. Escolha **External** (Externo) e clique em Create.
3. Preencha os campos obrigatórios básicos (Nome do App, Email de Suporte, Email de Desenvolvedor).
4. Na etapa **Escopos** (Scopes), clique em *Add or remove scopes* e adicione o escopo do Drive (geralmente `https://www.googleapis.com/auth/drive.file`).
5. Na etapa **Test Users** (Usuários de Teste), **você deve adicionar o seu próprio email do Google**. Se você não fizer isso, o Google bloqueará o login porque o app ainda não está publicado.

### Passo 3: Criar Credenciais para iOS
1. Vá em **APIs & Services > Credentials** (Credenciais).
2. Clique em **Create Credentials > OAuth client ID**.
3. Selecione o tipo de aplicativo como **iOS**.
4. No campo **Bundle ID**, preencha com o Bundle ID do projeto. Por padrão, ele foi criado como: `com.example.tinhaphone`. (Se mudar o bundle identifier no Xcode, mude aqui também).
5. Clique em Criar.
6. Uma janela aparecerá mostrando seu **Client ID** e o **iOS URL scheme** (que é o seu Client ID invertido).
   - O *Client ID* será algo como: `123456789-abcdefg.apps.googleusercontent.com`
   - O *iOS URL scheme* será algo como: `com.googleusercontent.apps.123456789-abcdefg`

### Passo 4: Configurar o Aplicativo (ios/Runner/Info.plist)
Abra o arquivo `ios/Runner/Info.plist` no seu editor ou no Xcode, e adicione os seguintes blocos logo "antes" do fechamento final `</dict>` no final do arquivo:

**1. Adicione o Client ID:**
```xml
<key>GIDClientID</key>
<string>COLE_SEU_CLIENT_ID_AQUI</string>
```

**2. Adicione o Esquema de URL (URL Scheme) para o login retornar para o App:**
```xml
<key>CFBundleURLTypes</key>
<array>
	<dict>
		<key>CFBundleTypeRole</key>
		<string>Editor</string>
		<key>CFBundleURLSchemes</key>
		<array>
			<string>COLE_SEU_IOS_URL_SCHEME_AQUI</string>
		</array>
	</dict>
</array>
```

### Passo 5: Teste no iOS!
1. Conecte o seu iPhone ou inicie o Simulador iOS.
2. No terminal, rode `flutter run -d ios`.
3. Clique em **Connect Drive** no app. Ele deverá abrir o pop-up de login do Google.
4. Faça o login com o seu email (o mesmo que você adicionou nos "Test Users" do Passo 2).
5. Tire uma foto e teste os botões de Upload para verificar se ela é enviada para o seu Drive!

---

### 🤖 E se eu quiser configurar para o Android?

A configuração para Android segue o mesmo fluxo no Google Cloud, mas difere em como as credenciais são cadastradas. Siga este mini-passo a passo:

#### 1. Gerar a assinatura de debug (SHA-1)
Para o Android, o Google identifica seu app pela sua chave de assinatura (SHA-1) combinada com o pacote (`com.example.tinhaphone`).
No seu terminal (Mac/Linux), rode o seguinte comando para pegar o SHA-1 de debug:
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```
*Copie o valor que aparecer na linha **`SHA1:`**.*

#### 2. Criar a Credencial OAuth para Android no Google Cloud
1. Vá no Google Cloud Console: **APIs & Services > Credentials**.
2. Clique em **Create Credentials > OAuth client ID**.
3. Selecione o tipo de aplicativo como **Android**.
4. No campo **Package name**, coloque o pacote do seu app: `com.example.tinhaphone`.
5. No campo **SHA-1 certificate fingerprint**, cole o valor `SHA1` que você pegou no passo 1.
6. Clique em **Create**.

#### 3. Criar a Credencial OAuth de Servidor (Web)
O Android precisa de um "Server Client ID" para conseguir acesso a permissões avançadas (como ler e gravar no Google Drive).
1. Volte em **Create Credentials > OAuth client ID**.
2. Dessa vez, escolha **Web application** (Aplicativo da Web).
3. Coloque um nome qualquer (ex: "Tinhaphone Web Gateway").
4. Deixe as URLs de redirecionamento em branco.
5. Clique em **Create**.
6. Copie o **Client ID** gerado. Ele deve ser parecido com o do iOS (`123456789-abcdefg.apps.googleusercontent.com`).

#### 4. Configurar no App
Diferente do iOS, o Android não precisa colar o ID do Android no Manifest, pois ele usa o SHA-1 que você acabou de gerar (Passo 2) silenciosamente.

No entanto, por conta do Google Drive, nós precisamos informar o Server Client ID (Passo 3) pro Login funcionar.
1. Abra o arquivo `lib/services/drive_service.dart`.
2. Logo no topo, procure pela variável: `static const String _serverClientId = 'COLE_SEU_WEB_CLIENT_ID_AQUI';`
3. Troque esse valor pelo Client ID que você copiou do Passo 3.

> **Aviso:** O Login do Google só funciona no emulador se ele tiver o **Google Play e o Google Play Services** instalados (na hora de criar o emulador no Android Studio, escolha um device com o ícone da Play Store ao lado).
