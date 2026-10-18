// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "StreamDrop", platforms: [.macOS(.v13)], products: [.executable(name: "StreamDrop", targets: ["StreamDrop"])], targets: [.executableTarget(name: "StreamDrop"), .testTarget(name: "StreamDropTests", dependencies: ["StreamDrop"])])
