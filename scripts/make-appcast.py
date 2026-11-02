#!/usr/bin/env python3
"""Writes the Sparkle appcast of a release.

Usage: make-appcast.py <version> <build> <minimum macOS> <zip> <notes.md> <output.xml> [download URL]

Each release attaches its own appcast, so it only lists that release. The update is signed with
sign_update: the private key comes from the SPARKLE_PRIVATE_KEY environment variable or, without
it, from the local keychain. The key is never written to disk or passed as an argument.
"""

import glob
import os
import subprocess
import sys
from email.utils import formatdate
from xml.sax.saxutils import quoteattr

KEYCHAIN_ACCOUNT = "io.github.nxritsu.Halo"
REPOSITORY = os.environ.get("GITHUB_REPOSITORY", "NxRitsu/Halo")


def signature_attributes(archive):
    tools = glob.glob("build/release.noindex/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update")
    if not tools:
        sys.exit("sign_update not found: run scripts/build-release.sh first")
    key = os.environ.get("SPARKLE_PRIVATE_KEY")
    if key:
        command = [tools[0], "--ed-key-file", "-", archive]
    else:
        command = [tools[0], "--account", KEYCHAIN_ACCOUNT, archive]
    return subprocess.run(command, input=key, capture_output=True, text=True, check=True).stdout.strip()


def main():
    if len(sys.argv) not in (7, 8):
        sys.exit(__doc__)
    version, build, minimum_system, archive, notes_path, output = sys.argv[1:7]
    tag = f"v{version}"
    default_url = f"https://github.com/{REPOSITORY}/releases/download/{tag}/{os.path.basename(archive)}"
    url = sys.argv[7] if len(sys.argv) == 8 else default_url

    with open(notes_path, encoding="utf-8") as file:
        notes = file.read().replace("]]>", "]]]]><![CDATA[>")

    appcast = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Halo</title>
    <item>
      <title>{version}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{minimum_system}</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[{notes}]]></description>
      <enclosure url={quoteattr(url)} type="application/octet-stream" {signature_attributes(archive)}/>
    </item>
  </channel>
</rss>
"""
    with open(output, "w", encoding="utf-8") as file:
        file.write(appcast)


if __name__ == "__main__":
    main()
