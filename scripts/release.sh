#!/bin/zsh
# Выпуск новой версии: ./scripts/release.sh 1.1 "Что нового"
# Ставит версию (номер сборки +1), собирает ipa, добавляет версию в источник AltStore
# (altstore-source.json), коммитит, пушит и создаёт GitHub Release с ipa.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:?версия, например 1.1}
NOTES=${2:-"Version $VERSION"}
REPO=ismylvdya/TodayCalendarWidget
IPA=build/HabitsOnReminders.ipa

BUILD=$(( $(sed -n 's/.*CURRENT_PROJECT_VERSION: "\([0-9]*\)".*/\1/p' project.yml) + 1 ))
sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/; s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$BUILD\"/" project.yml
./scripts/build-ipa.sh

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
json.dump(src, open("altstore-source.json", "w"), indent=2, ensure_ascii=False)
open("altstore-source.json", "a").write("\n")
PY

git add project.yml altstore-source.json
git commit -q -m "Release $VERSION"
git push -q origin HEAD
gh release create "v$VERSION" "$IPA" --repo "$REPO" --title "Habits on Reminders $VERSION" --notes "$NOTES"
