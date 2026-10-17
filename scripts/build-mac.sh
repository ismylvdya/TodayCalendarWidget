#!/bin/zsh
# Собирает Calendar Enhancer.app (Release) и подписывает сертификатом Apple Development
# с entitlements (общая App Group приложения и виджета). Xcode сам подписать с App
# Group без профиля не даёт — поэтому сборка без подписи, подпись — здесь.
# Выводит путь к собранному .app.
set -euo pipefail
cd "$(dirname "$0")/.."

DD=${1:-build/DDmac}
APP="$DD/Build/Products/Release/Calendar Enhancer.app"
# Сертификат Apple Development (Team ID ML62XSB3UA — с него начинается App Group), иначе свой
# самоподписанный, иначе ad-hoc.
IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)
if [ -z "$IDENTITY" ]; then
    IDENTITY="Calendar Enhancer Signing"
    security find-identity -p codesigning | grep -q "$IDENTITY" || IDENTITY="-"
fi

xcodegen generate -q
xcodebuild -project TodayCalendarWidget.xcodeproj -scheme TodayCalendarWidget -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath $DD \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build | grep -E "error|BUILD" >&2

codesign --force --sign "$IDENTITY" --entitlements Widget/Widget.entitlements \
    "$APP/Contents/PlugIns/TodayCalendarWidgetExtension.appex"
codesign --force --sign "$IDENTITY" --entitlements App/App.entitlements "$APP"
echo "$APP"
