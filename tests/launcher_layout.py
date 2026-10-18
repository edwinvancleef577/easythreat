#!/usr/bin/env python3
"""Check the repository layout expected by OctoLauncher's direct Git install.

Run: python tests/launcher_layout.py
The launcher uses the last URL component as the folder name, then reads
<folder>/<folder>.toc. It does not search an extra addon subdirectory.
"""
from pathlib import Path
import re
import shutil
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def verify(root, addon):
    toc = root / (addon + ".toc")
    assert toc.is_file(), "Missing root TOC: " + str(toc)
    assert not (root / addon / (addon + ".toc")).exists(), "Nested addon copy"
    text = toc.read_text(encoding="utf-8-sig")
    metadata = dict(re.findall(r"^## ([^:]+):\s*(.*)$", text, re.M))
    for key in ("Interface", "Title", "Author", "Notes", "Version"):
        assert metadata.get(key, "").strip(), "Missing TOC metadata: " + key
    assert metadata["Author"].strip() == "VanCleef"
    count = 0
    for line in text.splitlines():
        entry = line.strip()
        if not entry or entry.startswith("#"):
            continue
        path = root / entry.replace("\\", "/")
        assert root.resolve() in path.resolve().parents, "TOC path escapes addon"
        assert path.is_file(), "Missing TOC dependency: " + entry
        count += 1
    # Bindings.xml is discovered by the game separately from the TOC.
    bindings = root / "Bindings.xml"
    if addon == "EasyCast":
        assert bindings.is_file(), "Missing keyboard bindings"
        assert ET.parse(bindings).getroot().tag == "Bindings"
    media = list((root / "Media").glob("*.tga"))
    assert media, "Artwork is not at the expected addon-relative path"
    return count, len(media)


def main():
    toc_files = list(ROOT.glob("*.toc"))
    assert len(toc_files) == 1, "Expected one TOC at repository root"
    addon = toc_files[0].stem
    # Preserve capitalization in the documented URL for case-sensitive systems.
    url = "https://github.com/edwinvancleef577/" + addon + ".git"
    assert url in (ROOT / "README.md").read_text(), "Missing canonical launcher URL"
    folder = url.removesuffix(".git").rsplit("/", 1)[-1]
    assert folder == addon
    count, assets = verify(ROOT, folder)
    with tempfile.TemporaryDirectory() as temp:
        installed = Path(temp) / "Interface" / "AddOns" / folder
        shutil.copytree(ROOT, installed, ignore=shutil.ignore_patterns(".git", "__pycache__"))
        assert verify(installed, folder) == (count, assets)
        # Prove the previous wrapped repository layout is rejected.
        wrapped = Path(temp) / "wrapped" / folder
        wrapped.mkdir(parents=True)
        shutil.copyfile(installed / (folder + ".toc"), wrapped / (folder + ".toc"))
        try:
            verify(wrapped.parent, folder)
        except AssertionError:
            pass
        else:
            raise AssertionError("Nested repository layout was incorrectly accepted")
    print("PASS: " + addon + " launcher layout, " + str(count) +
          " TOC files, " + str(assets) + " artwork files and nested-layout rejection")


if __name__ == "__main__":
    main()
