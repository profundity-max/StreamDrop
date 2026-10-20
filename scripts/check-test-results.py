"""Summarize XCTest xUnit output; strict mode rejects skipped/empty coverage."""
import argparse, sys
import xml.etree.ElementTree as ET
from pathlib import Path

def check(path,strict=False):
    root=ET.parse(path).getroot()
    cases=root.findall('.//testcase')
    if root.get('tests') is not None and int(root.get('tests'))!=len(cases):raise ValueError('Incomplete XCTest event coverage')
    skipped=[case for case in cases if case.find('skipped') is not None]
    failed=[case for case in cases if case.find('failure') is not None or case.find('error') is not None]
    print(f'XCTest coverage: {len(cases)} cases, {len(failed)} failed, {len(skipped)} skipped')
    for case in skipped:print('Skipped: '+case.get('classname','')+'.'+case.get('name',''))
    if not cases or failed or (strict and skipped):raise ValueError('Required XCTest coverage did not pass')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path',type=Path)
    parser.add_argument('--strict',action='store_true')
    args=parser.parse_args()
    try:check(args.path,args.strict)
    except (OSError,ValueError,ET.ParseError) as error:sys.exit(str(error))
