"""Exercise private release-file handling using disposable, synthetic inputs."""
import base64
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import prepare_android_ci as release


class ReleaseInputsTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "android/app").mkdir(parents=True)
        (self.root / "config").mkdir()
        (self.root / "config/public.json").write_text(json.dumps({
            "SUPABASE_URL": "https://test.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_fixture",
            "ENABLE_EXTENSIONS": False,
            "ENABLE_PUSH": False,
        }))
        self.environment = {
            "GITHUB_ACTIONS": "true",
            "RELEASE_BUILD_NUMBER": "8",
            "ANDROID_KEYSTORE_BASE64": base64.b64encode(b"synthetic-keystore").decode(),
            "ANDROID_STORE_PASSWORD": " sample\\password\n",
            "ANDROID_KEY_ALIAS": "upload",
            "ANDROID_KEY_PASSWORD": "synthetic",
            "ENABLE_EXTENSIONS": "true",
            "ENABLE_PUSH": "false",
        }
        self.addCleanup(patch.stopall)
        patch.object(release, "ROOT", self.root).start()
        patch.dict(os.environ, self.environment, clear=True).start()

    def test_private_files_and_public_flags(self):
        release.prepare()
        self.assertEqual((self.root / release.PRIVATE_FILES[0]).read_bytes(), b"synthetic-keystore")
        for name in (release.PRIVATE_FILES[0], release.PRIVATE_FILES[1], release.PRIVATE_FILES[3]):
            self.assertEqual((self.root / name).stat().st_mode & 0o777, 0o600)
        config = json.loads((self.root / "config/local.json").read_text())
        self.assertTrue(config["ENABLE_EXTENSIONS"])
        self.assertFalse(config["ENABLE_PUSH"])
        self.assertEqual(set(config), {"SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "ENABLE_EXTENSIONS", "ENABLE_PUSH"})
        self.assertFalse((self.root / "android/app/google-services.json").exists())
        with self.assertRaises(FileExistsError):
            release.prepare()

    def test_invalid_release_inputs_do_not_write_files(self):
        for key, value in (("RELEASE_BUILD_NUMBER", "2;echo unsafe"),
                           ("ANDROID_KEYSTORE_BASE64", "invalid!"),
                           ("ENABLE_PUSH", "true")):
            with self.subTest(key=key), patch.dict(os.environ, {key: value}):
                with self.assertRaises(ValueError):
                    release.prepare()
                self.assertFalse(any((self.root / name).exists() for name in release.PRIVATE_FILES))

    def test_java_properties_escaping_preserves_passwords(self):
        self.assertEqual(release.properties_value(" a\\b\n\t\r"), r"\ a\\b\n\t\r")
        self.assertEqual(release.properties_value("£😀"), r"\u00a3\ud83d\ude00")

    def test_cleanup_requires_ci_and_removes_only_generated_files(self):
        release.prepare()
        with patch.object(release.sys, "argv", ["helper", "--clean"]):
            with patch.dict(os.environ, {"GITHUB_ACTIONS": "false"}):
                self.assertEqual(release.main(), 1)
                self.assertTrue((self.root / "android/key.properties").exists())
            self.assertEqual(release.main(), 0)
        self.assertTrue((self.root / "config/public.json").exists())
        self.assertFalse(any((self.root / name).exists() for name in release.PRIVATE_FILES))


if __name__ == "__main__":
    unittest.main()
