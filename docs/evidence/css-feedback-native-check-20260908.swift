import AppKit
import WebKit

// Fixed local reproduction of the captured item, not model-generated code.
// No remote content, persistent website storage, or visible app window.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let configuration = WKWebViewConfiguration()
configuration.websiteDataStore = .nonPersistent()
let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 300), configuration: configuration)
let html = """
<!doctype html><meta charset="utf-8">
<style>
body { margin: 0; }
.grid { display: grid; grid-template-columns: repeat(3, 1fr);
  grid-auto-rows: 40px; width: 300px; }
.span { grid-column: span 2; }
#sparse { grid-auto-flow: row; }
#dense { grid-auto-flow: row dense; }
</style>
<div id="sparse" class="grid"><div class="span">A</div><div class="span">B</div><div>C</div></div>
<div id="dense" class="grid"><div class="span">A</div><div class="span">B</div><div>C</div></div>
"""
let script = """
JSON.stringify(['sparse', 'dense'].map(id => {
  const grid = document.getElementById(id), origin = grid.getBoundingClientRect();
  return {mode: id, width: origin.width, height: origin.height,
    cells: [...grid.children].map(child => {
      const r = child.getBoundingClientRect();
      return {item: child.textContent, row: 1 + (r.top - origin.top) / 40,
        column: 1 + (r.left - origin.left) / 100, columnSpan: r.width / 100};
    })};
}))
"""
final class Observer: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(script) { value, error in
            guard error == nil, let result = value as? String else {
                fputs("Local layout observation failed.\n", stderr)
                exit(1)
            }
            print(result)
            exit(0)
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { exit(1) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { exit(1) }
}
let observer = Observer()
view.navigationDelegate = observer
view.loadHTMLString(html, baseURL: nil)
DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
    fputs("Local layout observation exceeded 20 seconds.\n", stderr)
    exit(2)
}
RunLoop.main.run()
