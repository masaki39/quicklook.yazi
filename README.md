# quicklook.yazi

A [Yazi](https://github.com/sxyazi/yazi) previewer plugin for macOS that previews Office documents (and anything else Quick Look can thumbnail) using the system's Quick Look, with no LibreOffice required.

- `.docx` / `.xlsx` / `.pptx`, OpenDocument, etc. are rendered with `qlmanage -t` (Quick Look thumbnails).
- Legacy binary formats (`.xls` / `.doc` / `.ppt`) are rendered from Quick Look's HTML preview with the bundled `html2png` helper instead. Quick Look's thumbnails of those formats drop CJK text whose font isn't installed (e.g. ＭＳ 明朝), while its HTML preview falls back to an installed font the way Finder's space-bar preview does.

Only the first page is shown; there is no paging.

## Requirements

- macOS
- `html2png` (for `.xls` / `.doc` / `.ppt`):

  ```sh
  brew install masaki39/tap/html2png
  ```

## Installation

```sh
ya pkg add masaki39/quicklook
```

## Update

```sh
ya pkg upgrade masaki39/quicklook
brew upgrade masaki39/tap/html2png
```

## Configuration

Add previewers in `~/.config/yazi/yazi.toml`:

```toml
[plugin]
prepend_previewers = [
  { mime = "application/openxmlformats-officedocument.*", run = "quicklook" },
  { mime = "application/oasis.opendocument.*", run = "quicklook" },
  { mime = "application/ms-*", run = "quicklook" },
  { mime = "application/msword", run = "quicklook" },
  { url = "*.docx", run = "quicklook" },
]
```

## html2png

`html2png <in.html> <out.png> <width>` renders a local HTML file with WebKit and writes a `<width>`px-wide PNG of its first page. Its source is [`html2png/main.swift`](html2png/main.swift). To build it by hand:

```sh
swiftc -O html2png/main.swift -o html2png/html2png
```

## License

MIT
