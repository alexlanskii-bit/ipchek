# Команды проекта IPCHEK. Список: `make help`.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

PROJECT := IPCHEK.xcodeproj
SCHEME := IPCHEK
DERIVED := build/DerivedData
PKG := Packages/IPCheckCore
FORMAT_PATHS := App $(PKG)/Sources $(PKG)/Tests $(PKG)/Package.swift scripts
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' -quiet

.PHONY: help project lint format test build build-release run install verify hooks icon clean

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

INSTALLED := /Applications/IPCHEK.app
RELEASE_APP := $(DERIVED)/Build/Products/Release/IPCHEK.app

INSTALLED_ID := com.lavmoviesstudio.ipchek

install: build-release ## Установить рабочую версию в «Программы», включить автозапуск и запустить
	@test -d "$(RELEASE_APP)" || { echo "Нет сборки $(RELEASE_APP)"; exit 1; }
	@# Закрываем штатно, как «Выйти», только рабочую версию: IPCHEK Dev живёт отдельно.
	@# Сначала копию под присмотром macOS (иначе launchd запустил бы её снова), потом остальные.
	@scripts/autostart.sh stop
	@scripts/stop-app.sh $(INSTALLED_ID)
	@rm -rf "$(INSTALLED)"
	@ditto "$(RELEASE_APP)" "$(INSTALLED)"
	@codesign --verify --strict "$(INSTALLED)"
	@# Файл автозапуска в ~/Library/LaunchAgents (решение владельца 2026-11-07) и запуск
	@# под присмотром macOS: при входе в систему и после сбоя IPCHEK запустится сам.
	@scripts/autostart.sh start
	@echo "✅ IPCHEK установлен в «Программы», автозапуск включён, IPCHEK запущен"

verify: lint test build build-release ## Все проверки: оформление, тесты, обе сборки
	@echo "✅ make verify: все проверки пройдены"

hooks: ## Включить проверку перед каждым коммитом
	@git config core.hooksPath scripts/git-hooks
	@echo "Проверка перед коммитом включена (scripts/git-hooks/pre-commit)"

icon: ## Перерисовать значок приложения (scripts/make-app-icon.swift)
	@xcrun --sdk macosx swift scripts/make-app-icon.swift App/Assets.xcassets/AppIcon.appiconset

clean: ## Удалить сборки и сгенерированный проект
	@rm -rf build $(PROJECT) $(PKG)/.build
