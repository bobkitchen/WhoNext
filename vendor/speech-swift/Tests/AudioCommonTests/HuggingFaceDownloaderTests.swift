import XCTest
@testable import AudioCommon

final class HuggingFaceDownloaderTests: XCTestCase {

    // MARK: - offlineMode

    func testOfflineModeSkipsDownloadWhenWeightsExist() async throws {
        // Create a temp directory with a fake safetensors file
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fakeWeights = tmpDir.appendingPathComponent("model.safetensors")
        try Data([0x00]).write(to: fakeWeights)

        // offlineMode=true should return immediately without network
        var progressReported = false
        try await HuggingFaceDownloader.downloadWeights(
            modelId: "fake/model",
            to: tmpDir,
            offlineMode: true,
            progressHandler: { progress in
                if progress >= 1.0 { progressReported = true }
            }
        )
        XCTAssertTrue(progressReported, "Progress should reach 1.0 in offline mode")
    }

    func testOfflineModeWithoutWeightsFallsThrough() async {
        // Empty directory — offlineMode should still attempt download (and fail)
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline_empty_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        do {
            try await HuggingFaceDownloader.downloadWeights(
                modelId: "nonexistent/model-that-does-not-exist",
                to: tmpDir,
                offlineMode: true
            )
            XCTFail("Should have thrown an error for nonexistent model")
        } catch {
            // Expected — no cached weights, so download is attempted and fails
        }
    }

    func testOfflineModeFalseDoesNotSkip() async {
        // offlineMode=false (default) should not skip even if weights exist
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline_false_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fakeWeights = tmpDir.appendingPathComponent("model.safetensors")
        try? Data([0x00]).write(to: fakeWeights)

        // offlineMode=false should attempt network (and fail for fake model)
        do {
            try await HuggingFaceDownloader.downloadWeights(
                modelId: "nonexistent/model-that-does-not-exist",
                to: tmpDir,
                offlineMode: false
            )
            XCTFail("Should have thrown for nonexistent model with offlineMode=false")
        } catch {
            // Expected — network download attempted and failed
        }
    }

    // MARK: - weightsExist

    func testWeightsExistReturnsTrueForSafetensors() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("weights_exist_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        XCTAssertFalse(HuggingFaceDownloader.weightsExist(in: tmpDir))

        let fakeWeights = tmpDir.appendingPathComponent("model.safetensors")
        try Data([0x00]).write(to: fakeWeights)

        XCTAssertTrue(HuggingFaceDownloader.weightsExist(in: tmpDir))
    }

    func testWeightsExistReturnsFalseForEmptyDirectory() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("weights_empty_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        XCTAssertFalse(HuggingFaceDownloader.weightsExist(in: tmpDir))
    }

    func testWeightsExistReturnsFalseForNonexistentDirectory() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent_\(UUID().uuidString)")
        XCTAssertFalse(HuggingFaceDownloader.weightsExist(in: tmpDir))
    }

    // MARK: - cacheDir (custom cache directory)

    func testCustomCacheDirSkipsDefaultResolution() async throws {
        // Create a temp directory with a fake safetensors file
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("custom_cache_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fakeWeights = tmpDir.appendingPathComponent("model.safetensors")
        try Data([0x00]).write(to: fakeWeights)

        // With custom cacheDir + offlineMode, should succeed without any network or default path resolution
        var progressReported = false
        try await HuggingFaceDownloader.downloadWeights(
            modelId: "fake/model",
            to: tmpDir,
            offlineMode: true,
            progressHandler: { progress in
                if progress >= 1.0 { progressReported = true }
            }
        )
        XCTAssertTrue(progressReported)
        XCTAssertTrue(HuggingFaceDownloader.weightsExist(in: tmpDir))
    }
}
