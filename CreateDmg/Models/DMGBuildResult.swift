import Foundation

struct DMGBuildResult: Sendable {
    let success: Bool
    let exitCode: Int32
    let log: String
    let outputURL: URL?
}
