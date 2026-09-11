#!/usr/bin/env python3
"""
run_jsbeeb.py - open a disc image in jsbeeb (bbc.xania.org) on a Master,
autobooting. `make run EMU=jsbeeb`, and the fallback when `make run` finds
no emulator installed.

    python3 tools/run_jsbeeb.py build/paradroid.ssd           opens a browser
    python3 tools/run_jsbeeb.py --print build/paradroid.ssd   prints the URL

hexwab's recipe from issue #3: the disc travels INSIDE the URL, zipped and
base64'd, after the '#'. A fragment is never sent to the server, so its
length does not matter and nothing is uploaded anywhere. His shell version
needs `zip` and GNU `base64 -w0`; this needs only the python the build
already uses. Master because it has the four sideways RAM banks.
"""

import base64
import io
import os
import sys
import webbrowser
import zipfile

URL = 'https://bbc.xania.org/#model=Master&autoboot&disc=data:'


def disc_url(path):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
        z.write(path, os.path.basename(path))
    return URL + base64.b64encode(buf.getvalue()).decode('ascii')


def main():
    args = sys.argv[1:]
    show = '--print' in args
    if show:
        args.remove('--print')
    if len(args) != 1:
        raise SystemExit(__doc__)
    url = disc_url(args[0])
    if show:
        print(url)
    elif not webbrowser.open(url):
        raise SystemExit('run_jsbeeb: no browser to open; try --print')


if __name__ == '__main__':
    main()
