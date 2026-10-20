import XCTest
import Darwin
@testable import StreamDrop

final class ToolHealthTests:ReportingTestCase {
    @MainActor func testShutdownWaitsForChecksAndRejectsLateChecks() async throws {
        let health=ToolHealth()
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:root)}
        let script=root.appendingPathComponent("probe"),pidFile=root.appendingPathComponent("pid")
        try "#!/bin/sh\n/bin/sleep 30 &\nprintf '%s' \"$!\" > '\(pidFile.path)'\nwait\n".write(to:script,atomically:true,encoding:.utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:script.path)
        let check=Task{await health.check(.ytDLP,configured:script.path,timeout:30)}
        let deadline=Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath:pidFile.path),Date()<deadline{try await Task.sleep(nanoseconds:10_000_000)}
        let pid=try XCTUnwrap(Int32(String(contentsOf:pidFile)))
        await health.shutdown()
        let result=await check.value
        XCTAssertFalse(result.usable)
        let drained=Date().addingTimeInterval(3)
        while kill(pid,0)==0,Date()<drained{try await Task.sleep(nanoseconds:10_000_000)}
        XCTAssertEqual(kill(pid,0),-1)
        let late=await health.check(.ytDLP,configured:script.path)
        XCTAssertFalse(late.usable)
        XCTAssertTrue(late.detail.contains("退出"))
    }
    func testInstalledToolsReturnVersions() async throws {
        for tool in MediaTool.allCases {
            guard ToolPaths.find("",name:tool.rawValue) != nil else{throw XCTSkip("media tool missing")}
            let result=await ToolHealth.shared.check(tool,configured:"")
            XCTAssertTrue(result.usable,result.detail)
            XCTAssertFalse(try XCTUnwrap(result.version).isEmpty)
        }
    }
    func testMissingAndFailingToolsHaveExplicitReasons() async {
        let missing=await ToolHealth.shared.check(.ytDLP,configured:"/no/such/streamdrop-tool")
        XCTAssertFalse(missing.usable);XCTAssertNil(missing.path)
        let failing=await ToolHealth.shared.check(.ffmpeg,configured:"/usr/bin/false")
        XCTAssertFalse(failing.usable);XCTAssertTrue(failing.detail.contains("退出失败"))
    }
    func testTimeoutAndCancellationDrainStubbornChild() async throws {
        for cancel in [false,true] {
            let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            defer{try? FileManager.default.removeItem(at:root)}
            let script=root.appendingPathComponent("probe"),pidFile=root.appendingPathComponent("pid")
            try "#!/bin/sh\ntrap '' INT TERM\n/bin/sleep 30 &\nprintf '%s' \"$!\" > '\(pidFile.path)'\nwait\n".write(to:script,atomically:true,encoding:.utf8)
            try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:script.path)
            let task=Task{await ToolHealth.shared.check(.ytDLP,configured:script.path,timeout:cancel ? 30 : 0.3)}
            let deadline=Date().addingTimeInterval(3)
            while !FileManager.default.fileExists(atPath:pidFile.path),Date()<deadline{try await Task.sleep(nanoseconds:10_000_000)}
            if cancel{task.cancel()}
            let result=await task.value
            XCTAssertFalse(result.usable)
            XCTAssertTrue(result.detail.contains(cancel ? "取消" : "超时"),result.detail)
            let pid=try XCTUnwrap(Int32(String(contentsOf:pidFile)))
            let drained=Date().addingTimeInterval(3)
            while kill(pid,0)==0,Date()<drained{try await Task.sleep(nanoseconds:10_000_000)}
            XCTAssertEqual(kill(pid,0),-1)
            XCTAssertEqual(errno,ESRCH)
        }
    }
    func testExecutableWithWrongVersionOutputIsNotHealthy() async throws {
        let result=await ToolHealth.shared.check(.ytDLP,configured:"/usr/bin/true")
        XCTAssertFalse(result.usable)
        XCTAssertEqual(result.path,"/usr/bin/true")
        XCTAssertNil(result.version)
        XCTAssertFalse(result.detail.isEmpty)
    }
}
