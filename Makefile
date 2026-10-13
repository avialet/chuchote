SHELL := /bin/zsh
.SHELLFLAGS := -o pipefail -c
# VIALETKIT_PATH=../vialetkit : kit local, resolu en absolu pour l'app et pour le noyau.
ifdef VIALETKIT_PATH
export VIALETKIT_PATH := $(abspath $(VIALETKIT_PATH))
endif
APP := Chuchote
PROJECT := $(APP).xcodeproj
BUILD_DIR := $(CURDIR)/build
DERIVED := $(BUILD_DIR)/DerivedData
CORE := Packages/$(APP)Core
HAS_XCODE := $(shell xcodebuild -version >/dev/null 2>&1 && echo yes || echo no)

# Depot vialetapps (scripts/plaque.swift pour l'icone et le fond du DMG) : par defaut le dossier parent.
VIALETAPPS_PATH ?= $(abspath $(CURDIR)/..)
export VIALETAPPS_PATH
PLAQUE := $(VIALETAPPS_PATH)/scripts/plaque.swift

.PHONY: gen build xcode-build spm-build run install release dmg-layout test icon clean

# La version vit dans VERSION. Pour Xcode, on la recopie dans Version.xcconfig.
gen:
	printf 'MARKETING_VERSION = %s\n' "$$(tr -d '[:space:]' < VERSION)" > Version.xcconfig
	xcodegen generate

# Avec Xcode : build via xcodebuild. Sans : SwiftPM + assemblage du bundle.
build:
ifeq ($(HAS_XCODE),yes)
	$(MAKE) xcode-build
else
	$(MAKE) spm-build
endif

xcode-build: gen
	xcodebuild -project $(PROJECT) -scheme $(APP) -configuration Debug \
	  -derivedDataPath $(DERIVED) CODE_SIGN_IDENTITY="-" build | tail -20
	rm -rf $(BUILD_DIR)/$(APP).app
	cp -R $(DERIVED)/Build/Products/Debug/$(APP).app $(BUILD_DIR)/$(APP).app

spm-build:
	swift build --product $(APP) 2>&1 | grep -E "error|warning: var|Build"
	scripts/bundle.sh debug

run: build
	pkill -x $(APP) || true
	open $(BUILD_DIR)/$(APP).app

# Installe dans /Applications (emplacement stable pour le raccourci global,
# l'ouverture a la connexion et Spotlight), puis lance.
INSTALL_DIR := /Applications
install:
	swift build -c release --product $(APP) 2>&1 | grep -E "error|Build"
	scripts/bundle.sh release
	pkill -x $(APP) || true
	rm -rf $(INSTALL_DIR)/$(APP).app
	cp -R $(BUILD_DIR)/$(APP).app $(INSTALL_DIR)/$(APP).app
	open $(INSTALL_DIR)/$(APP).app

# Version distribuable : build/$(APP)-X.Y.Z.dmg + .sha256 (voir docs/publier-une-version.md).
release:
	swift build -c release --product $(APP) 2>&1 | grep -E "error|Build"
	scripts/bundle.sh release
	scripts/make-dmg.sh

# Disposition de la fenetre du DMG (Finder) : scripts/dmg/DS_Store et fond.png, a committer.
dmg-layout:
	swift build -c release --product $(APP) 2>&1 | grep -E "error|Build"
	scripts/bundle.sh release
	scripts/make-dmg.sh --layout

# Tests du noyau : fonctionne avec les seuls Command Line Tools.
test:
	cd $(CORE) && swift run chuchotecore-check $(FILTER)

# Icone : plaque de l'affiche (glyphe de Brand.swift, initiale s'il est vide), par scripts/plaque.swift.
icon:
	@[ -f "$(PLAQUE)" ] || { echo "plaque.swift introuvable : $(PLAQUE) (VIALETAPPS_PATH=<depot vialetapps>)" >&2; exit 1; }
	swift "$(PLAQUE)" iconset $(APP)/App/Brand.swift $(BUILD_DIR) >/dev/null
	iconutil -c icns $(BUILD_DIR)/AppIcon.iconset -o $(APP)/Resources/AppIcon.icns

clean:
	rm -rf $(BUILD_DIR) $(PROJECT) Version.xcconfig .build $(CORE)/.build
