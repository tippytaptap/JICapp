#!/usr/bin/env python3
"""Check local mobile release inputs without printing keys or contacting services."""
import argparse
import base64
import json
from pathlib import Path
import plistlib
import re
import sys
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]


def public_configuration(path):
    configuration = json.loads(path.read_text())
    allowed = {"SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "ENABLE_EXTENSIONS", "ENABLE_PUSH"}
    if not isinstance(configuration, dict) or set(configuration) != allowed:
        raise ValueError("Build configuration must contain only the four public keys in config/example.json.")
    url = urlsplit(configuration["SUPABASE_URL"])
    if url.scheme != "https" or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise ValueError("SUPABASE_URL must be the HTTPS API origin.")
    if url.path not in ("", "/"):
        raise ValueError("SUPABASE_URL must not contain an API path.")
    key = configuration["SUPABASE_PUBLISHABLE_KEY"]
    if not isinstance(key, str) or not key:
        raise ValueError("A public Supabase client key is required.")
    if not key.startswith("sb_publishable_"):
        try:
            parts = key.split(".")
            if len(parts) != 3:
                raise ValueError()
            payload = json.loads(base64.urlsafe_b64decode(parts[1] + "=" * (-len(parts[1]) % 4)))
            if payload.get("role") != "anon":
                raise ValueError()
        except (ValueError, TypeError, UnicodeDecodeError):
            raise ValueError("Only a publishable or legacy anon key can enter the app; server keys are forbidden.") from None
    for name in ("ENABLE_EXTENSIONS", "ENABLE_PUSH"):
        if type(configuration[name]) is not bool:
            raise ValueError(f"{name} must be a JSON boolean.")
    if configuration["ENABLE_PUSH"] and not configuration["ENABLE_EXTENSIONS"]:
        raise ValueError("Account push requires the workspace feature flag.")
    return configuration


def check_android(push, require_signing):
    failures = []
    phone = (ROOT / "android/app/build.gradle.kts").read_text()
    watch = (ROOT / "android/wear/build.gradle.kts").read_text()
    phone_id = re.search(r'applicationId\s*=\s*"([^\"]+)"', phone).group(1)
    watch_id = re.search(r'applicationId\s*=\s*"([^\"]+)"', watch).group(1)
    if phone_id != watch_id:
        failures.append("Android phone and Wear application IDs must match.")
    if 'signingConfig = signingConfigs.getByName("debug")' in phone:
        failures.append("The phone release build still uses a debug certificate.")
    if require_signing:
        source = ROOT / "android/key.properties"
        properties = {}
        if source.is_file():
            properties = dict(line.split("=", 1) for line in source.read_text().splitlines()
                              if "=" in line and not line.lstrip().startswith(("#", "!")))
            properties = {key.strip(): value.strip() for key, value in properties.items()}
        if not all(properties.get(key) for key in ("storeFile", "storePassword", "keyAlias", "keyPassword")):
            failures.append("Supply the four Android signing properties in ignored android/key.properties.")
        else:
            keystore = Path(properties["storeFile"])
            if not keystore.is_absolute():
                keystore = ROOT / "android" / keystore
            if not keystore.is_file():
                failures.append("The configured Android upload keystore is missing.")
    if push:
        config_file = ROOT / "android/app/google-services.json"
        if not config_file.is_file():
            failures.append("Android push needs android/app/google-services.json.")
        else:
            try:
                firebase = json.loads(config_file.read_text())
                clients = firebase.get("client", [])
                if not any(client.get("client_info", {}).get("android_client_info", {}).get("package_name") == phone_id for client in clients):
                    failures.append("Android Firebase configuration has no matching application ID.")
            except (ValueError, AttributeError):
                failures.append("Android Firebase configuration is invalid.")
    return failures


def check_ios(push, require_signing):
    failures = []
    project = (ROOT / "ios/Runner.xcodeproj/project.pbxproj").read_text()
    identifier = re.search(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", project).group(1).strip('"')
    watch = plistlib.loads((ROOT / "ios/CommunityWatch/Info.plist").read_bytes())
    if watch["WKCompanionAppBundleIdentifier"] != identifier:
        failures.append("Apple Watch companion bundle ID does not match Runner.")
    for target in ("Runner", "PrayerWidget", "CommunityWatch", "WatchWidgets"):
        info = plistlib.loads((ROOT / f"ios/{target}/Info.plist").read_bytes())
        if info.get("CFBundleVersion") != "$(FLUTTER_BUILD_NUMBER)" or info.get("CFBundleShortVersionString") != "$(FLUTTER_BUILD_NAME)":
            failures.append(f"{target} version must follow the phone build.")
    if require_signing and not re.search(r"DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}\s*;", project):
        failures.append("Select your Apple development team for all four targets in Xcode.")
    if push:
        firebase_path = ROOT / "ios/Runner/GoogleService-Info.plist"
        if not firebase_path.is_file():
            failures.append("iOS push needs ios/Runner/GoogleService-Info.plist.")
        else:
            try:
                if plistlib.loads(firebase_path.read_bytes()).get("BUNDLE_ID") != identifier:
                    failures.append("iOS Firebase configuration belongs to another bundle ID.")
            except (ValueError, plistlib.InvalidFileException):
                failures.append("iOS Firebase configuration is invalid.")
        entitlements = plistlib.loads((ROOT / "ios/Runner/Runner.entitlements").read_bytes())
        if "aps-environment" not in entitlements:
            failures.append("Enable Runner Push Notifications in Xcode and provision its APNs entitlement.")
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="config/local.json")
    parser.add_argument("--platform", choices=("android", "ios", "all"), default="all")
    parser.add_argument("--source-only", action="store_true", help="Check source/public config without requiring local signing credentials.")
    args = parser.parse_args()
    path = Path(args.config)
    if not path.is_absolute():
        path = ROOT / path
    try:
        config = public_configuration(path)
        failures = []
        if args.platform in ("android", "all"):
            failures.extend(check_android(config["ENABLE_PUSH"], not args.source_only))
        if args.platform in ("ios", "all"):
            failures.extend(check_ios(config["ENABLE_PUSH"], not args.source_only))
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        print("FAIL: Build configuration is missing or invalid. Use only the public fields from config/example.json; never include server keys.")
        return 1
    for failure in failures:
        print("FAIL:", failure)
    if failures:
        return 1
    print("Source checks passed." if args.source_only else "Local release inputs are present.")
    print("Workspace:", "enabled — verify deployed backend smoke tests" if config["ENABLE_EXTENSIONS"] else "disabled — public preview only")
    print("Remote push:", "enabled — physical delivery test required" if config["ENABLE_PUSH"] else "disabled; no Firebase/APNs inputs required")
    print("This does not verify credentials, store ownership, provisioning or delivery. Follow docs/MOBILE-RELEASE.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
