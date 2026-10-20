from pathlib import Path
import os, subprocess, sys, tempfile, unittest
from test_servers import wait_for_servers

ROOT=Path(__file__).resolve().parents[1]

class CoverageGateTests(unittest.TestCase):
    def testExitedFixtureFailsImmediatelyWithProcessReason(self):
        child=subprocess.Popen([sys.executable,'-c','raise SystemExit(7)'])
        child.wait(timeout=5)
        with self.assertRaisesRegex(RuntimeError,'exited with 7'):
            wait_for_servers([child],[18764],timeout=.1)
    def testXCTestObserverReportsAnActualSkippedTest(self):
        with tempfile.TemporaryDirectory(prefix='streamdrop-observer-') as temp:
            root=Path(temp);tests=root/'Tests/ObserverFixture';tests.mkdir(parents=True)
            (root/'Package.swift').write_text('// swift-tools-version: 5.9\nimport PackageDescription\nlet package=Package(name:"ObserverFixture",targets:[.testTarget(name:"ObserverFixture")])\n')
            (tests/'ReportingTestCase.swift').write_bytes((ROOT/'Tests/StreamDropTests/ReportingTestCase.swift').read_bytes())
            (tests/'SkippedTests.swift').write_text('import XCTest\nfinal class SkippedTests:ReportingTestCase {func testIntentionalSkip()throws{throw XCTSkip("report fixture")}}\n')
            report=root/'results.xml'
            result=subprocess.run(['swift','test'],cwd=root,env=dict(os.environ,STREAMDROP_XCTEST_REPORT=str(report)),capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            gate=subprocess.run([sys.executable,str(ROOT/'scripts/check-test-results.py'),str(report),'--strict'],capture_output=True,text=True)
            self.assertEqual(gate.returncode,1,gate.stdout+gate.stderr)
            self.assertIn('1 cases, 0 failed, 1 skipped',gate.stdout)
    def testSkippedCoverageIsReportedAndStrictlyRejected(self):
        with tempfile.TemporaryDirectory() as temp:
            report=Path(temp)/'tests.xml'
            report.write_text('<testsuites><testsuite><testcase name="real-download"><skipped/></testcase></testsuite></testsuites>')
            for strict,code in [(False,0),(True,1)]:
                result=subprocess.run([sys.executable,str(ROOT/'scripts/check-test-results.py'),str(report),*(['--strict'] if strict else [])],capture_output=True,text=True)
                self.assertEqual(result.returncode,code,result.stdout+result.stderr)
                self.assertIn('1 skipped',result.stdout)
    def testStrictRunnerRejectsMissingToolsBeforeStartingFixtures(self):
        result=subprocess.run([sys.executable,str(ROOT/'scripts/test.py'),'--require-tools'],env=dict(os.environ,PATH=''),capture_output=True,text=True)
        self.assertEqual(result.returncode,1)
        self.assertIn('Missing required tools',result.stderr)
    def testEmptyCoverageCannotPass(self):
        with tempfile.TemporaryDirectory() as temp:
            report=Path(temp)/'tests.xml';report.write_text('<testsuites/>')
            result=subprocess.run([sys.executable,str(ROOT/'scripts/check-test-results.py'),str(report)],capture_output=True,text=True)
            self.assertEqual(result.returncode,1)

if __name__=='__main__':unittest.main()
