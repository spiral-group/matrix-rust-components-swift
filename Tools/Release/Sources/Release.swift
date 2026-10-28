// Modified by the Spiral authors, 2026: local-only builds, PROVENANCE.json, and
// publishing only to an explicitly named Spiral owner.

import ArgumentParser
import CommandLineTools
import Foundation

@main
struct Release: AsyncParsableCommand {
    @Option(help: "An optional build number that will be appended to the generated version (e.g. 25.12.31-123). This option is ignored when a custom version is specified.")
    var buildNumber: Int? = nil

    @Option(help: "A custom version to use instead of generating a calendar version. This option takes precedence over --build-number.")
    var customVersion: String? = nil

    var version: String {
        customVersion ?? Date.now.calendarVersion(buildNumber: buildNumber)
    }

    @Flag(help: "Prevents the run from pushing anything to GitHub.")
    var localOnly = false

    @Option(help: "The GitHub owner of both Spiral forks. Required unless --local-only is used.")
    var githubOwner: String?

    @Option(help: "The release asset base URL written to Package.swift. Required unless --local-only is used.")
    var releaseBaseURL: String?

    var packageDirectory = URL(fileURLWithPath: #file)
        .deletingLastPathComponent() // Release.swift
        .deletingLastPathComponent() // Sources
        .deletingLastPathComponent() // Release
        .deletingLastPathComponent() // Tools
    var buildDirectory: URL {
        packageDirectory
            .deletingLastPathComponent() // matrix-rust-components-swift
            .appending(component: "matrix-rust-sdk")
    }

    var sourceRepo: Repository {
        Repository(owner: githubOwner ?? "spiral-local", name: "matrix-rust-sdk")
    }

    var packageRepo: Repository {
        Repository(owner: githubOwner ?? "spiral-local", name: "matrix-rust-components-swift")
    }

    mutating func validate() throws {
        guard !localOnly else { return }

        guard githubOwner?.isEmpty == false else {
            throw ValidationError("--github-owner is required for publishing.")
        }
        guard releaseBaseURL?.isEmpty == false else {
            throw ValidationError("--release-base-url is required for publishing.")
        }
    }

    mutating func run() async throws {
        let apiToken = localOnly ? "" : try githubAPIToken()
        let package = Package(repository: packageRepo, directory: packageDirectory, apiToken: apiToken)
        Zsh.defaultDirectory = package.directory

        Log.info("Build directory: \(buildDirectory.path())")

        let product = try build()
        let (zipFileURL, checksum) = try package.zipBinary(with: product)

        try updateGeneratedSources(with: product)
        try writeProvenance(for: product, checksum: checksum)

        guard !localOnly else {
            try installLocalFramework(from: product)
            Log.info("Local package ready. No manifest, git, or network publication changes were made.")
            return
        }

        try await updateManifest(package, with: product, checksum: checksum)
        try validatePublishRemote()
        try commitAndPush(package, with: product)
        try await package.makeRelease(with: product, uploading: zipFileURL)
    }

    mutating func build() throws -> BuildProduct {
        let git = Git(directory: buildDirectory)
        let commitHash = try git.commitHash
        let branch = try git.branchName

        let sourceChanges = try Zsh.run(command: "git status --porcelain", directory: buildDirectory)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard sourceChanges?.isEmpty != false else {
            throw ValidationError("The matrix-rust-sdk checkout must be clean so provenance identifies the exact source.")
        }

        Log.info("Building \(branch) at \(commitHash)")

        // unset fixes an issue where swift compilation prevents building for targets other than macOS
        let cargoCommand = "cargo xtask swift build-framework --release --target aarch64-apple-ios --target aarch64-apple-ios-sim"
        try Zsh.run(command: "unset SDKROOT && \(cargoCommand)", directory: buildDirectory)

        return BuildProduct(sourceRepo: sourceRepo,
                            version: version,
                            commitHash: commitHash,
                            branch: branch,
                            directory: buildDirectory.appending(component: "bindings/apple/generated/"),
                            frameworkName: "MatrixSDKFFI.xcframework")
    }

    func updateGeneratedSources(with product: BuildProduct) throws {
        Log.info("Copying sources")
        let source = product.directory.appending(component: "swift", directoryHint: .isDirectory)
        let destination = packageDirectory.appending(component: "Sources/MatrixRustSDK", directoryHint: .isDirectory)
        try Zsh.run(command: "rsync -a --delete '\(source.path())' '\(destination.path())'")
    }

    func updateManifest(_ package: Package, with product: BuildProduct, checksum: String) async throws {
        try await package.updateManifest(with: product, checksum: checksum)

        guard let releaseBaseURL else {
            throw ValidationError("Missing release base URL after validation.")
        }

        let manifestURL = package.directory.appending(component: "Package.swift")
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        let lines = manifest.split(separator: "\n", omittingEmptySubsequences: false)
        let updatedManifest = lines.map { line in
            line.starts(with: "let releaseBaseURL = ")
                ? "let releaseBaseURL = \"\(releaseBaseURL)\""
                : String(line)
        }.joined(separator: "\n")
        try updatedManifest.write(to: manifestURL, atomically: true, encoding: .utf8)
    }

    func installLocalFramework(from product: BuildProduct) throws {
        Log.info("Installing local framework")
        let source = product.directory.appending(component: product.frameworkName, directoryHint: .isDirectory)
        let destination = packageDirectory.appending(component: product.frameworkName, directoryHint: .isDirectory)
        try Zsh.run(command: "rsync -a --delete '\(source.path())/' '\(destination.path())/'")

        // The manifest target depends on this ignored directory, which is not part of SwiftPM's cache key.
        let manifest = packageDirectory.appending(component: "Package.swift")
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: manifest.path())
    }

    func writeProvenance(for product: BuildProduct, checksum: String) throws {
        // A checkout cloned from the published fork has only `origin`.
        let upstreamURL = try Zsh.run(command: "git remote get-url upstream 2>/dev/null || git remote get-url origin", directory: buildDirectory)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let provenance = BuildProvenance(packageVersion: product.version,
                                         sourceCommit: product.commitHash,
                                         sourceBranch: product.branch,
                                         sourceUpstreamURL: upstreamURL,
                                         artifactName: "\(product.frameworkName).zip",
                                         artifactSHA256: checksum)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(provenance)
        try data.write(to: packageDirectory.appending(component: "PROVENANCE.json"), options: Data.WritingOptions.atomic)
    }

    func validatePublishRemote() throws {
        guard let githubOwner else {
            throw ValidationError("Missing GitHub owner after validation.")
        }

        let expectedSuffix = "/\(githubOwner)/matrix-rust-components-swift.git"
        let originURL = try Zsh.run(command: "git remote get-url origin", directory: packageDirectory)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard originURL?.hasSuffix(expectedSuffix) == true else {
            throw ValidationError("Refusing to publish: origin must end with \(expectedSuffix).")
        }
    }

    func commitAndPush(_ package: Package, with product: BuildProduct) throws {
        Log.info("Pushing changes")

        let git = Git(directory: package.directory)
        try git.add(files: "Package.swift", "PROVENANCE.json", "Sources")
        try git.commit(message: "Bump to version \(version) (\(product.sourceRepo.name)/\(product.branch) \(product.commitHash))")
        try Zsh.run(command: "git push origin HEAD", directory: package.directory)
    }

    func githubAPIToken() throws -> String {
        let netrcURL = FileManager.default.homeDirectoryForCurrentUser.appending(component: ".netrc")
        guard let netrc = try? NetrcParser.parse(file: netrcURL),
              let authorization = netrc.authorization(for: URL(string: "https://api.github.com")!)
        else {
            throw ValidationError("A GitHub API token for api.github.com is required in ~/.netrc when publishing.")
        }
        return authorization.password
    }
}

private struct BuildProvenance: Encodable {
    let packageVersion: String
    let sourceCommit: String
    let sourceBranch: String
    let sourceUpstreamURL: String?
    let artifactName: String
    let artifactSHA256: String
}
