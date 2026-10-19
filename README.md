# quicklook.yazi

A [Yazi](https://github.com/sxyazi/yazi) previewer plugin for macOS that previews Office documents (and anything else Quick Look can thumbnail) using the system's Quick Look, with no LibreOffice required.

- `.docx` / `.xlsx` / `.pptx`, OpenDocument, etc. are rendered with `qlmanage -t` (Quick Look thumbnails).
- Legacy binary formats (`.xls` / `.doc` / `.ppt`) are rendered from Quick Look's HTML preview with the bundled `html2png` helper instead. Quick Look's thumbnails of those formats drop CJK text whose font isn't installed (e.g. ＭＳ 明朝), while its HTML preview falls back to an installed font the way Finder's space-bar preview does.

Only the first page is shown; there is no paging. Unsupported files fall back to Yazi's built-in `file` previewer.

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

Add it as the last-resort previewer in `~/.config/yazi/yazi.toml`:

```toml
[plugin]
append_previewers = [
  { url = "*", run = "quicklook" },
]
```

A `url = "*"` rule in `append_previewers` replaces Yazi's preset `file` fallback, so files the built-in previewers already handle (code, images, video, PDF, archives, ...) keep their richer previews, and everything else (Office, iWork, ...) goes to Quick Look. Files Quick Look can't render fall back to the built-in `file` previewer. Since `qlmanage` hangs on such files, each call is bounded by a 3 s timeout and the result is remembered per file, and common binaries (`application/octet-stream`, Mach-O, SQLite, ...) are skipped up front.

You can also target specific types with `prepend_previewers` instead, e.g. `{ url = "*.{docx,xlsx,pptx}", run = "quicklook" }`.

## html2png

`html2png <in.html> <out.png> <width>` renders a local HTML file with WebKit and writes a `<width>`px-wide PNG of its first page. Its source is [`html2png/main.swift`](html2png/main.swift). To build it by hand:

```sh
swiftc -O html2png/main.swift -o html2png/html2png
```

## License

MIT
