import json
from pathlib import Path


ROOT = Path(__file__).parents[2]


def test_release_manifest_matches_production_versions_and_downloads():
    manifest = json.loads((ROOT / "release" / "version.json").read_text())

    assert manifest["pc"]["version"] == "0.8.4"
    assert manifest["android"]["version"] == "0.8.10+21"
    assert manifest["pc"]["installer_url"].endswith("/ClipSyncPC_Setup.exe")
    assert manifest["pc"]["portable_url"].endswith("/ClipSyncPC.exe")
    assert manifest["android"]["url"].endswith("/ClipSync.apk")
