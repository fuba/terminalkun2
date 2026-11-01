#!/usr/bin/env python3
"""Build and upload an internal TestFlight update using the signed-in Xcode account."""
import argparse
import contextlib
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
DISTRIBUTION = ROOT / 'build/Distribution'


class DistributionState:
    def __init__(self, directory):
        self.directory = directory
        self.path = directory / 'settings.json'

    def read(self):
        return json.loads(self.path.read_text()) if self.path.exists() else {}

    @contextlib.contextmanager
    def lock(self):
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.directory.chmod(0o700)
        with (self.directory / 'state.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            yield

    def save(self, state):
        descriptor, name = tempfile.mkstemp(dir=self.directory, prefix='settings-', suffix='.json')
        try:
            with os.fdopen(descriptor, 'w') as output:
                json.dump(state, output, indent=2)
                output.write('\n')
            os.replace(name, self.path)
        finally:
            if os.path.exists(name):
                os.unlink(name)

    def configure(self, team, bundle):
        if not re.fullmatch(r'[A-Z0-9]{10}', team):
            raise ValueError('Developer Team ID は英大文字・数字10文字で指定してください。')
        if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', bundle):
            raise ValueError('Bundle ID を確認してください。')
        with self.lock():
            state = self.read()
            if state and (state['teamID'] != team or state['bundleID'] != bundle):
                raise ValueError('更新先の Team / Bundle ID を変更できません。別アプリとしての登録を避けるため停止しました。')
            state.update(teamID=team, bundleID=bundle)
            self.save(state)

    def reserve_build(self):
        with self.lock():
            state = self.read()
            if not state.get('teamID') or not state.get('bundleID'):
                raise ValueError('先に configure --team <Team ID> を実行してください。')
            number = int(state.get('lastBuild', 0)) + 1
            if number > 9999:
                raise ValueError('ビルド番号が9999に達しました。バージョン番号を更新してください。')
            state['lastBuild'] = number
            self.save(state)
            return number

    def update(self, **values):
        with self.lock():
            state = self.read()
            state.update(values)
            self.save(state)


def export_options(team):
    return {'method': 'app-store-connect', 'destination': 'upload',
            'teamID': team, 'signingStyle': 'automatic',
            'manageAppVersionAndBuildNumber': True,
            'testFlightInternalTestingOnly': True, 'uploadSymbols': True}


def validate_archive(archive, team, bundle, number):
    app = archive / 'Products/Applications/TerminalKun2.app'
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    properties = plistlib.loads((archive / 'Info.plist').read_bytes()).get('ApplicationProperties', {})
    if info.get('CFBundleIdentifier') != bundle or info.get('CFBundleVersion') != str(number):
        raise ValueError('アーカイブの Bundle ID / ビルド番号が設定と一致しません。')
    if properties.get('Team') and properties.get('Team') != team:
        raise ValueError('アーカイブの Team が設定と一致しません。')
    return app


def archive_digest(archive):
    digest = hashlib.sha256()
    for path in sorted(archive.rglob('*')):
        relative = str(path.relative_to(archive))
        if path.is_symlink():
            entry = ['link', relative, os.readlink(path)]
        elif path.is_file():
            content = hashlib.sha256()
            with path.open('rb') as source:
                while chunk := source.read(1024 * 1024):
                    content.update(chunk)
            entry = ['file', relative, content.hexdigest()]
        else:
            continue
        digest.update(json.dumps(entry, ensure_ascii=True).encode() + b'\n')
    return digest.hexdigest()


def apple_tool_environment(original):
    environment = dict(original)
    system = ['/usr/bin', '/bin', '/usr/sbin', '/sbin']
    paths = system + [path for path in original.get('PATH', '').split(':') if path and path not in system]
    environment['PATH'] = ':'.join(paths)
    return environment


def validate_signing_metadata(entitlements, team, bundle, previous=None):
    identity = entitlements.get('application-identifier', '')
    if entitlements.get('com.apple.developer.team-identifier') != team or not re.fullmatch(r'[A-Z0-9]{10}\.' + re.escape(bundle), identity):
        raise ValueError('配布署名の Team / アプリ識別子が一致しません。')
    if entitlements.get('get-task-allow') is not False:
        raise ValueError('開発用の署名は TestFlight へ配信しません。')
    if previous and identity != previous:
        raise ValueError('既存のアプリ識別子 prefix が変わっています。更新を停止しました。')
    return identity


def run(arguments, log):
    print(f'Log: {log.relative_to(ROOT)}', flush=True)
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('a') as output:
        output.write('\n' + ' '.join(map(str, arguments)) + '\n')
        output.flush()
        result = subprocess.run(list(map(str, arguments)), cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                                env=apple_tool_environment(os.environ) if arguments[0] == 'xcodebuild' else None)
    if result.returncode:
        raise RuntimeError(f'処理に失敗しました。詳細: {log.relative_to(ROOT)}')


def archive_build(store):
    state = store.read()
    if not state.get('teamID'):
        raise ValueError('先に configure --team <Team ID> を実行してください。')
    number = store.reserve_build()
    derived = DISTRIBUTION / 'DerivedData'
    archive = DISTRIBUTION / 'Archives' / f'TerminalKun2-{number}.xcarchive'
    log = DISTRIBUTION / 'logs' / f'archive-{number}.log'
    run(['bash', 'scripts/dev.sh', 'prepare', derived], log)
    # Xcode archive actions use a separate products directory for host build tools.
    products = derived / 'Build/Intermediates.noindex/ArchiveIntermediates/TerminalKun2/BuildProductsPath/Release'
    products.mkdir(parents=True, exist_ok=True)
    host_tool = products / 'SwiftTermBuildInfoGenerator'
    if host_tool.is_symlink():
        host_tool.unlink()
    shutil.copy2(derived / 'Build/Products/Release/SwiftTermBuildInfoGenerator', host_tool)
    arguments = ['xcodebuild', '-project', 'TerminalKun2.xcodeproj', '-scheme', 'TerminalKun2',
                 '-configuration', 'Release', '-sdk', 'iphoneos', '-destination', 'generic/platform=iOS',
                 '-derivedDataPath', derived, '-archivePath', archive,
                 '-clonedSourcePackagesDirPath', ROOT / 'build/SourcePackages',
                 '-skipPackagePluginValidation', '-disableAutomaticPackageResolution',
                 '-onlyUsePackageVersionsFromResolvedFile', 'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES',
                 f'TERMINALKUN2_DEVELOPMENT_TEAM={state["teamID"]}', f'TERMINALKUN2_APP_BUNDLE_ID={state["bundleID"]}',
                 f'TERMINALKUN2_BUILD_NUMBER={number}', 'CODE_SIGN_STYLE=Automatic']
    arguments += ['CODE_SIGNING_ALLOWED=NO']
    run(arguments + ['archive'], log)
    validate_archive(archive, state['teamID'], state['bundleID'], number)
    store.update(lastArchive=str(archive.relative_to(ROOT)), archiveBuild=number)
    print(f'配布署名前のアーカイブ: {archive}')


def export_signed(store):
    state = store.read()
    if not state.get('lastArchive'):
        raise ValueError('先に archive を実行してください。')
    archive = (ROOT / state['lastArchive']).resolve()
    if not archive.is_relative_to(DISTRIBUTION.resolve()):
        raise ValueError('配信用アーカイブ領域の外は使用できません。')
    validate_archive(archive, state['teamID'], state['bundleID'], state['archiveBuild'])
    options = DISTRIBUTION / 'ExportOptions.plist'
    values = export_options(state['teamID'])
    values['destination'] = 'export'
    options.write_bytes(plistlib.dumps(values))
    export = DISTRIBUTION / 'Export' / str(state['archiveBuild'])
    run(['xcodebuild', '-exportArchive', '-archivePath', archive, '-exportPath', export,
         '-exportOptionsPlist', options, '-allowProvisioningUpdates'], DISTRIBUTION / f'logs/export-{state["archiveBuild"]}.log')
    packages = list(export.glob('*.ipa'))
    if len(packages) != 1:
        raise ValueError('配布用 IPA が一意に見つかりません。')
    verify = export / 'Verified'
    if verify.exists():
        shutil.rmtree(verify)
    run(['ditto', '-x', '-k', packages[0], verify], DISTRIBUTION / 'logs/verify.log')
    app = verify / 'Payload/TerminalKun2.app'
    run(['codesign', '--verify', '--deep', '--strict', app], DISTRIBUTION / 'logs/verify.log')
    result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)], capture_output=True, check=True)
    entitlements = plistlib.loads(result.stdout)
    identity = validate_signing_metadata(entitlements, state['teamID'], state['bundleID'], state.get('signedIdentity'))
    store.update(signedIdentity=identity, signedArchive=state['lastArchive'], signedIPA=str(packages[0].relative_to(ROOT)), verifiedArchiveDigest=archive_digest(archive))
    print(f'配布署名を検証した IPA: {packages[0]}')


def upload(store):
    state = store.read()
    if state.get('signedArchive') != state.get('lastArchive') or not state.get('signedIdentity'):
        raise ValueError('先に export でこのアーカイブの配布署名を検証してください。')
    archive = (ROOT / state['lastArchive']).resolve()
    if not archive.is_relative_to(DISTRIBUTION.resolve()):
        raise ValueError('配信用アーカイブ領域の外はアップロードできません。')
    validate_archive(archive, state['teamID'], state['bundleID'], state['archiveBuild'])
    if not state.get('verifiedArchiveDigest') or archive_digest(archive) != state['verifiedArchiveDigest']:
        raise ValueError('署名を検証した後でアーカイブが変更されています。export からやり直してください。')
    options = DISTRIBUTION / 'UploadOptions.plist'
    options.write_bytes(plistlib.dumps(export_options(state['teamID'])))
    run(['xcodebuild', '-exportArchive', '-archivePath', archive, '-exportPath', DISTRIBUTION / 'Upload',
         '-exportOptionsPlist', options, '-allowProvisioningUpdates'], DISTRIBUTION / f'logs/upload-{state["archiveBuild"]}.log')
    store.update(lastUpload=datetime.datetime.now(datetime.timezone.utc).isoformat(), uploadedArchive=state['lastArchive'])
    print('Apple へのアップロードが完了しました。App Store Connect で処理・配信状態を確認してください。')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    configure = commands.add_parser('configure')
    configure.add_argument('--team', required=True)
    configure.add_argument('--bundle', default='dev.fuba.terminalkun2')
    for name in ['status', 'archive', 'export', 'upload', 'update']:
        commands.add_parser(name)
    args = parser.parse_args()
    store = DistributionState(DISTRIBUTION)
    if args.command == 'configure':
        store.configure(args.team, args.bundle)
    elif args.command == 'status':
        print(json.dumps(store.read(), indent=2))
    else:
        # Serialize complete builds/uploads as well as individual state writes.
        DISTRIBUTION.mkdir(parents=True, exist_ok=True)
        with (DISTRIBUTION / 'distribution.lock').open('a') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError('別の配信処理が実行中です。先の処理の終了を待ってください。')
            if args.command in ['archive', 'update']:
                archive_build(store)
            if args.command in ['export', 'update']:
                export_signed(store)
            if args.command in ['upload', 'update']:
                upload(store)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
