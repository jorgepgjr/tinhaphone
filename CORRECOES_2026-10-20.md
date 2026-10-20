# Correções e dados de teste — 20/10/2026

- Login: aceita IP local sem protocolo, preserva o último servidor após login bem-sucedido e distingue erro de conexão de tempo esgotado. O erro exato relatado na troca de servidor não foi reproduzido neste ambiente.
- Professor: tocar em + sem turma abre a seleção; escolher uma turma continua automaticamente para câmera/importação. Carregamento, falha e ausência de turmas exibem orientação.
- Família: painel de publicação com cartão do professor, informações rotuladas, ícones, legenda, rolagem e botão de fechar.

## Fotos fictícias

Geradas pela ferramenta integrada de imagens, sem usar fotos de crianças reais como referência. Cada prompt pediu fotografia escolar natural, personagem inteiramente fictício, roupa cotidiana, luz suave, enquadramento horizontal e ausência de textos/marcas. Cenas:

1. Criança fictícia de 5 anos pintando em uma mesa escolar.
2. Criança fictícia de 6 anos lendo um livro ilustrado na sala de aula.
3. Criança fictícia de 5 anos montando blocos coloridos na escola.
4. Criança fictícia de 5 anos cuidando de uma pequena planta na escola.

Arquivos definitivos no projeto:

- `../prisma/backend/uploads/1/test-professora-artes-20261020.png`
- `../prisma/backend/uploads/1/test-professora-leitura-20261020.png`
- `../prisma/backend/uploads/1/test-familia-blocos-20261020.png`
- `../prisma/backend/uploads/1/test-familia-jardim-20261020.png`

A carga incremental `../prisma/backend/add_test_photos.py` criou as fotos 35–38, todas na escola Girassol, turma Grupo 2 e atribuídas à professora. Apenas as fotos 37–38 possuem publicações para FILHO TESTE, vinculado ao pai de teste. As duas primeiras permanecem apenas na galeria escolar. A base não foi recriada. O script pode ser executado novamente sem duplicar esses registros.

## Validação

- `flutter test`: 53 testes passaram, incluindo o toque em + sem turma selecionada, normalização de endereços, isolamento de contas e os fluxos familiares.
- `flutter analyze --no-fatal-infos`: concluiu sem erros ou warnings, com 79 apontamentos informativos de lint no projeto.
- Snapshot do painel de informações gerado e inspecionado em `test/goldens/family-post-details.png`; teste visual passou.
- API real: login das duas contas, quatro fotos na galeria do professor, duas novas publicações para o pai e imagens assinadas retornando HTTP 200. Outro familiar não recebeu as novas publicações.
- A falha `Unable to establish loopback connection` foi resolvida configurando especificamente `jdk.net.unixdomain.tmpdir`. Alterar apenas `java.io.tmpdir` não resolvia, pois o Java usa outro diretório para os sockets locais. O wrapper Windows agora define um caminho completo em `%USERPROFILE%\.gradle\socket-tmp` e propaga a propriedade aos subprocessos Java. As variáveis permanecem locais à compilação; nenhuma configuração global de Java foi alterada. `android/gradlew.bat` passou a ser versionado para preservar o ajuste.
- `flutter build apk --debug`: compilação concluída com a correção automática, sem preparação manual do terminal.
- APK normal atualizado no emulador com `adb install -r` (sucesso), preservando os dados locais; aplicativo aberto pelo identificador `com.example.tinhaphone`.
- `flutter test integration_test/login_gallery_regression_test.dart -d emulator-5554 --no-uninstall`: passou no Android 13, com API e SQLite reais, cobrindo login com servidor editado, botão +, seleção de turma e informações familiares. O teste usa o pacote separado `com.example.tinhaphone.integration`.
- Permanecem avisos preventivos do Flutter sobre futuras atualizações de Gradle, AGP e Kotlin; eles não impedem esta compilação.
