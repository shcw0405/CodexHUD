import AppKit

// The app keeps a long-lived stdin pipe to the Codex app-server. If that
// process dies, a write would otherwise raise SIGPIPE and kill us; ignore it
// and let `FileHandle.write(contentsOf:)` surface a catchable error instead.
signal(SIGPIPE, SIG_IGN)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
