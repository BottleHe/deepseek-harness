#!/usr/bin/env python3
"""Pre-seed the Desktop runtime download cache through fast regional mirrors.

Every asset is pinned by a SHA-256 digest in scripts/primary-runtime/lock.json, so
mirror-served bytes are rejected unless they match the lock exactly. Run this when
the direct sources (github.com, files.pythonhosted.org) are slow from your network:

    python3 apps/desktop/scripts/seed-runtime-download-cache.py linux-x64

Assets already present in the cache are skipped. Electron is not handled here;
export ELECTRON_MIRROR (for example https://mirrors.huaweicloud.com/electron/)
before packaging instead.
"""

import hashlib
import json
import os
import subprocess
import sys
from urllib.parse import quote

REPOSITORY = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
PYPI_MIRROR_PREFIX = "https://mirrors.aliyun.com/pypi/web/"
GITHUB_PROXY_PREFIX = "https://gh-proxy.com/"


def fetch(cache, url, sha256, mirror_url):
    dest = os.path.join(cache, sha256)
    if os.path.exists(dest):
        return
    for candidate in (mirror_url, url):
        if candidate is None:
            continue
        print("fetching:", candidate[:100], flush=True)
        subprocess.run(["curl", "-sL", "--retry", "3", "-o", dest + ".part", candidate], check=False)
        if os.path.exists(dest + ".part"):
            digest = hashlib.sha256(open(dest + ".part", "rb").read()).hexdigest()
            if digest == sha256:
                os.rename(dest + ".part", dest)
                return
            os.remove(dest + ".part")
            print("hash mismatch, trying next source", flush=True)
    sys.exit("FAILED to fetch with matching digest: " + url)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    target = sys.argv[1]
    lock = json.load(open(os.path.join(REPOSITORY, "scripts", "primary-runtime", "lock.json")))
    if target not in lock["targets"]:
        sys.exit(f"unknown target {target}; expected one of {', '.join(lock['targets'])}")
    cache = os.path.join(REPOSITORY, "apps", "desktop", ".desktop-build", "downloads")
    os.makedirs(cache, exist_ok=True)
    artifact = lock["targets"][target]

    python_name = (f"cpython-{lock['pythonVersion']}+{lock['pythonRelease']}"
        + f"-{artifact['pythonTarget']}-install_only_stripped.tar.gz")
    python_url = (f"https://github.com/astral-sh/python-build-standalone/releases/download/"
        + f"{lock['pythonRelease']}/{quote(python_name)}")
    fetch(cache, python_url, artifact["pythonSha256"], GITHUB_PROXY_PREFIX + python_url)

    for wheel in artifact.get("wheels", []) + lock.get("wheels", []):
        mirror = wheel["url"].replace("https://files.pythonhosted.org/", PYPI_MIRROR_PREFIX)
        fetch(cache, wheel["url"], wheel["sha256"], mirror)
    print("cache seeded for", target)


if __name__ == "__main__":
    main()
