#!/usr/bin/env swift
import Foundation

// Sangeet AI - CLI Process Forwarder
// This script compiles and executes the 'verify-mastering' target inside packages/audio-engine.
// It maps arguments perfectly, resolving all modules and transitive C-headers automatically.

let scriptFile = URL(fileURLWithPath: CommandLine.arguments[0])
let workspaceRoot = scriptFile.deletingLastPathComponent().deletingLastPathComponent()
let packagePath = workspaceRoot.appendingPathComponent("packages/audio-engine").path

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["swift", "run", "--package-path", packagePath, "verify-mastering"] + Array(CommandLine.arguments.dropFirst())

// Forward environment variables
process.environment = ProcessInfo.processInfo.environment

do {
    try process.run()
    process.waitUntilExit()
    exit(process.terminationStatus)
} catch {
    print("Error: Failed to launch verification runner: \(error.localizedDescription)")
    exit(1)
}
