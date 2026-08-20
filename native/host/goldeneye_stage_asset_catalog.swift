import Compression
import CryptoKit
import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

public enum GoldenEyeStageAssetCatalogError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingManifest
    case malformedManifest(String)
    case manifestGuard(String)
    case missingAsset(String)
    case oversizedAsset(String)
    case catalogStatus(String, UInt32)
    case catalogMismatch(String)
    case assetStatus(String, UInt32)
    case digestMismatch(String, String, String)
    case decodedMismatch(String)
    case decodeFailure(String, UInt32, UInt32)
    case stubStatus(UInt32, UInt32)

    public var description: String {
        switch self {
        case .missingManifest:
            return "native stage asset manifest is missing"
        case let .malformedManifest(detail):
            return "native stage asset manifest is malformed: \(detail)"
        case let .manifestGuard(detail):
            return "native stage asset manifest guard failed: \(detail)"
        case let .missingAsset(name):
            return "native stage asset is missing: \(name)"
        case let .oversizedAsset(name):
            return "native stage asset exceeds bounded input size: \(name)"
        case let .catalogStatus(operation, status):
            return "native stage C catalog operation \(operation) failed with status \(status)"
        case let .catalogMismatch(detail):
            return "native stage catalog mismatch: \(detail)"
        case let .assetStatus(name, status):
            return "native stage asset \(name) failed C validation with status \(status)"
        case let .digestMismatch(name, kind, detail):
            return "native stage \(kind) digest mismatch for \(name): \(detail)"
        case let .decodedMismatch(name):
            return "native stage decoded bytes do not match prepared asset: \(name)"
        case let .decodeFailure(name, produced, expected):
            return "native stage 1172 decode count mismatch for \(name): produced \(produced), expected \(expected)"
        case let .stubStatus(milestone, status):
            return "native stage STUB(M\(milestone)) status failed with \(status)"
        }
    }
}

public enum GoldenEyeStageAssetKind: String, CaseIterable, Sendable, Equatable {
    case background
    case stan
    case setup

    fileprivate var cKind: UInt32 {
        switch self {
        case .background: return UInt32(GE_STAGE_V5_RESOURCE_BACKGROUND)
        case .stan: return UInt32(GE_STAGE_V5_RESOURCE_STAN)
        case .setup: return UInt32(GE_STAGE_V5_RESOURCE_SETUP)
        }
    }

    fileprivate var directoryName: String { rawValue }
}

public struct GoldenEyeStageAssetResource: Sendable, Equatable {
    public let stageID: UInt32
    public let stageName: String
    public let kind: GoldenEyeStageAssetKind
    public let resourceName: String
    public let assetHandle: UInt32
    public let sourceOffset: UInt32
    public let sourceBytes: UInt32
    public let decodedBytes: UInt32
    public let compressed1172: Bool
    public let sourceSHA256: String
    public let decodedSHA256: String
    public let sourceURL: URL
    public let decodedURL: URL

    fileprivate init(
        stageID: UInt32,
        stageName: String,
        kind: GoldenEyeStageAssetKind,
        resourceName: String,
        assetHandle: UInt32,
        sourceOffset: UInt32,
        sourceBytes: UInt32,
        decodedBytes: UInt32,
        compressed1172: Bool,
        sourceSHA256: String,
        decodedSHA256: String,
        sourceURL: URL,
        decodedURL: URL
    ) {
        self.stageID = stageID
        self.stageName = stageName
        self.kind = kind
        self.resourceName = resourceName
        self.assetHandle = assetHandle
        self.sourceOffset = sourceOffset
        self.sourceBytes = sourceBytes
        self.decodedBytes = decodedBytes
        self.compressed1172 = compressed1172
        self.sourceSHA256 = sourceSHA256
        self.decodedSHA256 = decodedSHA256
        self.sourceURL = sourceURL
        self.decodedURL = decodedURL
    }
}

public struct GoldenEyeStageAssetStage: Sendable, Equatable {
    public let stageID: UInt32
    public let stageName: String
    public let demoMask: UInt32
    public let resources: [GoldenEyeStageAssetResource]
}

public struct GoldenEyeStageStubReport: Sendable, Equatable {
    public let milestone: UInt32
    public let stageID: UInt32
    public let status: UInt32
    public let message: String
}

public struct GoldenEyeStageBootstrapStage: Sendable, Equatable {
    public let stageID: UInt32
    public let stageName: String
    public let resourceCount: UInt32
    public let sourceHash: UInt64
    public let decodedHash: UInt64
    public let stageHash: UInt64
}

public struct GoldenEyeStageBootstrapReport: Sendable, Equatable {
    public let stages: [GoldenEyeStageBootstrapStage]
    public let catalogHash: UInt64
    public let gameplayStub: GoldenEyeStageStubReport
    public let rendererStub: GoldenEyeStageStubReport

    public var isAssetReady: Bool { !stages.isEmpty && catalogHash != 0 }
}

/// Immutable native stage asset catalog.  It owns metadata and prepared-file
/// URLs only; it never retains the ROM or a resource byte buffer.  Loading
/// validates each row immediately, then discards source/decoded bytes after
/// deriving the deterministic stage report.
public struct GoldenEyeStageAssetCatalog: Sendable, Equatable {
    public static let manifestFileName = "stage-assets-manifest.txt"
    public static let expectedResourceCount = 21
    public static let maxPreparedBytes = 64 * 1024 * 1024

    public let rootURL: URL
    public let manifestURL: URL
    public let stages: [GoldenEyeStageAssetStage]
    public let bootstrapReport: GoldenEyeStageBootstrapReport

    public var catalogHash: UInt64 { bootstrapReport.catalogHash }

    public init(rootURL: URL, manifestURL: URL, stages: [GoldenEyeStageAssetStage], bootstrapReport: GoldenEyeStageBootstrapReport) {
        self.rootURL = rootURL
        self.manifestURL = manifestURL
        self.stages = stages
        self.bootstrapReport = bootstrapReport
    }

    public func bootstrap() -> GoldenEyeStageBootstrapReport { bootstrapReport }

    public static func load(stageAssetRoot rootURL: URL) throws -> Self {
        let manifestURL = rootURL.appendingPathComponent(manifestFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw GoldenEyeStageAssetCatalogError.missingManifest
        }

        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        } catch {
            throw GoldenEyeStageAssetCatalogError.malformedManifest(String(describing: error))
        }
        let manifest = try Manifest.parse(manifestData)
        try manifest.validateGuards()

        let expectedStages = try cCatalog()
        var expectedResources: [String: CResourceMetadata] = [:]
        for stage in expectedStages {
            for resource in stage.resources {
                expectedResources[key(stageID: resource.stageID, kind: resource.kind)] = resource
            }
        }
        guard expectedResources.count == expectedResourceCount else {
            throw GoldenEyeStageAssetCatalogError.catalogMismatch(
                "C catalog exposed \(expectedResources.count) resources, expected \(expectedResourceCount)"
            )
        }

        var seen: Set<String> = []
        var rowsByStage: [UInt32: [GoldenEyeStageAssetResource]] = [:]
        var resourceDigests: [String: (source: UInt64, decoded: UInt64, stage: UInt64)] = [:]
        for row in manifest.resources {
            guard let kind = GoldenEyeStageAssetKind(rawValue: row.kind) else {
                throw GoldenEyeStageAssetCatalogError.malformedManifest("unknown resource kind \(row.kind)")
            }
            let resourceKey = key(stageName: row.stageName, kind: kind, resourceName: row.resourceName)
            guard !seen.contains(resourceKey) else {
                throw GoldenEyeStageAssetCatalogError.malformedManifest("duplicate resource \(resourceKey)")
            }
            seen.insert(resourceKey)

            guard let expectedStage = expectedStages.first(where: { $0.stageName == row.stageName }),
                  let expected = expectedStage.resources.first(where: {
                      $0.kind == kind && $0.resourceName == row.resourceName
                  }) else {
                throw GoldenEyeStageAssetCatalogError.catalogMismatch(resourceKey)
            }
            guard expected.sourceOffset == row.sourceOffset,
                  expected.sourceBytes == row.sourceBytes,
                  expected.decodedBytes == row.decodedBytes,
                  expected.compressed1172 == row.compressed1172 else {
                throw GoldenEyeStageAssetCatalogError.catalogMismatch(
                    "metadata differs for \(resourceKey)"
                )
            }
            guard expectedResources[key(stageID: expected.stageID, kind: kind)] != nil else {
                throw GoldenEyeStageAssetCatalogError.catalogMismatch(resourceKey)
            }

            let safeStageName = row.stageName.replacingOccurrences(of: " ", with: "_")
            let safeName = "\(safeStageName)__\(row.kind)__\(row.resourceName)"
            let directoryURL = rootURL.appendingPathComponent(kind.directoryName, isDirectory: true)
            let sourceURL: URL
            let decodedURL: URL
            if row.compressed1172 {
                sourceURL = directoryURL.appendingPathComponent("\(safeName).rz", isDirectory: false)
                decodedURL = directoryURL.appendingPathComponent("\(safeName).bin", isDirectory: false)
            } else {
                sourceURL = directoryURL.appendingPathComponent("\(safeName).bin", isDirectory: false)
                decodedURL = sourceURL
            }
            let sourceData = try boundedData(at: sourceURL, expectedBytes: row.sourceBytes, name: resourceKey)
            let decodedData = try boundedData(at: decodedURL, expectedBytes: row.decodedBytes, name: resourceKey)
            try validateDigest(sourceData, expected: row.sourceSHA256, name: resourceKey, kind: "source")
            try validateDigest(decodedData, expected: row.decodedSHA256, name: resourceKey, kind: "decoded")

            var cResource = expected.cValue
            let cStatus = sourceData.withUnsafeBytes { rawBytes -> UInt32 in
                guard let baseAddress = rawBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return UInt32(GE_STATUS_INVALID_ARGUMENT)
                }
                var view = GEStageAssetViewV5()
                return UInt32(ge_stage_v5_validate_asset(
                    &cResource,
                    baseAddress,
                    UInt32(sourceData.count),
                    &view
                ))
            }
            guard cStatus == UInt32(GE_STATUS_OK) else {
                throw GoldenEyeStageAssetCatalogError.assetStatus(resourceKey, cStatus)
            }

            let checkedDecoded: Data
            if row.compressed1172 {
                checkedDecoded = try decode1172(
                    sourceData,
                    expectedBytes: Int(row.decodedBytes),
                    name: resourceKey
                )
            } else {
                checkedDecoded = sourceData
            }
            guard checkedDecoded == decodedData else {
                throw GoldenEyeStageAssetCatalogError.decodedMismatch(resourceKey)
            }

            let resource = GoldenEyeStageAssetResource(
                stageID: expected.stageID,
                stageName: row.stageName,
                kind: kind,
                resourceName: row.resourceName,
                assetHandle: expected.assetHandle,
                sourceOffset: row.sourceOffset,
                sourceBytes: row.sourceBytes,
                decodedBytes: row.decodedBytes,
                compressed1172: row.compressed1172,
                sourceSHA256: row.sourceSHA256,
                decodedSHA256: row.decodedSHA256,
                sourceURL: sourceURL,
                decodedURL: decodedURL
            )
            rowsByStage[expected.stageID, default: []].append(resource)

            var sourceHash = StageHash.offsetBasis
            var decodedHash = StageHash.offsetBasis
            StageHash.append(data: sourceData, to: &sourceHash)
            StageHash.append(data: decodedData, to: &decodedHash)
            var stageHash = StageHash.offsetBasis
            StageHash.append(word: expected.stageID, to: &stageHash)
            StageHash.append(word: expected.assetHandle, to: &stageHash)
            StageHash.append(word: row.sourceOffset, to: &stageHash)
            StageHash.append(word: row.sourceBytes, to: &stageHash)
            StageHash.append(word: row.decodedBytes, to: &stageHash)
            StageHash.append(word: kind.cKind, to: &stageHash)
            StageHash.append(word: sourceHash, to: &stageHash)
            StageHash.append(word: decodedHash, to: &stageHash)
            resourceDigests[resourceKey] = (sourceHash, decodedHash, stageHash)
        }

        guard seen.count == expectedResourceCount,
              manifest.resources.count == expectedResourceCount else {
            throw GoldenEyeStageAssetCatalogError.malformedManifest(
                "resource count is \(seen.count), expected \(expectedResourceCount)"
            )
        }

        var completeStages: [GoldenEyeStageAssetStage] = []
        completeStages.reserveCapacity(expectedStages.count)
        var finalStageReports: [GoldenEyeStageBootstrapStage] = []
        finalStageReports.reserveCapacity(expectedStages.count)
        var catalogHash = StageHash.offsetBasis
        for expectedStage in expectedStages {
            let resources = (rowsByStage[expectedStage.stageID] ?? []).sorted {
                $0.kind.cKind < $1.kind.cKind
            }
            guard resources.count == GE_STAGE_V5_RESOURCE_COUNT else {
                throw GoldenEyeStageAssetCatalogError.catalogMismatch(
                    "stage \(expectedStage.stageName) has \(resources.count) resources"
                )
            }
            completeStages.append(
                GoldenEyeStageAssetStage(
                    stageID: expectedStage.stageID,
                    stageName: expectedStage.stageName,
                    demoMask: expectedStage.demoMask,
                    resources: resources
                )
            )
            var sourceHash = StageHash.offsetBasis
            var decodedHash = StageHash.offsetBasis
            var stageHash = StageHash.offsetBasis
            StageHash.append(word: expectedStage.stageID, to: &stageHash)
            StageHash.append(word: expectedStage.demoMask, to: &stageHash)
            for resource in resources {
                let digestKey = key(
                    stageName: expectedStage.stageName,
                    kind: resource.kind,
                    resourceName: resource.resourceName
                )
                guard let digest = resourceDigests[digestKey] else {
                    throw GoldenEyeStageAssetCatalogError.catalogMismatch(
                        "missing deterministic hash for \(resource.resourceName)"
                    )
                }
                StageHash.append(word: digest.source, to: &sourceHash)
                StageHash.append(word: digest.decoded, to: &decodedHash)
                StageHash.append(word: digest.stage, to: &stageHash)
            }
            let final = GoldenEyeStageBootstrapStage(
                stageID: expectedStage.stageID,
                stageName: expectedStage.stageName,
                resourceCount: UInt32(resources.count),
                sourceHash: sourceHash,
                decodedHash: decodedHash,
                stageHash: stageHash
            )
            finalStageReports.append(final)
            StageHash.append(word: final.stageHash, to: &catalogHash)
        }

        let gameplayStub = try stubReport(milestone: UInt32(GE_STAGE_V5_STUB_M26), stageID: expectedStages[0].stageID)
        let rendererStub = try stubReport(milestone: UInt32(GE_STAGE_V5_STUB_M27), stageID: expectedStages[0].stageID)
        let report = GoldenEyeStageBootstrapReport(
            stages: finalStageReports,
            catalogHash: catalogHash,
            gameplayStub: gameplayStub,
            rendererStub: rendererStub
        )
        return Self(rootURL: rootURL, manifestURL: manifestURL, stages: completeStages, bootstrapReport: report)
    }

    public static func fromEnvironment() -> Result<Self, Error> {
        let environment = ProcessInfo.processInfo.environment
        let root: String?
        if let explicit = environment["GOLDENEYE_NATIVE_STAGE_ASSET_ROOT"], !explicit.isEmpty {
            root = explicit
        } else if let bootRoot = environment["GOLDENEYE_NATIVE_ASSET_ROOT"], !bootRoot.isEmpty {
            root = URL(fileURLWithPath: bootRoot, isDirectory: true)
                .deletingLastPathComponent()
                .appendingPathComponent("stage-assets", isDirectory: true)
                .path
        } else {
            root = nil
        }
        guard let root else {
            return .failure(GoldenEyeStageAssetCatalogError.missingManifest)
        }
        do {
            return .success(try load(stageAssetRoot: URL(fileURLWithPath: root, isDirectory: true)))
        } catch {
            return .failure(error)
        }
    }

    private struct ManifestResource: Sendable, Equatable {
        let index: Int
        let stageName: String
        let kind: String
        let resourceName: String
        let stageID: UInt32
        let sourceOffset: UInt32
        let sourceBytes: UInt32
        let compressed1172: Bool
        let decodedBytes: UInt32
        let sourceSHA256: String
        let decodedSHA256: String
    }

    private struct Manifest: Sendable, Equatable {
        let values: [String: String]
        let resources: [ManifestResource]

        static func parse(_ data: Data) throws -> Self {
            guard let text = String(data: data, encoding: .utf8) else {
                throw GoldenEyeStageAssetCatalogError.malformedManifest("not UTF-8")
            }
            var values: [String: String] = [:]
            var resources: [ManifestResource] = []
            for (lineIndex, line) in text.split(whereSeparator: { $0.isNewline }).enumerated() {
                guard let separator = line.firstIndex(of: "=") else {
                    throw GoldenEyeStageAssetCatalogError.malformedManifest("line \(lineIndex + 1) has no equals sign")
                }
                let key = String(line[..<separator])
                let value = String(line[line.index(after: separator)...])
                guard !key.isEmpty else {
                    throw GoldenEyeStageAssetCatalogError.malformedManifest("line \(lineIndex + 1) has an empty key")
                }
                let resourceIndexSuffix = key.dropFirst("resource_".count)
                if key.hasPrefix("resource_") &&
                    !resourceIndexSuffix.isEmpty &&
                    resourceIndexSuffix.allSatisfy({ $0.isNumber }) {
                    let fields = value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                    guard fields.count == 9 else {
                        throw GoldenEyeStageAssetCatalogError.malformedManifest(
                            "resource row \(key) has \(fields.count) fields"
                        )
                    }
                    guard let sourceOffset = UInt32(fields[3]),
                          let sourceBytes = UInt32(fields[4]),
                          let compressed = UInt32(fields[5]),
                          let decodedBytes = UInt32(fields[6]),
                          compressed <= 1 else {
                        throw GoldenEyeStageAssetCatalogError.malformedManifest(
                            "resource row \(key) has invalid numeric fields"
                        )
                    }
                    resources.append(
                        ManifestResource(
                            index: Int(resourceIndexSuffix) ?? -1,
                            stageName: fields[0],
                            kind: fields[1],
                            resourceName: fields[2],
                            stageID: 0,
                            sourceOffset: sourceOffset,
                            sourceBytes: sourceBytes,
                            compressed1172: compressed == 1,
                            decodedBytes: decodedBytes,
                            sourceSHA256: fields[7].lowercased(),
                            decodedSHA256: fields[8].lowercased()
                        )
                    )
                } else {
                    values[key] = value
                }
            }
            return Self(values: values, resources: resources)
        }

        func validateGuards() throws {
            let required: [String: String] = [
                "manifest_version": "1",
                "asset_family": "ramrom_stage_resources",
                "external_rom_size": "12582912",
                "external_rom_sha1": "abe01e4aeb033b6c0836819f549c791b26cfde83",
                "linux_reference_command": "make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1",
                "linux_reference_hash_command": "sha1sum -c ge007.u.sha1",
                "rom_copied_into_checkout": "false",
                "rom_copied_into_bundle": "false",
                "private_payloads_copied_into_checkout": "false",
                "private_payloads_copied_into_bundle": "false",
                "resource_count": "21",
                "manifest_status": "PASS",
            ]
            for (key, expected) in required {
                guard values[key] == expected else {
                    throw GoldenEyeStageAssetCatalogError.manifestGuard(
                        "\(key)=\(values[key] ?? "<missing>") (expected \(expected))"
                    )
                }
            }
            guard resources.count == GoldenEyeStageAssetCatalog.expectedResourceCount else {
                throw GoldenEyeStageAssetCatalogError.manifestGuard(
                    "resource rows=\(resources.count) (expected \(GoldenEyeStageAssetCatalog.expectedResourceCount))"
                )
            }
            let indices = resources.map(\.index).sorted()
            guard indices == Array(0..<GoldenEyeStageAssetCatalog.expectedResourceCount) else {
                throw GoldenEyeStageAssetCatalogError.manifestGuard(
                    "resource row indices are not exactly 0..20"
                )
            }
            for resource in resources {
                guard resource.sourceSHA256.count == 64,
                      resource.decodedSHA256.count == 64,
                      resource.sourceSHA256.allSatisfy({ $0.isHexDigit }),
                      resource.decodedSHA256.allSatisfy({ $0.isHexDigit }) else {
                    throw GoldenEyeStageAssetCatalogError.manifestGuard(
                        "non-SHA-256 digest in \(resource.resourceName)"
                    )
                }
            }
        }
    }

    private struct CResourceMetadata {
        let cValue: GEStageResourceV5
        let stageID: UInt32
        let kind: GoldenEyeStageAssetKind
        let resourceName: String
        let assetHandle: UInt32
        let sourceOffset: UInt32
        let sourceBytes: UInt32
        let decodedBytes: UInt32
        let compressed1172: Bool
    }

    private struct CStageMetadata {
        let stageID: UInt32
        let stageName: String
        let demoMask: UInt32
        let resources: [CResourceMetadata]
    }

    private static func cCatalog() throws -> [CStageMetadata] {
        let count = ge_stage_v5_catalog_count()
        guard count == UInt32(GE_STAGE_V5_STAGE_COUNT) else {
            throw GoldenEyeStageAssetCatalogError.catalogStatus("count", count)
        }
        var stages: [CStageMetadata] = []
        stages.reserveCapacity(Int(count))
        for index in 0..<count {
            var entry = GEStageCatalogEntryV5()
            let status = UInt32(ge_stage_v5_catalog_entry(index, &entry))
            guard status == UInt32(GE_STATUS_OK) else {
                throw GoldenEyeStageAssetCatalogError.catalogStatus("entry \(index)", status)
            }
            let stageName = cString(&entry.stage_name, capacity: Int(GE_STAGE_V5_STAGE_NAME_BYTES))
            let cResources = [entry.background, entry.stan, entry.setup]
            var resources: [CResourceMetadata] = []
            resources.reserveCapacity(cResources.count)
            for (resourceIndex, resourceValue) in cResources.enumerated() {
                var resource = resourceValue
                guard let kind = GoldenEyeStageAssetKind.allCases.first(where: {
                    $0.cKind == resource.resource_kind
                }) else {
                    throw GoldenEyeStageAssetCatalogError.catalogMismatch(
                        "entry \(index) resource \(resourceIndex) has unknown kind"
                    )
                }
                let resourceName = cString(
                    &resource.resource_name,
                    capacity: Int(GE_STAGE_V5_RESOURCE_NAME_BYTES)
                )
                resources.append(
                    CResourceMetadata(
                        cValue: resource,
                        stageID: resource.stage_id,
                        kind: kind,
                        resourceName: resourceName,
                        assetHandle: resource.asset_handle,
                        sourceOffset: resource.source_offset,
                        sourceBytes: resource.source_bytes,
                        decodedBytes: resource.decoded_bytes,
                        compressed1172: resource.compression == UInt32(GE_STAGE_V5_COMPRESSION_1172)
                    )
                )
            }
            stages.append(
                CStageMetadata(
                    stageID: entry.stage_id,
                    stageName: stageName,
                    demoMask: entry.demo_mask,
                    resources: resources
                )
            )
        }
        return stages
    }

    private static func cString<T>(_ tuple: inout T, capacity: Int) -> String {
        withUnsafePointer(to: &tuple) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { cStringPointer in
                String(cString: cStringPointer)
            }
        }
    }

    private static func key(stageID: UInt32, kind: GoldenEyeStageAssetKind) -> String {
        "\(stageID):\(kind.rawValue)"
    }

    private static func key(stageName: String, kind: GoldenEyeStageAssetKind, resourceName: String) -> String {
        "\(stageName):\(kind.rawValue):\(resourceName)"
    }

    private static func boundedData(at url: URL, expectedBytes: UInt32, name: String) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw GoldenEyeStageAssetCatalogError.missingAsset(name)
        }
        guard expectedBytes <= UInt32(maxPreparedBytes) else {
            throw GoldenEyeStageAssetCatalogError.oversizedAsset(name)
        }
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= maxPreparedBytes, data.count == Int(expectedBytes) else {
                throw GoldenEyeStageAssetCatalogError.catalogMismatch(
                    "\(name) byte count \(data.count), expected \(expectedBytes)"
                )
            }
            return data
        } catch let error as GoldenEyeStageAssetCatalogError {
            throw error
        } catch {
            throw GoldenEyeStageAssetCatalogError.missingAsset("\(name): \(error)")
        }
    }

    private static func validateDigest(_ data: Data, expected: String, name: String, kind: String) throws {
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw GoldenEyeStageAssetCatalogError.digestMismatch(name, kind, "expected \(expected), got \(actual)")
        }
    }

    private static func decode1172(_ source: Data, expectedBytes: Int, name: String) throws -> Data {
        var info = GEStage1172InfoV5()
        let status = source.withUnsafeBytes { rawBytes -> UInt32 in
            guard let baseAddress = rawBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return UInt32(GE_STATUS_INVALID_ARGUMENT)
            }
            return UInt32(ge_stage_v5_read_1172(
                baseAddress,
                UInt32(source.count),
                UInt32(expectedBytes),
                &info
            ))
        }
        guard status == UInt32(GE_STATUS_OK) else {
            throw GoldenEyeStageAssetCatalogError.assetStatus(name, status)
        }
        let prefixBytes = Int(info.prefix_bytes)
        guard prefixBytes <= source.count else {
            throw GoldenEyeStageAssetCatalogError.assetStatus(name, UInt32(GE_STATUS_INVALID_SIZE))
        }
        var output = Data(count: expectedBytes)
        let payload = source.dropFirst(prefixBytes)
        let produced = output.withUnsafeMutableBytes { outputBytes -> Int in
            payload.withUnsafeBytes { inputBytes -> Int in
                guard let outputBase = outputBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let inputBase = inputBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return compression_decode_buffer(
                    outputBase,
                    outputBytes.count,
                    inputBase,
                    inputBytes.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard produced == expectedBytes else {
            throw GoldenEyeStageAssetCatalogError.decodeFailure(
                name,
                UInt32(clamping: produced),
                UInt32(expectedBytes)
            )
        }
        return output
    }

    private static func stubReport(milestone: UInt32, stageID: UInt32) throws -> GoldenEyeStageStubReport {
        var diagnostic = GEStageDiagnosticV5()
        let status = UInt32(ge_stage_v5_stub_status(milestone, stageID, 0, &diagnostic))
        guard status == UInt32(GE_STATUS_UNSUPPORTED_COMMAND) else {
            throw GoldenEyeStageAssetCatalogError.stubStatus(milestone, status)
        }
        let message = cString(&diagnostic.message, capacity: 96)
        return GoldenEyeStageStubReport(
            milestone: milestone,
            stageID: stageID,
            status: status,
            message: message
        )
    }
}

private enum StageHash {
    static let offsetBasis: UInt64 = 0xcbf29ce484222325
    static let prime: UInt64 = 0x100000001b3

    static func append(word: UInt32, to hash: inout UInt64) {
        var value = UInt64(word).littleEndian
        withUnsafeBytes(of: &value) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash &*= prime
            }
        }
    }

    static func append(word: UInt64, to hash: inout UInt64) {
        var value = word.littleEndian
        withUnsafeBytes(of: &value) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash &*= prime
            }
        }
    }

    static func append(data: Data, to hash: inout UInt64) {
        data.withUnsafeBytes { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash &*= prime
            }
        }
    }
}
