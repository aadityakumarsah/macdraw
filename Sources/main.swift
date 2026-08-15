import AppKit

setbuf(stdout, nil)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate

if CommandLine.arguments.contains("--selftest") {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        delegate.runSelfTest()
    }
}

app.run()
