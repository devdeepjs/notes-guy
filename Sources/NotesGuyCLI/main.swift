import Foundation
import NotesGuyCore

@main
struct NotesGuyCLI {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let vaultPath = parseVaultPath(arguments: arguments)
        let configuration: VaultConfiguration

        if let vaultPath {
            configuration = VaultConfiguration(vaultPath: vaultPath)
        } else {
            configuration = VaultStore.configurationFromEnvironment()
        }

        let store = VaultStore(configuration: configuration)
        let result = try store.bootstrap()

        print("notes-guy workspace ready")
        print("vault: \(result.vaultURL.path)")
        if result.changedFiles.isEmpty {
            print("changed: none")
        } else {
            print("changed:")
            for path in result.changedFiles {
                print("- \(path)")
            }
        }
    }

    private static func parseVaultPath(arguments: [String]) -> String? {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if argument == "--vault" {
                return iterator.next()
            }
            if argument.hasPrefix("--vault=") {
                return String(argument.dropFirst("--vault=".count))
            }
        }
        return nil
    }
}
