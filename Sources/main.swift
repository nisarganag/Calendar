import Cocoa

let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.nisarga.calbar")
if running.count > 1 {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate.shared
app.delegate = delegate
app.run()
