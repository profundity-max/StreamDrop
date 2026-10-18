#!/usr/bin/env python3
"""Verify version metadata, every Excel history row, and optional built/tag state."""
from pathlib import Path
import argparse, datetime, json, plistlib, re, subprocess, sys, zipfile
import xml.etree.ElementTree as ET

def check(root, built=False, tag=False):
    version=(root/'VERSION').read_text().strip()
    build=int((root/'BUILD_NUMBER').read_text().strip())
    assert re.fullmatch(r'\d+\.\d+\.\d+',version), 'Invalid semantic version'
    history=json.loads((root/'docs/releases/history.json').read_text())
    latest=history['releases'][-1]
    assert history['currentVersion']==latest['version']==version, 'Version metadata drift'
    assert latest['build']==build and latest['ref']=='v'+version, 'Build/tag metadata drift'
    assert ('## '+version+' —') in (root/'CHANGELOG.md').read_text(), 'Missing changelog entry'
    ns={'m':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
    with zipfile.ZipFile(root/'docs/releases/StreamDrop-version-history.xlsx') as archive:
        names=archive.namelist()
        shared=[]
        if 'xl/sharedStrings.xml' in names:
            shared=[''.join(x.itertext()) for x in ET.fromstring(archive.read('xl/sharedStrings.xml')).findall('m:si',ns)]
        workbook=ET.fromstring(archive.read('xl/workbook.xml'))
        sheets=workbook.findall('m:sheets/m:sheet',ns)
        assert [x.get('name') for x in sheets]==['版本记录','发布明细'], 'Unexpected workbook sheets'
        def cells(index):
            result={}
            for c in ET.fromstring(archive.read(f'xl/worksheets/sheet{index}.xml')).findall('.//m:c',ns):
                value=c.find('m:v',ns)
                text='' if value is None else value.text or ''
                if c.get('t')=='s':text=shared[int(text)]
                elif c.get('t')=='inlineStr':text=''.join(c.find('m:is',ns).itertext())
                assert c.get('t')!='e',f'Excel cell error: {c.get("r")}'
                result[c.get('r')]=text
            return result
        table=cells(1)
        def link(ref):
            return f'{history["repository"]}/{"releases/tag" if ref.startswith("v") else "commit"}/{ref}' if ref else '无独立 Git 提交或标签'
        for row,release in enumerate(history['releases'],6):
            expected={'A':release['version'],'C':release['kind'],'D':release['status'],
                      'E':str(release['build']),'F':release['ref'] or '未独立提交',
                      'G':release['reason'],'H':release['summary'],'I':str(release['tests']),
                      'J':link(release['ref'])+'\n'+release['limitations']}
            for column,value in expected.items():assert table.get(f'{column}{row}')==value,f'Excel drift: {column}{row}'
            value=table[f'B{row}']
            date=datetime.datetime.fromisoformat(value.replace('Z','+00:00')) if 'T' in value else datetime.datetime(1899,12,30)+datetime.timedelta(days=float(value))
            assert date.date().isoformat()==release['date'],f'Excel date drift: B{row}'
        details=cells(2)
        for row,change in enumerate(history['changes'],6):
            for col,key in [('A','area'),('B','summary'),('C','verification'),('D','ref')]:
                assert details.get(f'{col}{row}')==change[key],f'Excel detail drift: {col}{row}'
            assert details.get(f'E{row}')==link(change['ref']),f'Excel source drift: E{row}'
    if built:
        info=plistlib.loads((root/'output/StreamDrop.app/Contents/Info.plist').read_bytes())
        assert info['CFBundleShortVersionString']==version and info['CFBundleVersion']==str(build),'Built App version drift'
    if tag:
        def git(*args):return subprocess.check_output(['git',*args],cwd=root,text=True).strip()
        assert git('rev-parse',f'refs/tags/v{version}^{{commit}}')==git('rev-parse','HEAD'),'Tag does not match release commit'
    print(f'Release records consistent: v{version}, build {build}, {len(history["releases"])} history rows, {len(history["changes"])} change rows')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
    parser.add_argument('--built',action='store_true')
    parser.add_argument('--tag',action='store_true')
    args=parser.parse_args()
    try:check(args.root,args.built,args.tag)
    except (AssertionError,KeyError,ValueError,OSError,ET.ParseError,zipfile.BadZipFile,subprocess.CalledProcessError) as error:
        print(f'Release check failed: {error}',file=sys.stderr);sys.exit(1)
