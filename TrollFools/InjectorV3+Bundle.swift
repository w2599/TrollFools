//
//  InjectorV3+Bundle.swift
//  TrollFools
//
//  Created by 82Flex on 2025/1/10.
//

import OrderedCollections

extension InjectorV3 {

    // MARK: - Constants

    static let ignoredDylibAndFrameworkNames: Set<String> = [
        "cydiasubstrate",
        "cydiasubstrate.framework",
        "CydiaSubstrate",
        "CydiaSubstrate.framework",
        "CCC",
        "CCC.framework",
        "ellekit",
        "ellekit.framework",
        "ElleKit",
        "ElleKit.framework",
        "libsubstrate.dylib",
        "libSubstrate.dylib",
        "libsubstitute.dylib",
        "libSubstitute.dylib",
        "libellekit.dylib",
        "libElleKit.dylib",
    ]

    static let substrateName = "CCC"
    static let substrateFwkName = "CCC.framework"
    
    fileprivate static let infoPlistName = "Info.plist"
    fileprivate static let injectedMarkerName = ".troll-fools"

    // MARK: - Instance Methods

    var hasInjectedAsset: Bool {
        !injectedAssetURLsInBundle(bundleURL).isEmpty
    }

    // MARK: - Shared Methods

    func frameworkMachOsInBundle(_ target: URL) throws -> OrderedSet<URL> {

        precondition(checkIsBundle(target), "Not a bundle: \(target.path)")

        let executableURL = try locateExecutableInBundle(target)
        precondition(isMachO(executableURL), "Not a Mach-O: \(executableURL.path)")

        let frameworksURL = target.appendingPathComponent("Frameworks")
        let linkedDylibs = try linkedDylibsRecursivelyOfMachO(executableURL)

        var machOs = OrderedSet<URL>()
        if let enumerator = FileManager.default.enumerator(
            at: frameworksURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let itemURL as URL in enumerator {
                if checkIsInjectedBundle(itemURL) {
                    enumerator.skipDescendants()
                    continue
                }
                if linkedDylibs.contains(itemURL) && itemURL.deletingLastPathComponent().pathExtension == "framework" {
                    machOs.append(itemURL)
                }
            }
        }

        var sortedMachOs = try machOs
            .sorted { url1, url2 in
                let size1 = (try url1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let size2 = (try url2.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return if size1 == size2 {
                    url1.lastPathComponent.localizedStandardCompare(url2.lastPathComponent) == .orderedAscending
                } else {
                    size1 < size2
                }
            }

        if preferMainExecutable.wrappedValue {
            sortedMachOs.insert(executableURL, at: 0)
        } else {
            sortedMachOs.append(executableURL)
        }

        return OrderedSet(sortedMachOs)
    }

    func injectedAssetURLsInBundle(_ target: URL) -> [URL] {
        return (injectedBundleURLsInBundle(target) + injectedDylibAndFrameworkURLsInBundle(target))
            .sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
    }

    func injectedBundleURLsInBundle(_ target: URL) -> [URL] {

        precondition(checkIsBundle(target), "Not a bundle: \(target.path)")

        guard let bundleContentURLs = try? FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        let bundleURLs = bundleContentURLs
            .filter {
                $0.pathExtension.lowercased() == "bundle" &&
                !Self.ignoredDylibAndFrameworkNames.contains($0.lastPathComponent)
            }
            .filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            }
            .filter {
                checkIsInjectedBundle($0)
            }
            .sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })

        return bundleURLs
    }

    func injectedDylibAndFrameworkURLsInBundle(_ target: URL) -> [URL] {

        precondition(checkIsBundle(target), "Not a bundle: \(target.path)")

        let frameworksURL = target.appendingPathComponent("Frameworks")
        guard let frameworksContentURLs = try? FileManager.default.contentsOfDirectory(at: frameworksURL, includingPropertiesForKeys: nil) else {
            return []
        }

        let dylibURLs = frameworksContentURLs
            .filter {
                $0.pathExtension.lowercased() == "dylib" &&
                !$0.lastPathComponent.hasPrefix("libswift") &&
                !Self.ignoredDylibAndFrameworkNames.contains($0.lastPathComponent)
            }
            .sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })

        let frameworkURLs = frameworksContentURLs
            .filter {
                $0.pathExtension.lowercased() == "framework" &&
                !Self.ignoredDylibAndFrameworkNames.contains($0.lastPathComponent)
            }
            .filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            }
            .filter {
                checkIsInjectedBundle($0)
            }
            .sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })

        return dylibURLs + frameworkURLs
    }

    func markBundlesAsInjected(_ bundleURLs: [URL], privileged: Bool) throws {

        let filteredURLs = bundleURLs.filter { checkIsBundle($0) }
        precondition(filteredURLs.count == bundleURLs.count, "Not all urls are bundles")

        if privileged {
            let markerURL = temporaryDirectoryURL.appendingPathComponent(Self.injectedMarkerName)
            try Data().write(to: markerURL, options: .atomic)
            try cmdChangeOwnerToInstalld(markerURL, recursively: false)

            try filteredURLs.forEach {
                try cmdCopy(from: markerURL, to: $0.appendingPathComponent(Self.injectedMarkerName), overwrite: true)
            }
        } else {
            try filteredURLs.forEach {
                try Data().write(to: $0.appendingPathComponent(Self.injectedMarkerName), options: .atomic)
            }
        }
    }

    func identifierOfBundle(_ target: URL) throws -> String {

        precondition(checkIsBundle(target), "Not a bundle: \(target.path)")

        if let bundleIdentifier = Bundle(url: target)?.bundleIdentifier {
            return bundleIdentifier
        }

        let infoPlistURL = target.appendingPathComponent(Self.infoPlistName)
        let infoPlistData = try Data(contentsOf: infoPlistURL)

        guard let infoPlist = try PropertyListSerialization.propertyList(from: infoPlistData, options: [], format: nil) as? [String: Any]
        else {
            throw Error.generic(String(format: NSLocalizedString("Failed to parse: %@", comment: ""), infoPlistURL.path))
        }

        guard let bundleIdentifier = infoPlist["CFBundleIdentifier"] as? String else {
            throw Error.generic(String(format: NSLocalizedString("Failed to find entry CFBundleIdentifier in: %@", comment: ""), infoPlistURL.path))
        }

        return bundleIdentifier
    }

    func locateFrameworksDirectoryInBundle(_ target: URL) throws -> URL {

        precondition(checkIsBundle(target), "Not a bundle: \(target.path)")

        let frameworksDirectoryURL = target.appendingPathComponent("Frameworks")
        if !FileManager.default.fileExists(atPath: frameworksDirectoryURL.path) {
            try cmdMakeDirectory(at: target)
        }

        return frameworksDirectoryURL
    }

    func locateExecutableInBundle(_ target: URL) throws -> URL {

        precondition(checkIsBundle(target), "Not a bundle: \(target.path)")

        if let executableURL = Bundle(url: target)?.executableURL {
            return executableURL
        }

        let infoPlistURL = target.appendingPathComponent(Self.infoPlistName)
        let infoPlistData = try Data(contentsOf: infoPlistURL)

        guard let infoPlist = try PropertyListSerialization.propertyList(from: infoPlistData, options: [], format: nil) as? [String: Any]
        else {
            throw Error.generic(String(format: NSLocalizedString("Failed to parse: %@", comment: ""), infoPlistURL.path))
        }

        guard let executableName = infoPlist["CFBundleExecutable"] as? String else {
            throw Error.generic(String(format: NSLocalizedString("Failed to find entry CFBundleExecutable in: %@", comment: ""), infoPlistURL.path))
        }

        let executableURL = target.appendingPathComponent(executableName)
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw Error.generic(String(format: NSLocalizedString("Failed to locate main executable: %@", comment: ""), executableURL.path))
        }

        return executableURL
    }

    func checkIsEligibleAppBundle(_ target: URL) -> Bool {
        guard checkIsBundle(target) else {
            return false
        }

        let frameworksURL = target.appendingPathComponent("Frameworks")
        return !((try? FileManager.default.contentsOfDirectory(at: frameworksURL, includingPropertiesForKeys: nil).isEmpty) ?? true)
    }

    func checkIsInjectedAppBundle(_ target: URL) -> Bool {
        guard checkIsBundle(target) else {
            return false
        }

        let frameworksURL = target.appendingPathComponent("Frameworks")
        let substrateFwkURL = frameworksURL.appendingPathComponent(Self.substrateFwkName)

        return FileManager.default.fileExists(atPath: substrateFwkURL.path)
    }

    func checkIsInjectedBundle(_ target: URL) -> Bool {
        guard checkIsBundle(target) else {
            return false
        }

        let markerURL = target.appendingPathComponent(Self.injectedMarkerName)
        return FileManager.default.fileExists(atPath: markerURL.path)
    }

    func checkIsBundle(_ target: URL) -> Bool {
        let values = try? target.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        let isDirectory = values?.isDirectory ?? false
        let isPackage = values?.isPackage ?? false
        let pathExt = target.pathExtension.lowercased()
        return isPackage || (isDirectory && (pathExt == "app" || pathExt == "bundle" || pathExt == "framework"))
    }
}
