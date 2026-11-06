# Команды проекта IPCHEK. Список: `make help`.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

PROJECT := IPCHEK.xcodeproj
SCHEME := IPCHEK
DERIVED := build/DerivedData
PKG := Packages/IPCheckCore
FORMAT_PATHS := App $(PKG)/Sources $(PKG)/Tests $(PKG)/Package.swift scripts
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' -quiet

.PHONY: help project lint format test build build-release run verify hooks icon clean

help: ## Показать команды
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-14s %s\n", $$1, $$2}'

project: ## Сгенерировать проект Xcode из project.yml
	@command -v xcodegen >/dev/null || { echo "Нужен XcodeGen: brew install xcodegen"; exit 1; }
	@xcodegen generate --quiet

lint: ## Проверить оформление кода (swift-format)
	@xcrun swift-format lint --strict --recursive $(FORMAT_PATHS)

format: ## Исправить оформление кода (swift-format)
	@xcrun swift-format format --in-place --recursive $(FORMAT_PATHS)

test: ## Тесты логики (пакет IPCheckCore)
	@swift test --package-path $(PKG) --quiet

build: project ## Отладочная сборка (IPCHEK Dev)
	@$(XCODEBUILD) -configuration Debug build

build-release: project ## Финальная сборка (как будет установлена)
	@$(XCODEBUILD) -configuration Release build

run: build ## Собрать и запустить отладочную версию
	@open "$(DERIVED)/Build/Products/Debug/IPCHEK.app"

verify: lint test build build-release ## Все проверки: оформление, тесты, обе сборки
	@echo "✅ make verify: все проверки пройдены"

hooks: ## Включить проверку перед каждым коммитом
	@git config core.hooksPath scripts/git-hooks
	@echo "Проверка перед коммитом включена (scripts/git-hooks/pre-commit)"

icon: ## Перерисовать значок приложения (scripts/make-app-icon.swift)
	@xcrun --sdk macosx swift scripts/make-app-icon.swift App/Assets.xcassets/AppIcon.appiconset

clean: ## Удалить сборки и сгенерированный проект
	@rm -rf build $(PROJECT) $(PKG)/.build
