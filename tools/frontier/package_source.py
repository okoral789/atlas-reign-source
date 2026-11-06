"""Package the current corresponding source, without secrets or historic place binaries.

Usage: python tools/frontier/package_source.py --rojo <executable> --key-file <local secret path>
The key is used only to assert it is absent from every archived file, and is never copied.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

ROOT=Path(__file__).resolve().parents[2]


def scripts(path):
    result={}
    def visit(node,parents):
        props=node.find('Properties');name=props.find("*[@name='Name']").text;here=parents+(name,)
        if node.get('class') in ['Script','LocalScript','ModuleScript']:
            result[here]=(node.get('class'),props.find("*[@name='Source']").text or '')
        for child in node.findall('Item'):visit(child,here)
    for child in ET.parse(path).getroot().findall('Item'):visit(child,())
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--rojo',type=Path,required=True);parser.add_argument('--key-file',type=Path,required=True);parser.add_argument('--version',default='0.4.1');parser.add_argument('--build',type=Path,default=ROOT/'build/Frontier-Custom-v0.4.1.rbxlx');args=parser.parse_args()
    assert args.version and all(c.isalnum() or c in '.-_' for c in args.version)
    prefix='Frontier-v'+args.version
    key=args.key_file.read_text(encoding='utf-8-sig').strip().encode()
    raw=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=ROOT)
    files=sorted({p.decode('utf-8') for p in raw.split(b'\0') if p})
    files=[p for p in files if (ROOT/p).is_file() and not p.startswith(('snapshots/','build/','.git/','.secrets/'))]
    assert all(not p.endswith(('.rbxl','.rbxlx')) and 'key_to_api' not in p.lower() and p!='.mcp.json' for p in files)
    assert all(p in files for p in ['LICENSE','NOTICE.md','release.project.json','licenses/CC0-1.0.txt'])
    archive=ROOT/'build'/f'{prefix}-Corresponding-Source.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for file in files:
            body=(ROOT/file).read_bytes()
            assert key not in body, 'Refusing to package a credential: '+file
            z.writestr(prefix+'/'+file,body)
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for file in files: assert z.read(prefix+'/'+file)==(ROOT/file).read_bytes(),file
        with tempfile.TemporaryDirectory(prefix='frontier-source-') as temporary:
            z.extractall(temporary)
            unpacked=Path(temporary)/prefix;rebuilt=Path(temporary)/'rebuilt.rbxlx'
            subprocess.run([str(args.rojo),'build','release.project.json','-o',str(rebuilt)],cwd=unpacked,check=True,capture_output=True)
            assert scripts(rebuilt)==scripts(args.build), 'Source archive does not rebuild deployed scripts'
    report={'archive':archive.name,'files':len(files),'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
            'rebuiltScriptsMatched':len(scripts(args.build)),'credentialAbsent':True}
    (ROOT/'build'/f'source-package-check-v{args.version}.json').write_text(json.dumps(report,indent=2)+'\n', encoding="utf-8", newline="\n")
    print(json.dumps(report))
