"""Swap <dir>/<name>.new in for <dir>/<name> as soon as the game lets go of the file. python swapwhenfree.py <dir> <name>... """
import os, sys, time
d, names = sys.argv[1], sys.argv[2:]
left = list(names)
end = time.time() + 3 * 3600
while left and time.time() < end:
    for n in list(left):
        try:
            os.replace(os.path.join(d, n + ".new"), os.path.join(d, n))
            print(time.strftime("%H:%M:%S"), "swapped in", n, flush=True)
            left.remove(n)
        except OSError:
            pass
    time.sleep(2)
print("left:", left, flush=True)
