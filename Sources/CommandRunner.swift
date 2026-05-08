import Foundation

protocol CommandRunner: Sendable {
    func run(executable: String, arguments: [String]) async throws -> Data
}

struct ProcessCommandRunner: CommandRunner {
    func run(executable: String, arguments: [String]) async throws -> Data {
        try await Task.detached(priority: nil) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                throw CommandError.notFound
            } catch {
                throw error
            }

            process.waitUntilExit()

            let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            guard process.terminationStatus == 0 else {
                let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw CommandError.nonZeroExit(process.terminationStatus, stderr)
            }

            return output
        }.value
    }
}

enum CommandError: Error, Equatable, Sendable {
    case nonZeroExit(Int32, String)
    case notFound
}
