# TinhaKids unificado — professor e família

Este repositório é a base do aplicativo único **TinhaKids**. O nome técnico do pacote Dart e o identificador normal Android/iOS continuam os do TinhaPhone para preservar suas integrações nativas. O projeto antigo `tinhakids` fica como referência, sem necessidade de manter dois apps.

## Uso atual

- Login único por e-mail/senha, com perfil definido pelo Prisma.
- Professor: câmera, turma selecionada pelo nome, fila por conta, compartilhamento, envio ao Prisma e cópia opcional no Google Drive.
- Familiar: publicações, portfólios e somente os alunos vinculados no Prisma.
- Coordenação e Marketing continuam no portal. E-mails não podem ser compartilhados entre perfis.
- A sessão usa armazenamento seguro; a senha não é persistida. Fotos e configurações antigas não são importadas, nem apagadas pelo código novo.

Com a API do Prisma atualizada e em execução:

```powershell
flutter pub get
flutter run -d ID-DO-DISPOSITIVO
```

No emulador Android a API é `http://10.0.2.2:8000`. Para celular físico, acrescente `--dart-define=API_URL=http://IP-DO-COMPUTADOR:8000`. Também é possível informar o endereço em **Servidor de testes** no login. Em produção, configure um servidor HTTPS.

```powershell
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug
flutter test integration_test/unified_app_test.dart -d ID-DO-EMULADOR --no-uninstall
```

No Windows, `android/gradlew.bat` configura automaticamente um diretório de sockets Java em `%USERPROFILE%\.gradle\socket-tmp`. Isso evita o erro `Unable to establish loopback connection` quando o Windows fornece um caminho temporário abreviado, como `GUILHE~1`. A configuração vale apenas durante a compilação e seus subprocessos; não exige alterar o Java ou as variáveis globais do computador. Esse wrapper é versionado para preservar a correção.

O teste integrado requer a API e contas de desenvolvimento existentes, cria duas fotos e usa o pacote Android separado `com.example.tinhaphone.integration`. Não execute seed sobre uma base que precise preservar. O compartilhamento é simulado no limite do plugin nesse teste; valide também o menu nativo manualmente.

**Atualizações com dados:** não desinstale o app nem use `flutter install`, que pode remover a versão anterior. Para um APK compilado, utilize `adb install -r caminho-do-apk`. Interrompa se houver erro de assinatura e faça backup antes de qualquer desinstalação.

As configurações de iPhone foram mantidas/preparadas, mas compilação, assinatura, Keychain e compartilhamento precisam de validação em um Mac com Xcode. O guia completo está em `../prisma/GUIA_DE_TESTES_E_FLUXOS.md`.

## Cópia das fotos no Google Drive (professor)

### Galeria do professor

Na área do professor, escolha a turma no cartão superior e use o botão **+** para fotografar ou importar várias imagens da galeria. O envio ao Prisma começa após a importação; falhas permanecem na fila e podem ser reenviadas. A grade mostra fotos locais e registros enviados da turma, agrupados por data. Pressione e segure uma miniatura para selecionar várias fotos e então mover, adicionar/remover tags ou excluir. Os filtros de data, status e tags ficam no ícone ao lado de **Fotos**. Fotos publicadas ou usadas em portfólios não podem ser movidas nem excluídas do servidor.

As tags são opcionais e pertencem à escola. Fotos pendentes guardam suas tags no banco local da conta e as enviam depois da confirmação do upload. A visualização remota usa URLs assinadas e miniaturas reduzidas; ao expirar a URL, atualize a galeria.

O envio ao Google Drive voltou como destino opcional, separado do envio obrigatório ao Prisma. O professor conecta sua própria conta Google nas configurações, escolhe uma pasta (ou mantém “Meu Drive”) e pode salvar uma foto pelo ícone do Drive no visualizador ou usar **Configurações > Salvar pendentes no Drive**. A opção **Sair** também fica em Configurações; o cabeçalho do professor mantém apenas a engrenagem. As fotos já enviadas ao Drive ficam marcadas e não são reenviadas. A família não vê nem usa essa integração.

Em **Configurações > Google Drive**, o professor também pode ativar a remoção automática da cópia privada do app. Por segurança, essa cópia só é removida depois que o arquivo estiver confirmado tanto no Drive quanto no Prisma; o original da galeria do celular nunca é apagado. A preferência e a pasta ficam separadas para cada conta do TinhaKids.

### Configuração do Google Cloud

O projeto precisa ter a Google Drive API habilitada e a tela de consentimento OAuth configurada. Se o app estiver em modo de teste, adicione os e-mails autorizados como usuários de teste. Para distribuição, configure os clientes OAuth nativos correspondentes aos identificadores Android e iOS deste app. As credenciais Android e o esquema iOS existentes foram preservados; não coloque credenciais privadas em documentação ou no repositório.

As seções históricas abaixo descrevem como a integração era preparada originalmente e podem ser usadas como referência para configurar o projeto Google Cloud.

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
