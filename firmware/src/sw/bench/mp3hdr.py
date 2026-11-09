import sys
# usage: mp3hdr.py <in.mp3> <name> <nbytes>  -> C array of the audio (ID3v2 stripped)
data = open(sys.argv[1], 'rb').read()
if data[:3] == b'ID3':
    sz = (data[6] << 21) | (data[7] << 14) | (data[8] << 7) | data[9]
    data = data[10 + sz:]
data = data[:int(sys.argv[3])]
name = sys.argv[2]
print(f"static const unsigned char {name}[{len(data)}] = {{")
for i in range(0, len(data), 16):
    print("  " + ", ".join(f"0x{b:02x}" for b in data[i:i+16]) + ",")
print("};")
