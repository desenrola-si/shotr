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

> O app é assinado ad-hoc (sem certificado de desenvolvedor). Cada rebuild muda a identidade,
> então o macOS pode pedir a permissão de novo depois de rodar `./build.sh`.

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
