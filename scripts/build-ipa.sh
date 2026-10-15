#!/bin/zsh
# Собирает неподписанный TripleToday.ipa для установки через AltStore / SideStore
# (они сами переподписывают приложение Apple ID пользователя).
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate -q
xcodebuild -project TodayCalendarWidget.xcodeproj -scheme TripleTodayiOS \
    -destination 'generic/platform=iOS' -configuration Release \
    -derivedDataPath build/DDios \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    build | grep -E "error|BUILD"

rm -rf build/ipa && mkdir -p build/ipa/Payload
cp -R build/DDios/Build/Products/Release-iphoneos/TripleToday.app build/ipa/Payload/
(cd build/ipa && zip -qry ../TripleToday.ipa Payload)
echo "build/TripleToday.ipa"
