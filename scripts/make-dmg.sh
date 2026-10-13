#!/bin/zsh
# Fabrique build/Chuchote-X.Y.Z.dmg et son checksum a partir de build/Chuchote.app.
# DMG habille : volume "Chuchote" (sans version), l'app et un lien Applications,
# fond .background/fond.png, icone de volume (.VolumeIcon.icns) et disposition du Finder
# (.DS_Store, copie de scripts/dmg/DS_Store, produit une fois par `make dmg-layout`).
# L'app reste a la racine du volume sous le nom Chuchote.app : l'Updater de VialetKit en depend.
#
# Usage : scripts/make-dmg.sh            DMG de distribution
#         scripts/make-dmg.sh --layout   regle la fenetre dans le Finder et enregistre scripts/dmg/DS_Store
#
# Fond : scripts/dmg/fond.png s'il existe (commite, utile en CI), sinon dessine par
# ../scripts/plaque.swift du depot vialetapps (VIALETAPPS_PATH pour un autre emplacement).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Chuchote"
VOLUME="Chuchote"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
APP="$ROOT/build/$APP_NAME.app"
DMG="$ROOT/build/$APP_NAME-$VERSION.dmg"
WORK="$ROOT/build/dmg-work"
STAGE="$WORK/stage"
RW="$WORK/rw.dmg"
DMG_DIR="$ROOT/scripts/dmg"
PLAQUE="${VIALETAPPS_PATH:-$ROOT/..}/scripts/plaque.swift"
LAYOUT=""
[ "${1:-}" = "--layout" ] && LAYOUT="oui"

[ -d "$APP" ] || { echo "build/$APP_NAME.app introuvable : lancez scripts/bundle.sh release" >&2; exit 1; }
BUILT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ "$BUILT" = "$VERSION" ] || { echo "$APP_NAME.app est en $BUILT, pas $VERSION : relancez bundle.sh" >&2; exit 1; }

DEVICE=""
MOUNT=""
cleanup() {
  if [ -n "$DEVICE" ]; then
    hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true
  elif [ -n "$MOUNT" ] && [ -d "$MOUNT" ]; then
    hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

# Monte l'image de travail (options en arguments) : pose DEVICE et MOUNT, echoue sans peripherique.
attach_rw() {
  local out
  out="$(hdiutil attach "$RW" -readwrite -noverify -noautoopen "$@")"
  MOUNT="$(printf '%s\n' "$out" | awk -F '\t' 'NF >= 3 && $NF ~ /^\// { m = $NF } END { print m }')"
  DEVICE="$(printf '%s\n' "$out" | awk '/^\/dev\// { print $1; exit }')"
  [ -n "$DEVICE" ] || { echo "peripherique de l'image de travail introuvable (montage : ${MOUNT:-aucun})" >&2; exit 1; }
  [ -n "$MOUNT" ] || { echo "point de montage de l'image de travail introuvable" >&2; exit 1; }
}

detach_rw() {
  hdiutil detach "$DEVICE" >/dev/null || { echo "detachement impossible : $DEVICE ($MOUNT)" >&2; exit 1; }
  DEVICE=""
  MOUNT=""
}

# Fond : scripts/dmg/fond.png (commite) ; en mode --layout ou s'il manque, redessine dans build/.
# En mode --layout, fond et DS_Store ne rejoignent scripts/dmg qu'une fois le DS_Store obtenu.
FOND=""
DRAWN="$ROOT/build/dmg-fond.png"
if [ -n "$LAYOUT" ] || [ ! -f "$DMG_DIR/fond.png" ]; then
  if [ -f "$PLAQUE" ]; then
    swift "$PLAQUE" dmg-bg "$ROOT/$APP_NAME/App/Brand.swift" "$DRAWN" >/dev/null
    FOND="$DRAWN"
  elif [ -n "$LAYOUT" ]; then
    echo "$PLAQUE introuvable : make dmg-layout dessine le fond (VIALETAPPS_PATH=<depot vialetapps>)" >&2
    exit 1
  else
    echo "attention : ni scripts/dmg/fond.png ni $PLAQUE : DMG sans fond" >&2
  fi
else
  FOND="$DMG_DIR/fond.png"
fi

rm -rf "$WORK" "$DMG" "$DMG.sha256"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
if [ -n "$FOND" ]; then
  mkdir -p "$STAGE/.background"
  cp "$FOND" "$STAGE/.background/fond.png"
fi
ICNS="$APP/Contents/Resources/AppIcon.icns"
[ -f "$ICNS" ] && cp "$ICNS" "$STAGE/.VolumeIcon.icns"
[ -z "$LAYOUT" ] && [ -f "$DMG_DIR/DS_Store" ] && cp "$DMG_DIR/DS_Store" "$STAGE/.DS_Store"

hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW" >/dev/null

if [ -n "$LAYOUT" ]; then
  # Volume visible dans /Volumes : le Finder doit l'ouvrir (autorisation Automation au premier lancement).
  attach_rw
  osascript "$DMG_DIR/layout.applescript" "$(basename "$MOUNT")" "$APP_NAME.app" || {
    echo "Le Finder n'a pas repondu en 30 s : autoriser le Terminal a piloter le Finder, voir scripts/dmg/README.md," >&2
    echo "puis relancer make dmg-layout." >&2
    exit 1
  }
  # Le Finder ecrit .DS_Store en differe.
  for i in {1..20}; do [ -f "$MOUNT/.DS_Store" ] && break; sleep 0.5; done
  [ -f "$MOUNT/.DS_Store" ] || { echo "le Finder n'a pas ecrit .DS_Store" >&2; exit 1; }
  sleep 1
  cp "$MOUNT/.DS_Store" "$WORK/DS_Store"
  detach_rw
  cp "$WORK/DS_Store" "$DMG_DIR/DS_Store"
  cp "$DRAWN" "$DMG_DIR/fond.png"
  echo "-> $DMG_DIR/DS_Store et $DMG_DIR/fond.png (a committer)"
  exit 0
fi

# Icone de volume : drapeau "icone personnalisee" sur la racine (SetFile, outils de developpement).
mkdir -p "$WORK/mnt"
attach_rw -nobrowse -mountpoint "$WORK/mnt"
if command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "$MOUNT"
else
  echo "attention : SetFile absent, icone de volume non activee" >&2
fi
sync
detach_rw

hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
hdiutil verify -quiet "$DMG"
(cd "$ROOT/build" && shasum -a 256 "$APP_NAME-$VERSION.dmg" > "$APP_NAME-$VERSION.dmg.sha256")
echo "-> $DMG"
cat "$DMG.sha256"
