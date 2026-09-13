"""Export changed source for the authenticated GitHub connector. Never includes ignored files."""
import base64, json, pathlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[1]
files = subprocess.check_output(['git', 'ls-files', '-co', '--exclude-standard', '-z'], cwd=root).decode().split('\0')
result = []
for name in sorted(set(files) - {''}):
    path = root / name
    if not path.is_file():
        continue
    data = path.read_bytes()
    item = {'path': name, 'mode': '100755' if path.stat().st_mode & 0o111 else '100644', 'type': 'blob'}
    try:
        item['content'] = data.decode('utf8')
    except UnicodeDecodeError:
        item['base64'] = base64.b64encode(data).decode()
        item['sha'] = subprocess.check_output(['git', 'hash-object', name], cwd=root).decode().strip()
    result.append(item)
output = json.dumps(result, ensure_ascii=True)
if len(sys.argv) == 3:
    print(output[int(sys.argv[1]):int(sys.argv[2])], end='')
else:
    print(output, end='')
