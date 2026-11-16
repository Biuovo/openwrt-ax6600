#!/usr/bin/env python3
"""Exercise the actual ER1 image-preparation code, including layout guards."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PREP = (ROOT / 'Scripts/Prepare-ER1.sh').read_text()
CODE = PREP.split("<<'PY_ER1_IMAGE'\n", 1)[1].split('\nPY_ER1_IMAGE', 1)[0]
SOURCE = '''define Device/jdcloud_re-cs-02
\t$(call Device/FitImage)
\tKERNEL_SIZE := 6144k
endef

define Device/jdcloud_re-cs-07
\t$(call Device/FitImage)
\t$(call Device/EmmcImage)
\tKERNEL_SIZE := 6144k
\tIMAGE/factory.bin := append-kernel | pad-to $$(KERNEL_SIZE) | append-rootfs
endef

define Device/other
\tKERNEL_SIZE := 8192k
endef
'''

class KernelSizeTests(unittest.TestCase):
    def apply(self, text):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'ipq60xx.mk'
            path.write_text(text)
            result = subprocess.run([sys.executable, '-', str(path)], input=CODE,
                                    text=True, capture_output=True)
            return result.returncode, path.read_text()

    def test_only_er1_size_changes_and_repeated_run_is_safe(self):
        expected = SOURCE.replace('KERNEL_SIZE := 6144k', 'KERNEL_SIZE := 12288k', 2)
        # The other JDCloud board must retain its original size and FIT method.
        expected = expected.replace('KERNEL_SIZE := 12288k', 'KERNEL_SIZE := 6144k', 1)
        rc, actual = self.apply(SOURCE)
        self.assertEqual(rc, 0)
        self.assertEqual(actual, expected)
        rc, repeated = self.apply(actual)
        self.assertEqual(rc, 0)
        self.assertEqual(repeated, expected)
        self.assertLess(7750848, 12288 * 1024)

    def test_unknown_layout_fails_without_modifying_source(self):
        for text in [SOURCE.replace('re-cs-07', 're-cs-99'),
                     SOURCE.replace('6144k', '8192k'), SOURCE + SOURCE]:
            rc, actual = self.apply(text)
            self.assertNotEqual(rc, 0)
            self.assertEqual(actual, text)

if __name__ == '__main__':
    unittest.main()
