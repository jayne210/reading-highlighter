"""Pack standard PNG icon representations into the macOS ICNS container."""
import struct
import sys
from pathlib import Path

source = Path(sys.argv[1])
types = {
    "icp4": "icon_16x16.png", "icp5": "icon_32x32.png",
    "ic07": "icon_128x128.png", "ic08": "icon_256x256.png",
    "ic09": "icon_512x512.png", "ic10": "icon_512x512@2x.png",
    "ic11": "icon_16x16@2x.png", "ic12": "icon_32x32@2x.png",
    "ic13": "icon_128x128@2x.png", "ic14": "icon_256x256@2x.png",
}
chunks = []
for kind, filename in types.items():
    data = (source / filename).read_bytes()
    assert data.startswith(b"\x89PNG\r\n\x1a\n"), filename
    chunks.append(kind.encode("ascii") + struct.pack(">I", len(data) + 8) + data)
body = b"".join(chunks)
Path(sys.argv[2]).write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
