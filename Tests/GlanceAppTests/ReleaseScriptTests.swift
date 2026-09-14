import Foundation
import Testing

@Test(arguments: ["https://updates.invalid/downloads", "https://updates.invalid/downloads/"])
func appcastScriptPassesSupportedOptionsAndDirectoryURL(downloadBase: String) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let scripts = root.appendingPathComponent("scripts")
    let toolDirectory = root.appendingPathComponent(".build/artifacts/sparkle/Sparkle/bin")
    let archives = root.appendingPathComponent("archives")
    for directory in [scripts.appendingPathComponent("lib"), toolDirectory, archives] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    for file in ["generate-appcast.sh", "lib/release-env.sh"] {
        try FileManager.default.copyItem(at: repository.appendingPathComponent("scripts/\(file)"), to: scripts.appendingPathComponent(file))
    }
    let tool = toolDirectory.appendingPathComponent("generate_appcast")
    try """
    #!/bin/zsh
    set -euo pipefail
    [[ "$#" == 7 ]]
    [[ "$1" == --ed-key-file && -f "$2" ]]
    [[ "$3" == --download-url-prefix && "$4" == https://updates.invalid/downloads/ ]]
    [[ "$5" == -o && -d "$7" && -f "$7/Glance.zip" ]]
    print -r -- '<rss/>' > "$6"
    """.write(to: tool, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
    let key = root.appendingPathComponent("test-key")
    try Data().write(to: key)
    try Data().write(to: archives.appendingPathComponent("Glance.zip"))
    let output = root.appendingPathComponent("feed/appcast.xml")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = [scripts.appendingPathComponent("generate-appcast.sh").path]
    process.currentDirectoryURL = FileManager.default.temporaryDirectory
    process.environment = [
        "PATH": "/usr/bin:/bin", "DIST_DIR": archives.path,
        "DOWNLOAD_BASE_URL": downloadBase, "SPARKLE_PRIVATE_KEY_FILE": key.path,
        "APPCAST_OUTPUT": output.path,
    ]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let diagnostic = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(process.terminationStatus == 0, "\(diagnostic)")
    #expect(FileManager.default.fileExists(atPath: output.path))
}
