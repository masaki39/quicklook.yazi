// html2png <in.html> <out.png> <width>
// Renders a local HTML file with WebKit and writes a <width>px-wide PNG
// snapshot of its first page (A4 aspect ratio). Used to rasterize Quick
// Look's HTML previews, which (unlike its thumbnails) fall back to installed
// fonts.
import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count == 4, let width = Double(args[3]) else {
	FileHandle.standardError.write("usage: html2png <in.html> <out.png> <width>\n".data(using: .utf8)!)
	exit(2)
}

// Layout width when the page doesn't declare one (e.g. spreadsheets).
let defaultViewport = 960.0
// Quick Look's documents declare their page width via `<meta name=viewport
// content="width=595">`, which Finder's preview honors but a macOS WKWebView
// ignores. Read it so the page fills the image instead of sitting in a wide
// blank canvas.
let viewportScript = """
	(() => {
		const m = document.querySelector('meta[name=viewport]');
		const w = m && /width=(\\d+)/.exec(m.content);
		return w ? Number(w[1]) : 0;
	})()
	"""

class Delegate: NSObject, WKNavigationDelegate {
	let output: URL
	let snapshotWidth: Double

	init(output: URL, snapshotWidth: Double) {
		self.output = output
		self.snapshotWidth = snapshotWidth
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		webView.evaluateJavaScript(viewportScript) { result, _ in
			let declared = (result as? Double) ?? 0
			let viewport = declared > 0 ? declared : defaultViewport
			webView.setFrameSize(NSSize(width: viewport, height: viewport * 1.414))
			// Let the resize relayout before snapshotting.
			DispatchQueue.main.async { self.snapshot(webView) }
		}
	}

	func snapshot(_ webView: WKWebView) {
		let config = WKSnapshotConfiguration()
		config.rect = webView.bounds
		config.snapshotWidth = NSNumber(value: snapshotWidth)
		webView.takeSnapshot(with: config) { image, error in
			guard let image, let tiff = image.tiffRepresentation,
				let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
			else {
				FileHandle.standardError.write("snapshot failed: \(String(describing: error))\n".data(using: .utf8)!)
				exit(1)
			}
			do { try png.write(to: self.output) } catch { exit(1) }
			exit(0)
		}
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { exit(1) }
	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { exit(1) }
}

let input = URL(fileURLWithPath: args[1])
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: defaultViewport, height: defaultViewport * 1.414))
let delegate = Delegate(output: URL(fileURLWithPath: args[2]), snapshotWidth: width)
webView.navigationDelegate = delegate
webView.loadFileURL(input, allowingReadAccessTo: input.deletingLastPathComponent())
DispatchQueue.main.asyncAfter(deadline: .now() + 10) { exit(1) }
app.run()
