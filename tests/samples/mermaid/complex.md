# Mermaid rendering test

Sample content for checking diagram rendering, sizing and zoom behaviour on
phones. Ordered deliberately: the first two diagrams test *size* handling at
both extremes, the rest cover diagram types the renderer supports to differing
degrees.

## 1. A deliberately tiny diagram

Two nodes, nothing more. It should render small. If it is stretched to the full
width of the column, the page CSS is forcing `width: 100%` on every SVG.

```mermaid
graph LR
    A[Start] --> B[End]
```

## 2. A deliberately large diagram

Wide and deep, with subgraphs. On a phone this must shrink to fit, stay
legible, and be pinch-zoomable to read the labels.

```mermaid
graph TD
    subgraph Input
        A1[Markdown file] --> A2[Read from disk]
        A2 --> A3[Strip front matter]
    end
    subgraph Parsing
        A3 --> B1[comrak GFM parse]
        B1 --> B2[Add heading ids]
        B2 --> B3[Extract table of contents]
        B1 --> B4[Find mermaid fences]
    end
    subgraph Diagrams
        B4 --> C1[mermaid-rs-renderer]
        C1 --> C2[Inline SVG]
        C1 --> C3[Fallback to mermaid.js]
    end
    subgraph Images
        B2 --> D1[Resolve relative paths]
        D1 --> D2[Validate magic bytes]
        D2 --> D3[Rasterise SVG to PNG]
        D2 --> D4[Embed as data URI]
        D1 --> D5[Apply remote URL policy]
        D5 --> D6[Placeholder if blocked]
    end
    subgraph Output
        C2 --> E1[build_html]
        C3 --> E1
        D3 --> E1
        D4 --> E1
        D6 --> E1
        B3 --> E1
        E1 --> E2[Desktop webview]
        E1 --> E3[iOS WKWebView]
        E1 --> E4[Android WebView]
    end
```

## 3. Sequence diagram with loops and alternatives

```mermaid
sequenceDiagram
    participant U as User
    participant A as App
    participant C as Rust core
    participant P as Play or App Store
    U->>A: Open document
    A->>C: render_page(markdown, base_dir)
    loop For each image
        C->>C: Resolve and validate
    end
    C-->>A: HTML page
    A-->>U: Rendered document
    U->>A: Tap Support
    A->>P: Query products
    alt Products available
        P-->>A: Three tiers with prices
        U->>A: Choose a tier
        A->>P: Launch purchase
        P-->>A: Purchase complete
        A->>P: Consume
    else Nothing configured
        P-->>A: Empty catalogue
        A-->>U: Support unavailable
    end
```

## 4. State diagram

```mermaid
stateDiagram-v2
    [*] --> Welcome
    Welcome --> Viewing: Open document
    Viewing --> Searching: Tap search
    Searching --> Viewing: Cancel
    Viewing --> Settings: Open settings
    Settings --> Viewing: Back
    Viewing --> [*]: Close
```

## 5. Class diagram

```mermaid
classDiagram
    class MdrCore {
        +renderPage(markdown, baseDir, lang, editor, toc)
        +updateScript(markdown, baseDir, lang)
        +detectLang(markdown, lang)
        +version
    }
    class Billing {
        +start()
        +buy(tier)
        +stop()
    }
    class Prefs {
        +showToc
        +lang
    }
    MdrCore <|-- Android
    MdrCore <|-- iOS
    Billing --> MdrCore
    Prefs --> MdrCore
```

## 6. Entity relationship diagram

```mermaid
erDiagram
    DOCUMENT ||--o{ HEADING : contains
    DOCUMENT ||--o{ IMAGE : references
    DOCUMENT ||--o{ DIAGRAM : contains
    DOCUMENT {
        string path
        string baseDir
        string lang
    }
    HEADING {
        int level
        string text
        string anchor
    }
```

## 7. Pie chart

```mermaid
pie title Where rendering time goes
    "Markdown parse" : 20
    "Mermaid diagrams" : 45
    "Image embedding" : 25
    "Page assembly" : 10
```

## 8. Japanese labels

CJK text inside a diagram uses the font stack the document language selects,
so this should render in a Japanese face rather than a fallback.

```mermaid
graph LR
    A[文書を開く] --> B[解析]
    B --> C[図の描画]
    C --> D[画面に表示]
```

## 9. Decision nodes — known unsupported

The Rust renderer does not support diamond/decision nodes (`{text}`). This
should fall back to mermaid.js rather than failing, which is the behaviour
worth confirming on a phone, where the fallback script also has to run.

```mermaid
graph TD
    A[Start] --> B{Is it valid?}
    B -->|Yes| C[Render]
    B -->|No| D[Show error]
    C --> E[End]
    D --> E
```

## 10. Gantt

```mermaid
gantt
    title Release plan
    dateFormat YYYY-MM-DD
    section iOS
    TestFlight build     :done, 2026-09-20, 3d
    Device testing       :active, 2026-09-24, 4d
    section Android
    Internal testing     :2026-09-26, 4d
    Store listing        :2026-09-30, 3d
```
