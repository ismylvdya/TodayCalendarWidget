#!/bin/zsh
# Выпуск новой версии: ./scripts/release.sh 1.1 "Что нового" ["Что нового на Mac"]
# Ставит версию (номер сборки +1), собирает ipa для iPhone и dmg для Mac, добавляет версию
# в источник AltStore (altstore-source.json), коммитит, пушит и создаёт один GitHub Release
# с обоими файлами. Третий аргумент — заметки для Mac; без него dmg не собирается.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:?версия, например 1.1}
NOTES=${2:-"Version $VERSION"}
MAC_NOTES=${3:-}
REPO=ismylvdya/TodayCalendarWidget
IPA=build/HabitsOnReminders.ipa

BUILD=$(( $(sed -n 's/.*CURRENT_PROJECT_VERSION: "\([0-9]*\)".*/\1/p' project.yml) + 1 ))
sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/; s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$BUILD\"/" project.yml
./scripts/build-ipa.sh
ASSETS=($IPA)
if [ -n "$MAC_NOTES" ]; then ASSETS+=($(./scripts/build-dmg.sh | tail -1)); fi

python3 - "$VERSION" "$BUILD" "$NOTES" "$(stat -f %z $IPA)" "$REPO" <<'PY'
import json, sys, datetime
version, build, notes, size, repo = sys.argv[1:]
src = json.load(open("altstore-source.json"))
app = src["apps"][0]
app["versions"] = [v for v in app["versions"] if v["version"] != version]
app["versions"].insert(0, {
    "version": version, "buildVersion": build, "date": datetime.date.today().isoformat(),
    "localizedDescription": notes, "size": int(size), "minOSVersion": "18.0",
    "downloadURL": f"https://github.com/{repo}/releases/download/v{version}/HabitsOnReminders.ipa",
})
# Старые поля у самого приложения — для сборок AltStore, которые не читают список versions.
latest = app["versions"][0]
app.update({"version": latest["version"], "versionDate": latest["date"], "versionDescription": latest["localizedDescription"],
            "downloadURL": latest["downloadURL"], "size": latest["size"]})
json.dump(src, open("altstore-source.json", "w"), indent=2, ensure_ascii=False)
open("altstore-source.json", "a").write("\n")
PY

git add project.yml altstore-source.json
git commit -q -m "Release $VERSION"
git push -q origin HEAD
if [ -n "$MAC_NOTES" ]; then
    BODY="## iPhone — Habits (HabitsOnReminders.ipa)
Install or update through AltStore (the source updates by itself).

$NOTES

## Mac — Calendar Enhancer (CalendarEnhancer.dmg)
Open the dmg and drag Calendar Enhancer to Applications. The app is not notarized: the first time, right-click it → Open.

$MAC_NOTES"
else
    BODY="$NOTES"
fi
gh release create "v$VERSION" "${ASSETS[@]}" --repo "$REPO" --title "$VERSION" --notes "$BODY"
