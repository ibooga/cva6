import io
import unittest
from pathlib import Path

from util.flist_flattener import parseFlist


class FlistFlattenerTest(unittest.TestCase):

    def test_nested_relative_include(self):
        with self.subTest("nested includes"):  # using subtest for clarity
            from tempfile import TemporaryDirectory

            with TemporaryDirectory() as tmpdir:
                tmp_path = Path(tmpdir)
                subdir = tmp_path / "dir" / "subdir"
                subdir.mkdir(parents=True)

                c_flist = subdir / "c.flist"
                c_flist.write_text("foo.v\n")

                b_flist = subdir.parent / "b.flist"
                b_flist.write_text("-F subdir/c.flist\n")

                a_flist = tmp_path / "a.flist"
                a_flist.write_text("-F dir/b.flist\n")

                out = io.StringIO()
                with a_flist.open() as f_in:
                    parseFlist(f_in, out, printIncdir=False, printNewline=True)

                self.assertEqual(out.getvalue(), "foo.v\n")


if __name__ == "__main__":
    unittest.main()
