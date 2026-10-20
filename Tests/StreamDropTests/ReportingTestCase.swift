import XCTest
import Foundation

/// Observe structured XCTest results rather than infer skips from console text.
class ReportingTestCase:XCTestCase {
    override class func setUp(){super.setUp();XCTestReport.install()}
}
private final class XCTestReport:NSObject,XCTestObservation {
    private static let shared=XCTestReport()
    private static let registration:Void=XCTestObservationCenter.shared.addTestObserver(shared)
    static func install(){_=registration}
    private let lock=NSLock()
    private var cases:[XMLElement]=[]
    private var expectedCount=0
    func testSuiteDidFinish(_ testSuite:XCTestSuite){
        lock.lock();expectedCount=max(expectedCount,testSuite.testRun?.executionCount ?? 0);lock.unlock()
    }
    func testCaseDidFinish(_ testCase:XCTestCase){
        guard let run=testCase.testRun else{return}
        let item=XMLElement(name:"testcase")
        item.addAttribute(XMLNode.attribute(withName:"name",stringValue:testCase.name) as! XMLNode)
        if run.skipCount>0{item.addChild(XMLElement(name:"skipped"))}
        if run.totalFailureCount>0{item.addChild(XMLElement(name:"failure",stringValue:"XCTest reported failure"))}
        lock.lock();cases.append(item);lock.unlock()
    }
    func testBundleDidFinish(_ testBundle:Bundle){
        guard let path=ProcessInfo.processInfo.environment["STREAMDROP_XCTEST_REPORT"] else{return}
        lock.lock();let items=cases;lock.unlock()
        let root=XMLElement(name:"testsuites"),suite=XMLElement(name:"testsuite")
        root.addAttribute(XMLNode.attribute(withName:"tests",stringValue:String(expectedCount)) as! XMLNode)
        items.forEach{suite.addChild($0)};root.addChild(suite)
        do{try XMLDocument(rootElement:root).xmlData().write(to:URL(fileURLWithPath:path),options:.atomic)}
        catch{fputs("Could not save XCTest report: \(error)\n",stderr)}
    }
}
