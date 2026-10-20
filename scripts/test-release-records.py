"""Exercise the release gate in normal and optimized Python interpreters."""
from pathlib import Path
import json, shutil, subprocess, sys, tempfile, unittest

ROOT=Path(__file__).resolve().parents[1]

class ReleaseGateTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='streamdrop-release-check-')
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        for name in ['VERSION','BUILD_NUMBER','CHANGELOG.md','docs/releases/history.json','docs/releases/StreamDrop-version-history.xlsx']:
            target=self.root/name
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(ROOT/name,target)

    def gate(self,expected):
        for flags in [[],['-O']]:
            result=subprocess.run([sys.executable,*flags,str(ROOT/'scripts/check-release.py'),'--root',str(self.root)],capture_output=True,text=True)
            self.assertEqual(result.returncode,expected,result.stdout+result.stderr)

    def testCurrentRecordsPass(self):
        self.gate(0)

    def testVersionDriftIsRejectedWithOptimization(self):
        (self.root/'VERSION').write_text('9.9.9\n')
        self.gate(1)

    def testWorkbookNotesCannotDriftFromReleaseFacts(self):
        source=self.root/'docs/releases/history.json'
        data=json.loads(source.read_text())
        data['releases'][-1]['notes']=['A new limitation missing from the workbook']
        source.write_text(json.dumps(data))
        self.gate(1)

if __name__=='__main__':unittest.main()
