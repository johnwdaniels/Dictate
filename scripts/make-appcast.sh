#!/bin/bash
# Writes appcast.xml, the Sparkle feed that installed copies of Dictator check once a day.
#
# Usage: scripts/make-appcast.sh <zip> <tag> <build number> <repository URL> <sign_update> <EdDSA private key file>
# The feed lists one item, the release being published, and points at its zip on GitHub Releases.
set -euo pipefail

zip=$1
tag=$2
build=$3
repo_url=$4
sign_update=$5
key_file=$6

version=${tag#v}
# Prints: sparkle:edSignature="..." length="..."
signature=$("$sign_update" -f "$key_file" "$zip")
pub_date=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
minimum=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$(dirname "$zip")/Dictator.app/Contents/Info.plist" 2>/dev/null || echo "14.0")

cat > appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Dictator</title>
    <link>${repo_url}/releases</link>
    <item>
      <title>Dictator ${version}</title>
      <pubDate>${pub_date}</pubDate>
      <sparkle:version>${build}</sparkle:version>
      <sparkle:shortVersionString>${version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${minimum}</sparkle:minimumSystemVersion>
      <link>${repo_url}/releases/tag/${tag}</link>
      <enclosure url="${repo_url}/releases/download/${tag}/$(basename "$zip")" type="application/octet-stream" ${signature} />
    </item>
  </channel>
</rss>
XML
echo "Wrote appcast.xml for ${version} (build ${build})"
