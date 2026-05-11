import Foundation

let args = CommandLine.arguments
let foreground = args.contains("--foreground")

/// Kill any other running PRMenu processes (except ourselves).
func killExistingInstances() {
    let myPid = getpid()
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-x", "PRMenu"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    try? task.run()
    task.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    for line in output.split(separator: "\n") {
        if let pid = pid_t(line), pid != myPid {
            kill(pid, SIGTERM)
        }
    }
}

if !foreground {
    killExistingInstances()

    // Re-launch self with --foreground so the original process can exit
    // and return control to the terminal.
    let executablePath = ProcessInfo.processInfo.arguments[0]
    var newArgs = args
    newArgs.append("--foreground")

    let argv = newArgs.map { strdup($0) } + [nil]
    defer { argv.compactMap { $0 }.forEach { free($0) } }

    var pid: pid_t = 0
    var attrs: posix_spawnattr_t?
    posix_spawnattr_init(&attrs)
    posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_SETPGROUP))
    posix_spawnattr_setpgroup(&attrs, 0)

    let status = posix_spawn(&pid, executablePath, nil, &attrs, argv, environ)
    posix_spawnattr_destroy(&attrs)

    if status == 0 {
        _exit(0)
    } else {
        fputs("pr-menu: failed to background (\(status)), running in foreground\n", stderr)
    }
}

PRMenuApp.main()
