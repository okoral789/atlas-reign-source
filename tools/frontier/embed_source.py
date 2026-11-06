"""Attach a source archive to a copyable XML place without running game code."""

from base64 import b64encode
from hashlib import sha256
from pathlib import Path
import sys
from xml.etree import ElementTree as ET


EXTRACT = '''from base64 import b64decode
from hashlib import sha256
from pathlib import Path
import sys
from xml.etree import ElementTree as ET

parts = dict()
for item in ET.parse(sys.argv[1]).iter("Item"):
    if item.get("class") == "StringValue":
        props = item.find("Properties")
        name = props.findtext("string[@name='Name']", "")
        if name.startswith("AtlasSourceBlock"):
            index = int(name[len("AtlasSourceBlock"):])
            assert index not in parts, "Duplicate source block"
            parts[index] = b64decode(props.findtext("string[@name='Value']"), validate=True)
archive = b"".join(parts[index] for index in range(len(parts)))
assert sha256(archive).hexdigest() == {checksum!r}, "Source archive does not match"
Path({filename!r}).write_bytes(archive)
print("Source archive verified.")
'''


def add_item(parent, kind, name, value=None):
    item = ET.SubElement(parent, "Item", {"class": kind, "referent": "AtlasSource_" + name})
    props = ET.SubElement(item, "Properties")
    ET.SubElement(props, "string", {"name": "Name"}).text = name
    if value is not None:
        ET.SubElement(props, "string", {"name": "Value"}).text = value
    return item


if __name__ == "__main__":
    place, archive, output = map(Path, sys.argv[1:])
    assert place.resolve() != output.resolve()
    tree = ET.parse(place)
    root = tree.getroot()
    assert not any(name.text == "AtlasReignSource" for name in root.iterfind(".//string[@name='Name']"))
    storage = root.find("Item[@class='ServerStorage']")
    if storage is None:
        storage = add_item(root, "ServerStorage", "ServerStorage")
    folder = add_item(storage, "Folder", "AtlasReignSource")
    data = archive.read_bytes()
    checksum = sha256(data).hexdigest()
    add_item(folder, "StringValue", "Instructions",
             "Save the AtlasReignSource folder to a Roblox XML model file (.rbxmx), "
             "or save the whole place as a Roblox XML place (.rbxlx). "
             "Save the value of ExtractSourcePython as extract_source.py. "
             "Run python extract_source.py <your XML file>. "
             f"It will reconstruct and verify {archive.name}. SHA-256: {checksum}. "
             "See LICENSE and NOTICE.md in the resulting archive.")
    add_item(folder, "StringValue", "ExtractSourcePython",
             EXTRACT.format(checksum=checksum, filename=archive.name))
    block_size = 48 * 1024
    for index, start in enumerate(range(0, len(data), block_size)):
        add_item(folder, "StringValue", f"AtlasSourceBlock{index:04d}",
                 b64encode(data[start:start + block_size]).decode("ascii"))
    tree.write(output, encoding="utf-8", xml_declaration=False)
