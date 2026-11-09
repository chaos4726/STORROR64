# undef_calls.py <file.lua>: names called as functions in a Lua file that it never defines (a local, a parameter, a
# loop variable) and that are not Lua's or UE4SS's globals - a deleted helper shows up here, which compiling misses
import re, sys

src = open(sys.argv[1], encoding='utf-8').read()
code = re.sub(r'--\[\[.*?\]\]', '', src, flags=re.S)
code = re.sub(r'--[^\n]*', '', code)
code = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', code)
code = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", code)

defined = set(re.findall(r'local\s+function\s+(\w+)', code))
for m in re.finditer(r'local\s+([\w\s,]+?)(?:=|\n)', code):
    for n in m.group(1).split(','):
        defined.add(n.strip())
for m in re.finditer(r'function\s*[\w.:]*\s*\(([^)]*)\)', code):
    for n in m.group(1).split(','):
        defined.add(n.strip())
for m in re.finditer(r'for\s+([\w\s,]+?)\s+(?:in|=)', code):
    for n in m.group(1).split(','):
        defined.add(n.strip())

builtins = set('''pcall xpcall ipairs pairs tostring tonumber type select error assert require print setmetatable
getmetatable rawget rawset rawequal next unpack load loadfile dofile collectgarbage StaticFindObject FName FText
FindFirstOf FindAllOf LoadAsset StaticConstructObject ExecuteWithDelay ExecuteInGameThread RegisterHook
NotifyOnNewObject RegisterKeyBind LoopAsync ExecuteAsync IsKeyBindRegistered'''.split())
keywords = set('if then else elseif end for while do return function local and or not in repeat until'.split())

called = set(re.findall(r'(?<![\w.:])([A-Za-z_]\w*)\s*\(', code))
missing = sorted(n for n in called if n not in defined and n not in builtins and n not in keywords)
print(sys.argv[1], 'undefined calls:', missing if missing else 'none')
