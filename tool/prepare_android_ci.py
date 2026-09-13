#!/usr/bin/env python3
"""Materialise release workflow inputs without logging secret values."""
import base64
import json
import os
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
PRIVATE_FILES = (
    "android/release-upload.jks",
    "android/key.properties",
    "android/app/google-services.json",
    "config/local.json",
)


def properties_value(value):
    # java.util.Properties uses ISO-8859-1 and backslash escapes.
    def unicode_escape(character):
        encoded = character.encode("utf-16-be")
        return "".join(f"\\u{int.from_bytes(encoded[index:index + 2], 'big'):04x}" for index in range(0, len(encoded), 2))

    return "".join(
        "\\\\" if character == "\\" else
        "\\n" if character == "\n" else
        "\\r" if character == "\r" else
        "\\t" if character == "\t" else
        "\\ " if character == " " else
        unicode_escape(character) if ord(character) > 126 else character
        for character in value
    )


def private_write(path, value):
    # Fresh files only in the ephemeral CI checkout.
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as target:
        target.write(value)


def prepare():
    number = os.environ.get("RELEASE_BUILD_NUMBER", "")
    if not re.fullmatch(r"[1-9][0-9]{0,5}", number):
        raise ValueError("Build number must be between 1 and 999999.")
    names = ("ANDROID_KEYSTORE_BASE64", "ANDROID_STORE_PASSWORD", "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD")
    if any(not os.environ.get(name) for name in names):
        raise ValueError("Add all four Android signing secrets in repository Actions settings.")
    configuration = json.loads((ROOT / "config/public.json").read_text())
    for flag in ("ENABLE_EXTENSIONS", "ENABLE_PUSH"):
        value = os.environ.get(flag, "false")
        if value not in ("true", "false"):
            raise ValueError("Feature inputs must be true or false.")
        configuration[flag] = value == "true"
    if configuration["ENABLE_PUSH"] and not configuration["ENABLE_EXTENSIONS"]:
        raise ValueError("Push requires the workspace feature.")
    if configuration["ENABLE_PUSH"] and not os.environ.get("GOOGLE_SERVICES_JSON_BASE64"):
        raise ValueError("Push requires GOOGLE_SERVICES_JSON_BASE64 in Actions secrets.")
    try:
        keystore = base64.b64decode(os.environ["ANDROID_KEYSTORE_BASE64"], validate=True)
        firebase = base64.b64decode(os.environ.get("GOOGLE_SERVICES_JSON_BASE64", ""), validate=True)
        if firebase:
            json.loads(firebase)
    except (ValueError, UnicodeDecodeError):
        raise ValueError("Signing or Firebase input is not valid base64/JSON.") from None
    if not keystore:
        raise ValueError("The upload keystore is empty.")
    signing = {
        "storeFile": str(ROOT / PRIVATE_FILES[0]),
        "storePassword": os.environ["ANDROID_STORE_PASSWORD"],
        "keyAlias": os.environ["ANDROID_KEY_ALIAS"],
        "keyPassword": os.environ["ANDROID_KEY_PASSWORD"],
    }
    private_write(ROOT / PRIVATE_FILES[0], keystore)
    private_write(ROOT / PRIVATE_FILES[1], "".join(f"{key}={properties_value(value)}\n" for key, value in signing.items()).encode("ascii"))
    private_write(ROOT / PRIVATE_FILES[3], (json.dumps(configuration, indent=2) + "\n").encode())
    if firebase:
        private_write(ROOT / PRIVATE_FILES[2], firebase)
    print("Release inputs prepared. No store upload has been performed.")


def main():
    if not os.environ.get("GITHUB_ACTIONS") == "true":
        print("This helper runs in GitHub Actions only; follow docs/MOBILE-RELEASE.md for local builds.")
        return 1
    if sys.argv[1:] == ["--clean"]:
        for name in PRIVATE_FILES:
            (ROOT / name).unlink(missing_ok=True)
        return 0
    try:
        prepare()
    except (OSError, ValueError, KeyError):
        print("Release input preparation failed. Check required signing secrets, base64 files, build number and feature flags. Secret values were not logged.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
