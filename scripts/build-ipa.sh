#!/bin/zsh
# Собирает HabitsOnReminders.ipa для установки через AltStore / SideStore
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

# Ad-hoc подпись ради entitlements: AltStore/SideStore берут их из подписи при переподписывании
# (App Group — общая база привычек и настроек у приложения и виджета).
APP=build/ipa/Payload/TripleToday.app
codesign --force --sign - --entitlements iOSWidget/Widget.entitlements "$APP/PlugIns/TripleTodayWidget.appex"
codesign --force --sign - --entitlements iOSApp/App.entitlements "$APP"
rm -f build/*.ipa
(cd build/ipa && zip -qry ../HabitsOnReminders.ipa Payload)
echo "build/HabitsOnReminders.ipa"
