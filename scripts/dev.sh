#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
prepare_project() {
  python3 scripts/check-dependencies.py
  xcodegen generate
  mkdir -p TerminalKun2.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
  cp Package.resolved TerminalKun2.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
}
prepare_host_tool() {
  swift build --product SwiftTermBuildInfoGenerator --disable-automatic-resolution
  for configuration in Debug Release; do
    mkdir -p "$1/Build/Products/$configuration"
    cp .build/out/Products/Debug/SwiftTermBuildInfoGenerator "$1/Build/Products/$configuration/SwiftTermBuildInfoGenerator"
  done
}
case "${1:-test}" in
  resolve) swift package resolve 2>&1 | tee build/logs/resolve.log ;;
  generate) prepare_project ;;
  test) python3 scripts/check-dependencies.py; swift test --disable-automatic-resolution 2>&1 | tee build/logs/tests.log ;;
  build)
    prepare_project
    swift scripts/make-icon.swift Resources/AppIcon.svg Resources/Assets.xcassets/AppIcon.appiconset
    prepare_host_tool build/DerivedData
    xcodebuild -project TerminalKun2.xcodeproj -scheme TerminalKun2 -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO build 2>&1 | tee build/logs/build.log ;;
  device)
    prepare_project
    prepare_host_tool build/DeviceData
    xcodebuild -project TerminalKun2.xcodeproj -scheme TerminalKun2 -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DeviceData -clonedSourcePackagesDirPath build/SourcePackages -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build/logs/device.log ;;
  ui)
    prepare_project
    prepare_host_tool build/DerivedData
    xcodebuild -project TerminalKun2.xcodeproj -scheme TerminalKun2 -destination "platform=iOS Simulator,id=${2:-2BB24D00-0F02-4AAA-854F-D7EA1174178B}" -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages -skipPackagePluginValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO test 2>&1 | tee build/logs/ui-tests.log ;;
  *) echo 'Usage: scripts/dev.sh resolve|generate|test|build|device|ui'; exit 2 ;;
esac
