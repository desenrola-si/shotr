# Shotr

Captura de tela para macOS na barra de menus, no espírito do Shottr: seleção congelada com lupa,
editor de anotação, OCR e captura de página rolando. Swift + AppKit + ScreenCaptureKit + Vision,
sem dependência externa.

## Instalar

```bash
./build.sh                 # gera ~/Applications/Shotr.app
open ~/Applications/Shotr.app
```

Na primeira execução o macOS pede **Gravação de Tela**: Ajustes do Sistema › Privacidade e
Segurança › Gravação de Tela → marcar o Shotr → reabrir o app.

### Assinatura e a permissão que não gruda

Assinado ad-hoc, cada `./build.sh` muda o `cdhash` e o macOS trata o resultado como **outro app**:
o Shotr continua marcado no painel e a captura segue negada, porque o requisito gravado no TCC
aponta para o binário anterior.

```bash
Tools/setup-signing.sh   # certificado local, uma vez só
./build.sh               # passa a assinar com ele
```

O requisito vira `identifier "com.ximenes.shotr" and certificate root = H"…"` — preso ao
certificado, não ao binário. A autorização passa a sobreviver aos rebuilds.

Se a permissão travar em estado inconsistente:

```bash
tccutil reset ScreenCapture com.ximenes.shotr
```

## Atalhos

| Atalho | Ação |
|---|---|
| ⇧⌘1 | Capturar tela inteira (a que está sob o cursor) |
| ⇧⌘2 | Capturar área |
| ⇧⌘3 | Captura rolando (costura os quadros) |
| ⌃⌥⌘O | Reconhecer texto/QR de uma área |
| ⇧⌘4 | Repetir a última área |
| ⇧⌘5 | Conta-gotas de cor (copia o hex) |

Na seleção de área: arrastar seleciona, clique simples pega a janela sob o cursor, **Espaço**
captura a tela inteira, **Esc** cancela. A lupa mostra o pixel e o hex embaixo do cursor.

No editor:

| Tecla | Ferramenta |
|---|---|
| V | selecionar/mover |
| A | seta |
| R | retângulo |
| O | elipse |
| L | linha |
| P | lápis |
| T | texto |
| N | numerador |
| H | marca-texto |
| B | desfoque |
| X | pixelar |
| K | tarja preta |
| C | recortar |

⌘C copia, ⌘S salva, ⇧⌘S salva como, ⌘Z desfaz, ⇧⌘Z refaz, ⌘+/− zoom, ⌘0 tamanho real.
Segurar ⇧ ao arrastar trava ângulo (linha/seta) ou proporção (retângulo/elipse).

## Abrir junto com o sistema

Menu da barra › **Abrir ao Iniciar** (`SMAppService`, o mecanismo atual de Itens de Início do macOS).
Pelo terminal:

```bash
~/Applications/Shotr.app/Contents/MacOS/Shotr --login-status    # --enable-login / --disable-login
```

O registro grava o caminho do bundle: se mover o `Shotr.app`, desligue e ligue de novo.
O app fica só na barra de menus (`LSUIElement`) — sem ícone no Dock e fora do ⌘Tab, exceto
enquanto uma janela do editor está aberta.

## Linha de comando

```bash
~/Applications/Shotr.app/Contents/MacOS/Shotr --area      # --screen --scroll --ocr --color --previous
```

## Como a captura rolando funciona

Cada quadro é convertido para tons de cinza, e as últimas 70 linhas do que já foi costurado são
procuradas no quadro novo por soma de diferenças absolutas. Achado o encaixe, só o que está abaixo
dele é anexado. Sem conteúdo novo por ~40 quadros, a captura fecha sozinha.

Verificado com uma página sintética de 2400 px capturada em janelas de 700 px a passos de 130 px:
14 quadros costurados, 2390 px de altura, diferença média de 0,00 contra o original.

## Ajustes

Pasta de destino, formato (PNG/JPEG/TIFF), qualidade JPEG, o que fazer depois de capturar
(editor, copiar, salvar), som, modelo do nome do arquivo e intervalo da captura rolando.

## Estrutura

```
Sources/Shotr/
  main.swift                    ciclo de vida, menu principal, flags de CLI
  MenuBarController.swift       menu da barra
  CaptureCoordinator.swift      orquestra as ações e o pós-captura
  ScreenCapturer.swift          ScreenCaptureKit (tela, janela, retângulo)
  AreaSelector.swift            overlay congelado, lupa, conta-gotas
  ScrollingCapture.swift        laço de captura + HUD
  ImageStitcher.swift           costura por correlação de linhas
  CanvasView.swift              editor: entrada, seleção, undo, recorte
  AnnotationRenderer.swift      desenho e exportação das anotações
  Annotation.swift              modelo das anotações
  TextRecognizer.swift          Vision: texto + QR
  EditorWindowController.swift  janela do editor
  SettingsWindowController.swift
  ImageOutput.swift             salvar, copiar, colar
```
