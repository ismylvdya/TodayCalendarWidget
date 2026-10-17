#!/bin/zsh
# Собирает CalendarEnhancer.dmg для macOS: окно с приложением и ярлыком «Программы» —
# перетащить одно на другое. Подпись — своим сертификатом «Calendar Enhancer Signing»
# (если его нет в связке, сборка подпишется ad-hoc).
set -euo pipefail
cd "$(dirname "$0")/.."

DD=build/DDdmg
DMG=build/CalendarEnhancer.dmg
STAGE=build/dmg
APP=$(./scripts/build-mac.sh $DD | tail -1)

rm -rf $STAGE && mkdir -p $STAGE
ditto "$APP" "$STAGE/Calendar Enhancer.app"
ln -s /Applications "$STAGE/Applications"
rm -f $DMG
hdiutil create -volname "Calendar Enhancer" -srcfolder $STAGE -ov -format UDZO $DMG >/dev/null

# Собранная копия не должна оставаться в системе: второй экземпляр с тем же bundle ID
# путает виджеты (см. установку в ~/Applications).
LS=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
$LS -u "$PWD/$APP" 2>/dev/null || true
rm -rf $DD $STAGE
echo $DMG
