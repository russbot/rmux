import Foundation

/// Codable representation of a conductor.json file.
/// See https://docs.conductor.build/core/conductor-json
struct ConductorConfig: Codable {
    struct Scripts: Codable {
        let setup: String?
        let run: String?
        let archive: String?
    }

    let scripts: Scripts?
    let runScriptMode: String?

    static func load(repoRoot: String) -> ConductorConfig? {
        let url = URL(fileURLWithPath: repoRoot).appendingPathComponent("conductor.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ConductorConfig.self, from: data)
    }
}
