import CryptoKit
import Foundation

public enum EnginePins {
    public static let main = "libsherpa-onnx-c-api.dylib"
    public static let runtime = "libonnxruntime.dylib"

    public static let arm64: [String: String] = [
        main: "ee098d8b419d49b92101cde3c970a333b361066eb2d79a11ab480a116552b908",
        runtime: "3567d114f7299d559993e536d605a6f46d7bc9d2542004accc80ee9bf5457f0b",
    ]
    public static let x64: [String: String] = [
        main: "d32eb199b94c076afef9cfc42e445c581c0326a72fb2cfdfdc177ebacf9bf38f",
        runtime: "2bf27180c09e6fd3f407c9ab25205ebf1ff95f2d53bfa35e35409b5849e0ac70",
    ]

    public static var current: [String: String] {
        #if arch(arm64)
        return arm64
        #else
        return x64
        #endif
    }

    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func check(_ files: [String: Data], pins: [String: String] = current) -> String? {
        for (name, want) in pins.sorted(by: { $0.key < $1.key }) {
            guard let data = files[name] else { return "\(name) is missing" }
            if digest(data) != want { return "\(name) doesn't match the version Sofia was built for; run the installer again" }
        }
        return nil
    }
}
