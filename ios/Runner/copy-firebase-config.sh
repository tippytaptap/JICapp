#!/bin/sh
set -eu

# Optional native defaults for Firebase.initializeApp(). The downloaded file is
# ignored by git. An unconfigured preview must not retain a previous build's file.
firebase_source="${SRCROOT}/Runner/GoogleService-Info.plist"
firebase_destination="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist"
if [ -f "$firebase_source" ]; then
    configured_bundle=$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$firebase_source")
    if [ "$configured_bundle" != "$PRODUCT_BUNDLE_IDENTIFIER" ]; then
        echo 'error: Firebase configuration belongs to a different iOS bundle identifier.' >&2
        exit 1
    fi
    mkdir -p "$(dirname "$firebase_destination")"
    cp "$firebase_source" "$firebase_destination"
else
    rm -f "$firebase_destination"
fi
