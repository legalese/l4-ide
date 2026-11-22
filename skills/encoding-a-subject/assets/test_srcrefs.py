#!/usr/bin/env python3
"""Tests for srcrefs.py.  Run:  python3 -I skills/encoding-a-subject/assets/test_srcrefs.py

Every fixture is built in a temporary directory inside the test; nothing outside it is read or written.
The text in the fixtures is invented for the tests.
"""
import contextlib
import importlib.util
import io
import os
import re
import subprocess
import sys
import tempfile
import unicodedata
import unittest

sys.dont_write_bytecode = True  # importing srcrefs.py must not leave a __pycache__ in the skill's assets
HERE = os.path.dirname(os.path.abspath(__file__))
SRCREFS = os.path.join(HERE, "srcrefs.py")
_spec = importlib.util.spec_from_file_location("srcrefs", SRCREFS)
srcrefs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(srcrefs)

# RAW is law.txt; amend.txt is a second raw file beside it, addressed as `src:amend:N`.
LAW = [
    "Điều 35. Thời gian cân nhắc tham gia bảo hiểm",  # 1
    "Đối với các hợp đồng bảo hiểm có thời hạn trên 01 năm, trong thời hạn 21",  # 2
    "ngày kể từ ngày nhận được hợp đồng bảo hiểm, bên mua bảo hiểm có quyền từ",  # 3
    "                                   Trang 12",  # 4  a page footer, never quoted
    "chối tiếp tục tham gia bảo hiểm.",  # 5
    "",  # 6
    "Điều 36. Hợp đồng bảo hiểm",  # 7
    "1. Hợp đồng bảo hiểm phải được lập thành văn bản.",  # 8
    "2. Hợp đồng bảo hiểm có hiệu lực từ ngày bên mua bảo hiểm đóng phí.",  # 9
]
AMEND = [
    "1. Bổ sung khoản 3 vào sau khoản 2 Điều 3 như sau:",  # 1
    "“3. Tổ chức, cá nhân có quyền tham gia góp vốn.”",  # 2
]


def squash(s):
    return re.sub(r"\s+", " ", s).strip()


def q(a, b=None):
    """A quote line for lines a..b of law.txt."""
    b = b or a
    text = squash(" ".join(LAW[a - 1 : b]))
    return f"-- src:{a} | {text}" if b == a else f"-- src:{a}-{b} | {text}"


def qa(a, b=None):
    """A quote line for lines a..b of amend.txt."""
    b = b or a
    text = squash(" ".join(AMEND[a - 1 : b]))
    return f"-- src:amend:{a} | {text}" if b == a else f"-- src:amend:{a}-{b} | {text}"


DECL = ["GIVEN x IS A Number", "DECIDE `thing` IS x"]


class Result:
    def __init__(self, status, out):
        self.status = status
        self.out = out
        lines = out.strip().split("\n")
        self.summary = lines[-1]
        self.problems = lines[:-1]
        m = re.match(r"srcrefs check: (\d+) src: lines, (\d+) runs, (\d+) locators, (\d+) problems$", self.summary)
        assert m, f"unexpected summary line: {self.summary!r}"
        self.nsrc, self.nruns, self.nlocs, self.nbad = map(int, m.groups())
        assert self.nbad == len(self.problems), out


class Base(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = tmp.name
        self.raw = self.write("law.txt", "\n".join(LAW) + "\n")
        self.write("amend.txt", "\n".join(AMEND) + "\n")
        self.nfiles = 0

    def write(self, name, text):
        path = os.path.join(self.dir, name)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        return path

    def enc(self, *lines):
        self.nfiles += 1
        return self.write(f"enc{self.nfiles}.l4", "\n".join(lines) + "\n")

    def run_check(self, *files, refs=False, raw=None):
        flags = ["--refs"] if refs else []
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            status = srcrefs.main(["check", *flags, raw or self.raw, *files])
        return Result(status, buf.getvalue())

    def check(self, *lines, refs=False):
        """Check one encoding file made of `lines`."""
        return self.run_check(self.enc(*lines), refs=refs)

    def assertClean(self, res):
        self.assertEqual((res.status, res.problems), (0, []), res.out)

    def assertProblem(self, res, ln, *fragments):
        """Exactly the problem(s) given as (ln, fragments...) must appear; use for the single-problem case."""
        self.assertEqual(res.status, 1, res.out)
        self.assertEqual(res.nbad, 1, res.out)
        self.assertRegex(res.problems[0], rf":{ln}: ")
        for fragment in fragments:
            self.assertIn(fragment, res.problems[0])


class TestR1(Base):
    def test_verbatim_single_line_and_range_accepted(self):
        self.assertClean(self.check(q(1), q(2, 3), q(5)))

    def test_every_blank_and_noise_line_is_not_a_quote(self):
        res = self.check("-- just a comment", "", *DECL)
        self.assertClean(res)
        self.assertEqual(res.nsrc, 0)

    def test_case_punctuation_and_whitespace_are_ignored(self):
        self.assertClean(self.check("-- src:1 |   ĐIỀU 35 -- thời gian   cân nhắc tham gia bảo hiểm!!"))

    def test_quote_may_start_or_end_inside_the_lines(self):
        self.assertClean(self.check("-- src:2-3 | hợp đồng bảo hiểm có thời hạn trên 01 năm, trong thời hạn 21 ngày kể từ"))

    def test_changed_word_rejected(self):
        res = self.check("-- src:1 | Điều 35. Thời gian cân nhắc tham gia bảo hiểm nhân thọ")
        self.assertProblem(res, 1, "src:1-1", "not a slice")

    def test_wrong_line_rejected(self):
        res = self.check("-- src:7 | Điều 35. Thời gian cân nhắc tham gia bảo hiểm")
        self.assertProblem(res, 1, "not a slice")

    def test_quote_range_must_contain_the_text_not_just_the_endpoints(self):
        # The footer on raw line 4 is inside src:2-5, so a quote that skips it is not a slice of src:2-5.
        res = self.check("-- src:2-5 | " + squash(LAW[1] + " " + LAW[4]))
        self.assertProblem(res, 1, "not a slice")

    def test_nfd_encoding_against_nfc_raw(self):
        nfd = unicodedata.normalize("NFD", LAW[0])
        self.assertNotEqual(nfd, LAW[0])
        self.assertClean(self.check(f"-- src:1 | {nfd}"))

    def test_nfc_encoding_against_nfd_raw(self):
        raw = self.write("nfd.txt", unicodedata.normalize("NFD", "\n".join(LAW)) + "\n")
        res = self.run_check(self.enc(q(1), q(2, 3)), raw=raw)
        self.assertClean(res)

    def test_trailing_ellipsis_unicode_and_ascii(self):
        self.assertClean(self.check("-- src:2 | Đối với các hợp đồng bảo hiểm…", "-- src:2 | Đối với các hợp đồng bảo hiểm ..."))

    def test_ellipsis_does_not_excuse_wrong_text(self):
        res = self.check("-- src:2 | Đối với các hợp đồng tái bảo hiểm…")
        self.assertProblem(res, 1, "not a slice")

    def test_ellipsis_in_the_middle_is_only_punctuation(self):
        # as in the gate this tool generalises: only a TRAILING ellipsis is special; elsewhere it is dropped like any punctuation,
        # so the words either side must still be contiguous in the source
        self.assertClean(self.check("-- src:2 | Đối với các … hợp đồng bảo hiểm"))
        res = self.check("-- src:2 | Đối với các … bảo hiểm")
        self.assertProblem(res, 1, "not a slice")

    def test_trailing_table_pipe_is_ignored(self):
        self.assertClean(self.check(q(1) + " |"))

    def test_id_qualified_marker_checked_against_that_file(self):
        self.assertClean(self.check(qa(1), qa(1, 2)))

    def test_id_qualified_marker_is_not_checked_against_raw(self):
        # LAW line 1 quoted under the amend ID: the text is not in amend.txt.
        res = self.check("-- src:amend:1 | " + LAW[0])
        self.assertProblem(res, 1, "src:amend:1-1", "not a slice")

    def test_plain_marker_is_not_checked_against_id_file(self):
        res = self.check("-- src:1 | " + AMEND[0])
        self.assertProblem(res, 1, "not a slice")

    def test_id_with_no_raw_file_is_a_problem(self):
        res = self.check("-- src:nosuch:3 | anything")
        self.assertProblem(res, 1, "names no raw file nosuch.txt")

    def test_n_greater_than_m(self):
        res = self.check("-- src:5-2 | " + LAW[1])
        self.assertProblem(res, 1, "N > M")

    def test_line_zero_does_not_wrap_around_to_the_last_line(self):
        res = self.check("-- src:0-3 | " + LAW[8])
        self.assertProblem(res, 1, "line numbers start at 1")

    def test_quote_past_the_end_of_the_raw_file(self):
        res = self.check("-- src:50 | " + LAW[0])
        self.assertProblem(res, 1, "src:50-50", "past the end of the raw file (9 lines)")

    def test_marker_must_have_the_pipe(self):
        res = self.check("-- src:1 Điều 99 bogus")
        self.assertClean(res)
        self.assertEqual(res.nsrc, 0)

    def test_not_a_translator_exemption(self):
        # srcrefs.py is language-neutral: it has no language-specific escape hatches such as a `[translator]` marker.
        res = self.check("-- src:1 | [translator] not in the source")
        self.assertProblem(res, 1, "not a slice")

    def test_unreadable_file_is_a_problem(self):
        res = self.run_check(os.path.join(self.dir, "missing.l4"))
        self.assertEqual(res.status, 1)
        self.assertIn("missing.l4:0: cannot read file", res.problems[0])

    def test_the_text_of_the_next_line_is_not_a_slice_of_this_one(self):
        # the window is exactly lines N..M: neither the line after it nor the line before it
        self.assertProblem(self.check("-- src:1 | " + LAW[1]), 1, "not a slice")
        self.assertProblem(self.check("-- src:2 | " + LAW[0]), 1, "not a slice")
        self.assertProblem(self.check("-- src:2-3 | " + LAW[4]), 1, "not a slice")
        self.assertProblem(self.check("-- src:3-5 | " + LAW[1]), 1, "not a slice")

    def test_quote_range_past_the_end_of_the_raw_file(self):
        # the raw file's last line is 9; a trailing newline is not a tenth line
        self.assertProblem(self.check("-- src:9-10 | " + LAW[8]), 1, "src:9-10", "past the end of the raw file (9 lines)")
        self.assertProblem(self.check("-- src:4-99 | " + squash(LAW[4])), 1, "past the end")
        self.assertProblem(self.check("-- src:amend:2-3 | " + AMEND[1]), 1, "past the end of amend.txt (2 lines)")
        self.assertClean(self.check("-- src:8-9 | " + LAW[8]))

    def test_the_line_range_is_checked_whatever_the_quoted_text(self):
        # an empty body once skipped every check; N > M, line 0 and past the end are problems with any body
        for body in ("", " ", "…", "----", LAW[0]):
            for marker, why in (("5-2", "N > M"), ("0-1", "start at 1"), ("8-99", "past the end")):
                with self.subTest(body=body, marker=marker):
                    res = self.check(f"-- src:{marker} | {body}")
                    self.assertEqual(res.status, 1, res.out)
                    self.assertIn(why, res.problems[0])

    def test_a_quotation_with_no_text_is_a_problem(self):
        for body in ("", "   ", "…", "...", " -- ", "( )"):
            with self.subTest(body=body):
                self.assertProblem(self.check(f"-- src:1-5 | {body}"), 1, "src:1-5", "no text")

    def test_an_empty_quotation_does_not_cover_a_locator_it_never_quoted(self):
        res = self.check("-- src:1-5 |", "@ref src:1-5", *DECL, refs=True)
        self.assertProblem(res, 1, "no text")

    def test_quotation_starts_and_ends_at_a_word_boundary(self):
        # raw lines 2-3 say "... trong thời hạn 21 ngày kể từ ..."; a truncated number would change the legal meaning
        self.assertClean(self.check("-- src:2-3 | thời hạn 21 ngày kể từ"))
        for text in ("1 ngày kể từ", "thời hạn 2", "ời hạn 21 ngày", "hạn 21 ngà", "21 ngày kể từ ngày nhận được hợp đồng bảo hiể"):
            with self.subTest(text=text):
                self.assertProblem(self.check(f"-- src:2-3 | {text}"), 1, "not a slice")

    def test_a_trailing_ellipsis_lets_the_quotation_stop_inside_a_word(self):
        self.assertClean(self.check("-- src:2 | Đối với các hợp đồng bảo hiể…", "-- src:2 | Đối với các hợp đồng bảo hiể..."))
        # ... but it must still start on a word, and the same text without the ellipsis is not a slice
        self.assertProblem(self.check("-- src:2 | ối với các hợp đồng bảo hiể…"), 1, "not a slice")
        self.assertProblem(self.check("-- src:2 | Đối với các hợp đồng bảo hiể"), 1, "not a slice")

    def test_cr_alone_is_not_a_line_break(self):
        # lines are split on "\n" only, as the docstring says: a CR inside a line is whitespace
        raw = os.path.join(self.dir, "cr.txt")
        with open(raw, "w", encoding="utf-8", newline="") as f:
            f.write("Article 1. Alpha\rbeta\ngamma delta\nzeta eta\n")
        enc = self.write("cr.l4", "-- src:1 | Article 1. Alpha beta\n-- src:2-3 | gamma delta zeta eta\n")
        res = self.run_check(enc, raw=raw)
        self.assertClean(res)
        self.assertEqual(res.nsrc, 2)
        p = subprocess.run([sys.executable, "-I", SRCREFS, "quote", raw, "2", "3"], capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(p.stdout, "-- src:2 | gamma delta\n-- src:3 | zeta eta\n")
        self.assertProblem(self.run_check(self.write("cr2.l4", "-- src:4 | zeta eta\n"), raw=raw), 1, "past the end of the raw file (3 lines)")

    def test_crlf_files_are_read_like_lf_files(self):
        raw = os.path.join(self.dir, "crlf.txt")
        with open(raw, "w", encoding="utf-8", newline="") as f:
            f.write("\r\n".join(LAW) + "\r\n")
        text = "\r\n".join([q(1), q(2, 3), "@ref src:1-3 (Điều 35)", *DECL]) + "\r\n"
        enc = os.path.join(self.dir, "crlf.l4")
        with open(enc, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        res = self.run_check(enc, raw=raw, refs=True)
        self.assertClean(res)
        self.assertEqual((res.nsrc, res.nruns, res.nlocs), (2, 1, 1))


class TestWithoutRefsFlag(Base):
    def test_r2_and_r3_are_not_enforced_without_refs(self):
        lines = [q(1), *DECL, "@ref src:99-100", "@ref (src:5-2)", "@ref (src:oops"]
        res = self.check(*lines)
        self.assertClean(res)
        self.assertEqual(res.nlocs, 2)  # well-formed ones are counted, though not checked
        self.assertEqual(self.check(*lines, refs=True).status, 1)

    def test_orphan_quotation_passes_without_refs(self):
        self.assertClean(self.check(q(1), *DECL))

    def test_files_without_locators_behave_as_before(self):
        lines = [q(1), q(2, 3), "", q(5), "@ref Điều 35", *DECL, "-- src:2 | " + LAW[1]]
        res = self.check(*lines)
        self.assertClean(res)
        self.assertEqual((res.nsrc, res.nlocs), (4, 0))


class TestR2(Base):
    def test_locator_inside_quoted_range(self):
        self.assertClean(self.check(q(1), q(2, 3), "@ref Điều 35 (src:1-3)", *DECL, refs=True))

    def test_single_line_locator(self):
        self.assertClean(self.check(q(7), "@ref src:7", *DECL, refs=True))

    def test_locator_start_not_covered(self):
        res = self.check(q(2, 3), "@ref (src:1-3)", *DECL, refs=True)
        self.assertProblem(res, 2, "src:1-3", "line 1 not covered")

    def test_locator_end_not_covered(self):
        res = self.check(q(1, 2), "@ref (src:1-3)", *DECL, refs=True)
        self.assertProblem(res, 2, "src:1-3", "line 3 not covered")

    def test_locator_both_ends_not_covered_is_one_problem(self):
        res = self.check(q(5), "@ref (src:1-9)", *DECL, refs=True)
        self.assertProblem(res, 2, "line 1 and 9 not covered")

    def test_gap_inside_the_range_is_allowed(self):
        # raw line 4 is a page footer, left out of the run; the locator spans it
        self.assertClean(self.check(q(2, 3), q(5), "@ref src:2-5", *DECL, refs=True))

    def test_endpoints_may_be_covered_by_different_quote_lines(self):
        self.assertClean(self.check(q(1), "", q(8), "@ref src:1-8", *DECL, refs=True))

    def test_locator_in_a_gap_is_not_covered(self):
        res = self.check(q(2, 3), q(5), "@ref src:2-5 src:4", *DECL, refs=True)
        self.assertProblem(res, 3, "src:4", "line 4 not covered")

    def test_locator_past_the_end_of_the_raw_file(self):
        res = self.check(q(8, 9), "@ref src:8-99", *DECL, refs=True)
        self.assertProblem(res, 2, "src:8-99", "past the end of the raw file (9 lines)")

    def test_locator_wholly_past_the_end(self):
        res = self.check(q(1), "@ref src:500", q(1), "@ref src:1", refs=True)
        self.assertProblem(res, 2, "src:500", "past the end")

    def test_locator_line_zero(self):
        res = self.check(q(1), "@ref src:0-1", refs=True)
        self.assertProblem(res, 2, "start at 1")

    def test_n_greater_than_m(self):
        res = self.check(q(1, 3), "@ref src:1-3 src:3-1", *DECL, refs=True)
        self.assertProblem(res, 2, "src:3-1", "N > M")

    def test_n_equal_m_is_fine(self):
        self.assertClean(self.check(q(3), "@ref src:3-3", *DECL, refs=True))

    def test_id_qualified_locator_inside_quoted_range(self):
        self.assertClean(self.check(qa(1, 2), "@ref src:amend:1-2", *DECL, refs=True))

    def test_id_qualified_locator_needs_a_quote_with_that_id(self):
        # law.txt lines 1-2 are quoted, but the locator is about amend.txt
        res = self.check(q(1, 2), "@ref src:amend:1", refs=True)
        self.assertEqual(res.status, 1)
        self.assertTrue(any("src:amend:1" in p and "not covered" in p and "with ID amend" in p for p in res.problems), res.out)

    def test_plain_locator_needs_a_plain_quote(self):
        res = self.check(qa(1), "@ref src:1", refs=True)
        self.assertEqual(res.status, 1)
        self.assertTrue(any("src:1" in p and "not covered" in p for p in res.problems), res.out)

    def test_id_locator_past_the_end_of_the_id_file(self):
        res = self.check(qa(2), "@ref src:amend:2-9", refs=True)
        self.assertProblem(res, 2, "past the end of amend.txt (2 lines)")

    def test_id_locator_names_no_raw_file(self):
        res = self.check("@ref src:nosuch:1-2", refs=True)
        self.assertProblem(res, 1, "names no raw file nosuch.txt")

    def test_locator_of_another_file_does_not_cover(self):
        # coverage is per file: a quote in enc1.l4 does not cover a locator in enc2.l4
        f1 = self.enc(q(1, 3), "@ref src:1-3")
        f2 = self.enc("@ref src:1-3")
        res = self.run_check(f1, f2, refs=True)
        self.assertEqual(res.status, 1, res.out)
        self.assertEqual(res.nbad, 1)
        self.assertTrue(res.problems[0].startswith(f"{f2}:1: "), res.out)

    def test_several_locators_anywhere_on_the_line(self):
        res = self.check(q(1), qa(2), "@ref (src:1) Điều 35 and also src:amend:2, but see src:1.", *DECL, refs=True)
        self.assertClean(res)
        self.assertEqual(res.nlocs, 3)

    def test_each_bad_locator_on_a_line_is_reported(self):
        res = self.check(q(1), "@ref src:1 src:6 src:9", refs=True)
        self.assertEqual(res.nbad, 2, res.out)
        self.assertIn("src:6", res.problems[0])
        self.assertIn("src:9", res.problems[1])

    def test_locator_followed_by_punctuation(self):
        self.assertClean(self.check(q(1), "@ref Điều 35 (src:1): thời gian", q(8), "@ref src:8; src:8.", refs=True))

    def test_indented_ref_line_is_read(self):
        res = self.check(q(1), "    @ref src:1 src:6", refs=True)
        self.assertProblem(res, 2, "src:6")

    def test_locator_on_a_non_ref_line_is_ignored(self):
        lines = [
            q(1),
            "@ref Điều 35 (src:1)",
            "-- see src:99-100 and src:amend:7 and src:3-1",
            "GIVEN x IS A Number -- compare src:123",
            "@desc this one cites src:500",
            "DECIDE `thing` IS x",
        ]
        res = self.check(*lines, refs=True)
        self.assertClean(res)
        self.assertEqual(res.nlocs, 1)  # only the one on the @ref line

    def test_ref_keyword_is_read_the_way_l4_reads_it(self):
        # L4 matches the herald as a prefix: `@reference src:99` is an @ref with the text "erence src:99", and `@ref(src:1)` one too.
        res = self.check(q(1), "@reference src:1 src:99", *DECL, refs=True)
        self.assertProblem(res, 2, "src:99", "past the end")
        self.assertEqual(res.nlocs, 2)
        self.assertClean(self.check(q(1), "@ref(src:1)", *DECL, refs=True))

    def test_ref_src_and_ref_map_are_other_annotations(self):
        res = self.check(q(1), "@ref src:1", "@ref-map src:99 https://example.com/x", "@ref-src src:98", *DECL, refs=True)
        self.assertClean(res)
        self.assertEqual(res.nlocs, 1)

    def test_src_glued_to_a_word_is_not_a_locator(self):
        res = self.check(q(1), "@ref (src:1) xsrc:99 resrc:7-1", refs=True)
        self.assertClean(res)
        self.assertEqual(res.nlocs, 1)

    def test_malformed_locators_are_problems(self):
        for bad in ("src:5-x", "src:x", "src:1-2-3", "src:5:7", "src:law-1", "src: 760", "src:)",
                    # a range or a list written some other way would be read as the single line N
                    "src:1\u20135", "src:1\u20145", "src:1 \u2013 5", "src:1\u22125", "src:1..5", "src:1 - 5", "src:1,5",
                    "src:amend:1\u20132"):
            with self.subTest(bad=bad):
                res = self.check(q(1), "@ref src:1", f"@ref Điều 35 ({bad})", refs=True)
                self.assertEqual(res.nbad, 1, res.out)
                self.assertIn("malformed locator", res.problems[0])
                self.assertIn(":3: ", res.problems[0])

    def test_a_locator_followed_by_prose_with_numbers_is_not_malformed(self):
        for tail in ("(src:1) - 5 days", "(src:1), 5 days", "src:1; src:3", "src:1 to 3", "src:1 and src:3", "src:1. 5 days", "src:1-3, and 5"):
            with self.subTest(tail=tail):
                res = self.check(q(1, 3), f"@ref Điều 35 {tail}", *DECL, refs=True)
                self.assertClean(res)

    def test_a_locator_in_a_block_comment_is_not_a_locator(self):
        # L4 lexes {- -} and /* */ (nested) as comments, so an @ref inside is never attached to anything
        for opener, closer in (("{-", "-}"), ("/*", "*/")):
            with self.subTest(opener=opener):
                res = self.check(q(1), opener, "@ref src:1", closer, *DECL, refs=True)
                self.assertProblem(res, 1, "orphan quotation")
                self.assertEqual(res.nlocs, 0)
        res = self.check(q(1), "{- outer", "/* inner", "-}", "@ref src:1", "*/", "-}", "@ref src:1", *DECL, refs=True)
        self.assertClean(res)  # the first @ref is inside both comments; the second is outside them
        self.assertEqual(res.nlocs, 1)
        res = self.check(q(1), "{- an aside -} @ref src:1", *DECL, refs=True)  # code after the comment closed on the same line
        self.assertClean(res)
        self.assertEqual(res.nlocs, 1)

    def test_a_ref_in_a_line_comment_a_string_or_a_name_is_not_an_at_ref(self):
        lines = [
            q(1),
            "@ref src:1",
            "-- @ref src:99",
            "// @ref src:99",
            'DECIDE `x` IS "see @ref src:99"',
            "DECIDE `see @ref src:99` IS 1",
            "@desc cites @ref src:99",
            "DECIDE `y` IS 2 -- @ref src:99",
        ]
        res = self.check(*lines, refs=True)
        self.assertClean(res)
        self.assertEqual(res.nlocs, 1)

    def test_a_block_comment_does_not_hide_the_quote_lines_in_it(self):
        # a quotation commented out with {- -} is still checked against the raw text (R1 always held for it)
        res = self.check("{-", "-- src:1 | not the text", "-}")
        self.assertProblem(res, 2, "not a slice")

    def test_inline_ref_on_its_own_line_is_an_at_ref(self):
        self.assertClean(self.check(q(1), "<<Điều 35 (src:1)>>", *DECL, refs=True))
        res = self.check(q(1), "<<Điều 35 (src:1 src:99)>>", *DECL, refs=True)
        self.assertProblem(res, 2, "src:99", "past the end")

    def test_an_inline_ref_is_read_only_up_to_the_end_of_its_line(self):
        res = self.check(q(1), "<<Điều 35", "(src:1)>>", *DECL, refs=True)
        self.assertProblem(res, 1, "orphan quotation")
        self.assertEqual(res.nlocs, 0)

    def test_an_at_ref_after_code_on_the_same_line_is_read_and_checked(self):
        # L4 lexes it and attaches it to the next node; the gate reads it like any other (--strict wants it on its own line)
        res = self.check(q(1), "DECIDE `thing` IS 1 @ref src:1", refs=True)
        self.assertClean(res)
        self.assertEqual(res.nlocs, 1)
        res = self.check(q(1), "@ref src:1", "DECIDE `thing` IS 1 @ref src:99", refs=True)
        self.assertProblem(res, 3, "src:99", "past the end")

    def test_src_colon_at_the_end_of_a_ref_line_is_prose(self):
        self.assertClean(self.check(q(1), "@ref src:1 -- see the quote lines marked src:", refs=True))

    def test_prose_mentioning_src_is_not_a_problem(self):
        self.assertClean(self.check(q(1), "@ref src:1 -- the src: lines are quoted above", refs=True))

    def test_ref_without_locator_is_ignored(self):
        res = self.check(q(1), "@ref Điều 35", "@ref src:1", refs=True)
        self.assertClean(res)
        self.assertEqual(res.nlocs, 1)


class TestR3(Base):
    def test_run_with_overlapping_locator(self):
        self.assertClean(self.check(q(1), q(2, 3), "@ref src:1-3", *DECL, refs=True))

    def test_orphan_run_reports_its_first_line_and_range(self):
        res = self.check("GIVEN y IS A Number", q(2, 3), q(5), *DECL, refs=True)
        self.assertProblem(res, 2, "orphan quotation", "src:2-5")

    def test_orphan_run_with_a_single_line(self):
        res = self.check(q(8), *DECL, refs=True)
        self.assertProblem(res, 1, "orphan quotation", "src:8")

    def test_orphan_run_between_declarations_and_at_start(self):
        res = self.check(q(1), "@ref src:1", *DECL, q(8), *DECL, refs=True)
        self.assertProblem(res, 5, "orphan quotation", "src:8")

    def test_only_the_unreferenced_run_is_an_orphan(self):
        res = self.check(q(1), "@ref src:1", *DECL, q(8), q(9), "@ref src:8-9", *DECL, q(2, 3), *DECL, refs=True)
        self.assertProblem(res, 10, "orphan quotation", "src:2-3")
        self.assertEqual(res.nruns, 3)

    def test_blank_lines_do_not_break_a_run(self):
        res = self.check(q(1), "", q(2, 3), "", "", q(5), "@ref src:1-5", *DECL, refs=True)
        self.assertClean(res)
        self.assertEqual(res.nruns, 1)

    def test_blank_line_run_joined_orphan_is_one_problem(self):
        res = self.check(q(1), "", q(2, 3), "   ", q(5), *DECL, refs=True)
        self.assertProblem(res, 1, "src:1-5")
        self.assertEqual(res.nruns, 1)

    def test_a_comment_breaks_a_run(self):
        res = self.check(q(1), "-- an aside", q(2, 3), "@ref src:1", *DECL, refs=True)
        self.assertEqual(res.nruns, 2)
        self.assertProblem(res, 3, "orphan quotation", "src:2-3")

    def test_one_wide_locator_satisfies_two_runs(self):
        res = self.check(q(1), "-- an aside", q(2, 3), "@ref src:1-3", *DECL, refs=True)
        self.assertClean(res)
        self.assertEqual(res.nruns, 2)

    def test_a_declaration_or_ref_line_breaks_a_run(self):
        res = self.check(q(1), "@ref src:1", *DECL, q(2, 3), "@ref src:2-3", q(5), "@ref src:5", *DECL, refs=True)
        self.assertClean(res)
        self.assertEqual(res.nruns, 3)

    def test_overlap_is_enough(self):
        # the locator reaches only the last line of the run
        self.assertClean(self.check(q(1, 3), q(5), "@ref src:3-5", *DECL, refs=True))

    def test_a_narrower_locator_than_the_quote_line_still_overlaps(self):
        # the quote line names src:1-3; the locator names only its last raw line
        res = self.check(q(1, 3), "@ref src:3", *DECL, refs=True)
        self.assertClean(res)
        self.assertEqual(res.nruns, 1)

    def test_overlapping_any_line_of_the_run_is_enough(self):
        res = self.check(q(1), q(8), "@ref src:8", *DECL, refs=True)
        self.assertClean(res)
        self.assertEqual(res.nruns, 1)

    def test_locator_in_another_file_does_not_count(self):
        f1 = self.enc(q(1, 3), *DECL)
        f2 = self.enc(q(1, 3), "@ref src:1-3")
        res = self.run_check(f1, f2, refs=True)
        self.assertEqual(res.nbad, 1, res.out)
        self.assertTrue(res.problems[0].startswith(f"{f1}:1: orphan quotation"), res.out)

    def test_locator_with_another_id_does_not_count(self):
        res = self.check(q(1, 2), qa(1, 2), "@ref src:amend:1-2", *DECL, refs=True)
        self.assertEqual(res.status, 1, res.out)
        self.assertEqual(res.nruns, 1)
        self.assertEqual(len(res.problems), 1)
        self.assertRegex(res.problems[0], r":1: orphan quotation.*src:1-2")

    def test_mixed_id_run_needs_a_locator_per_id(self):
        res = self.check(q(1, 3), qa(1, 2), "@ref (src:1-3)", *DECL, refs=True)
        self.assertEqual(res.nruns, 1)
        self.assertEqual(res.nbad, 1, res.out)
        self.assertRegex(res.problems[0], r":2: orphan quotation.*src:amend:1-2")  # at that ID's first line

    def test_mixed_id_run_with_both_locators(self):
        res = self.check(q(1, 3), qa(1, 2), "@ref (src:1-3; src:amend:1-2)", *DECL, refs=True)
        self.assertClean(res)
        self.assertEqual((res.nruns, res.nlocs), (1, 2))

    def test_invalid_locator_does_not_save_a_run(self):
        res = self.check(q(1, 3), "@ref src:3-1", *DECL, refs=True)
        self.assertEqual(res.nbad, 2, res.out)
        self.assertTrue(any("N > M" in p for p in res.problems))
        self.assertTrue(any("orphan" in p for p in res.problems))

    def test_empty_file_and_file_without_quotes_are_fine(self):
        self.assertClean(self.check("", refs=True))
        self.assertClean(self.check(*DECL, "-- nothing quoted here", refs=True))

    def test_counts_in_summary(self):
        res = self.check(q(1), q(2, 3), "@ref src:1-3", *DECL, q(8), "@ref src:8 and src:9", refs=True)
        self.assertEqual((res.nsrc, res.nruns, res.nlocs), (3, 2, 3))
        # src:9 is not covered by any quote line
        self.assertEqual(res.nbad, 1)

    def test_problem_lines_are_in_file_order_then_line_order(self):
        f1 = self.enc(q(1), q(7), *DECL)
        f2 = self.enc(q(8), "", "-- src:2 | not a slice", *DECL)
        res = self.run_check(f1, f2, refs=True)
        starts = [p.split(": ")[0] for p in res.problems]
        # f1: one orphan run; f2: one orphan run (blank lines join q(8) to the line after) and the bad quote
        self.assertEqual(starts, [f"{f1}:1", f"{f2}:1", f"{f2}:3"])


class TestRefLines(Base):
    """What the default gate (--refs) makes of the lines around an @ref."""

    def test_a_quote_line_with_n_greater_than_m_is_one_problem_not_an_orphan_as_well(self):
        res = self.check("-- src:3-2 | " + LAW[1], *DECL, refs=True)
        self.assertProblem(res, 1, "N > M")

    def test_a_locator_past_the_end_is_reported_even_if_a_bad_quote_line_names_that_line(self):
        res = self.check("-- src:9-10 | " + LAW[8], "@ref src:9-10", *DECL, refs=True)
        self.assertEqual(res.nbad, 2, res.out)
        self.assertTrue(any(":1: " in p and "past the end" in p for p in res.problems), res.out)
        self.assertTrue(any(":2: src:9-10: past the end" in p for p in res.problems), res.out)

    def test_an_at_ref_line_is_not_a_quote_line_whatever_it_says_after_a_comment_mark(self):
        res = self.check(q(1), "@ref src:1 -- src:1 | not the text", *DECL, refs=True)
        self.assertClean(res)
        self.assertEqual(res.nsrc, 1)


class TestExemption(Base):
    """A run whose block ends where the convention puts no `@ref` needs none (R3); the rest of the gate still reads it."""

    def test_run_before_a_heading_or_directive_or_end_of_file_needs_no_ref(self):
        for after in (["§ `A heading`"], ["§§ `A subsection`"], ["#ASSERT x EQUALS 1"], ["#EVAL x"], ["#CHECK x"], ["#EVALTRACE x"], []):
            with self.subTest(after=after):
                res = self.check(q(1), q(2, 3), *after, refs=True)
                self.assertClean(res)
                self.assertEqual(res.nruns, 1)

    def test_exemption_looks_past_blank_lines_and_comments_and_other_runs(self):
        # the shape of a module header: two runs split by a comment, then a heading
        res = self.check("-- the V1 commencement:", q(2), "-- the commencement of the amending law:", q(8, 9), "", "§ `The vintages`", *DECL, refs=True)
        self.assertClean(res)
        self.assertEqual(res.nruns, 2)

    def test_a_declaration_or_any_other_line_ends_the_exemption(self):
        for after in (DECL, ["IMPORT prelude"], ["@desc a rule", *DECL], ["ASSUME x IS A Number"], ["DECLARE Thing HAS x IS A Number"]):
            with self.subTest(after=after):
                res = self.check(q(1), *after, refs=True)
                self.assertProblem(res, 1, "orphan quotation", "src:1")

    def test_an_exempt_run_is_still_checked_by_r1_and_its_locators_by_r2(self):
        res = self.check("-- src:1 | not the text", "#ASSERT x", refs=True)
        self.assertProblem(res, 1, "not a slice")
        res = self.check(q(1), "@ref src:1-3", "§ `A heading`", refs=True)  # the gate does not police where the @ref sits
        self.assertProblem(res, 2, "src:1-3", "line 3 not covered")

    def test_a_run_followed_by_a_ref_and_then_a_heading_with_a_matching_locator_passes(self):
        self.assertClean(self.check(q(1), "@ref src:1", "§ `A heading`", refs=True))

    def test_exempt_runs_are_still_counted(self):
        res = self.check(q(1), "#EVAL x", q(2, 3), "@ref src:2-3", *DECL, q(8), refs=True)
        self.assertClean(res)
        self.assertEqual((res.nsrc, res.nruns), (3, 3))

    def test_the_exemption_holds_under_strict_too(self):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            status = srcrefs.main(["check", "--strict", self.raw, self.enc(q(1), "-- aside", q(2, 3), "#ASSERT x", q(8), "@ref src:8", *DECL)])
        self.assertEqual(status, 0, buf.getvalue())


class TestStrict(Base):
    """--strict: R2 and R3 are local, and the locators must reach exactly the span the runs quote."""

    def strict(self, *lines):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            status = srcrefs.main(["check", "--strict", self.raw, self.enc(*lines)])
        return Result(status, buf.getvalue())

    def test_strict_implies_refs_and_passes_on_the_run_span(self):
        self.assertClean(self.strict(q(1), q(2, 3), q(5), "@ref Điều 35 (src:1-5)", *DECL))
        res = self.strict(q(1), *DECL)  # --refs was not given
        self.assertProblem(res, 1, "orphan quotation")

    def test_the_default_gate_accepts_a_locator_from_anywhere_in_the_file(self):
        # documented as a silent failure of the default mode: one wide locator at the end covers every run
        lines = [q(1), *DECL, q(2, 3), *DECL, q(8, 9), *DECL, "@ref src:1-9"]
        self.assertEqual(self.check(*lines, refs=True).status, 0)
        res = self.strict(*lines)
        self.assertEqual(res.status, 1, res.out)
        self.assertEqual(len([p for p in res.problems if "orphan quotation" in p]), 3, res.out)

    # ---- a locator elsewhere in the file does not count

    def test_deleting_the_first_ref_of_a_run_is_caught_even_if_a_later_ref_cites_the_run(self):
        # the later declaration's own @ref overlaps the run, but it sits in another block
        ok = [q(1, 3), "@ref src:1-3", *DECL, "@ref src:2-3", *DECL]
        self.assertClean(self.check(*ok, refs=True))
        self.assertClean(self.strict(*ok))
        gone = [q(1, 3), *DECL, "@ref src:2-3", *DECL]
        self.assertClean(self.check(*gone, refs=True))
        self.assertProblem(self.strict(*gone), 1, "orphan quotation", "src:1-3")

    def test_a_ref_above_its_run_does_not_cover_it(self):
        lines = ["@ref src:1", q(1), *DECL]
        self.assertClean(self.check(*lines, refs=True))
        res = self.strict(*lines)
        self.assertEqual(res.nbad, 2, res.out)
        self.assertTrue(any("orphan quotation" in p for p in res.problems), res.out)
        self.assertTrue(any("src:1: line 1 not covered" in p for p in res.problems), res.out)

    def test_an_earlier_runs_ref_does_not_cover_a_later_run(self):
        # the first run quotes lines 1-3 and the second quotes 2-3 again; the first run's @ref overlaps both, but sits in another block
        lines = [q(1, 3), "@ref src:1-3", *DECL, q(2, 3), *DECL]
        self.assertClean(self.check(*lines, refs=True))
        self.assertProblem(self.strict(*lines), 5, "orphan quotation", "src:2-3")

    def test_an_at_ref_after_code_does_not_cover_the_run(self):
        self.assertProblem(self.strict(q(1), "DECIDE `thing` IS 1 @ref src:1"), 1, "orphan quotation")

    def test_two_runs_split_by_a_comment_may_share_the_ref_below_them(self):
        self.assertClean(self.strict(q(1), "-- an aside", q(2, 3), "@ref src:1-3", *DECL))

    def test_refs_between_runs_of_one_block_count_for_the_runs_above_them(self):
        res = self.strict(q(1), "@ref src:1", q(2, 3), "@ref src:2-3", *DECL)
        self.assertClean(res)
        self.assertEqual(res.nruns, 2)

    # ---- an off-by-one locator that another run's quote lines would once have covered

    def test_a_locator_widened_into_the_next_run_is_not_covered(self):
        self.assertClean(self.strict(q(1, 3), "@ref src:1-3", *DECL, q(5), "@ref src:5", *DECL))
        lines = [q(1, 3), "@ref src:1-5", *DECL, q(5), "@ref src:5", *DECL]
        self.assertClean(self.check(*lines, refs=True))  # the default gate finds line 5 quoted somewhere in the file
        res = self.strict(*lines)
        self.assertTrue(any(":2: src:1-5: line 5 not covered by the quote lines it follows" in p for p in res.problems), res.out)

    def test_a_locator_widened_into_the_previous_run_is_not_covered(self):
        lines = [q(1), "@ref src:1", *DECL, q(2, 3), "@ref src:1-3", *DECL]
        self.assertClean(self.check(*lines, refs=True))
        res = self.strict(*lines)
        self.assertTrue(any(":6: src:1-3: line 1 not covered" in p for p in res.problems), res.out)

    def test_a_later_ref_is_governed_by_the_run_above_it(self):
        self.assertClean(self.strict(q(1, 3), "@ref src:1-3", *DECL, "@ref src:2-3", *DECL, "@ref src:3", *DECL))
        res = self.strict(q(1, 3), "@ref src:1-3", *DECL, "@ref src:2-5", *DECL)
        self.assertProblem(res, 5, "src:2-5", "line 5 not covered")

    def test_a_later_ref_is_governed_by_the_nearest_run_not_an_older_one(self):
        res = self.strict(q(1), "@ref src:1", *DECL, q(8), "@ref src:8", *DECL, "@ref src:1", *DECL)
        self.assertProblem(res, 9, "src:1", "line 1 not covered")

    def test_the_ids_of_the_governing_runs_are_kept_apart(self):
        res = self.strict(q(1, 2), qa(1, 2), "@ref src:1-2 src:amend:1-2", *DECL, q(5), "@ref src:5 src:amend:1", *DECL)
        self.assertProblem(res, 7, "src:amend:1", "not covered", "with ID amend")

    def test_a_plain_quote_does_not_cover_an_id_locator_with_the_same_number(self):
        res = self.strict(q(1), "@ref src:1 src:amend:1", *DECL)
        self.assertProblem(res, 2, "src:amend:1", "not covered", "with ID amend")

    def test_a_quote_line_with_n_greater_than_m_covers_nothing(self):
        res = self.strict("-- src:3-2 | " + LAW[1], "@ref src:2-3", *DECL)
        self.assertTrue(any("N > M" in p for p in res.problems), res.out)
        self.assertTrue(any("line 2 and 3 not covered" in p for p in res.problems), res.out)

    # ---- exactness

    def test_a_narrowed_locator_is_caught(self):
        self.assertClean(self.strict(q(2, 3), q(5), "@ref src:2-5", *DECL))
        for loc in ("src:3-5", "src:2-3", "src:3", "src:5"):
            with self.subTest(loc=loc):
                res = self.strict(q(2, 3), q(5), f"@ref {loc}", *DECL)
                self.assertProblem(res, 1, "not exact", "src:2-5")
                self.assertEqual(self.check(q(2, 3), q(5), f"@ref {loc}", *DECL, refs=True).status, 0)

    def test_a_widened_locator_is_caught_by_r2(self):
        res = self.strict(q(2, 3), q(5), "@ref src:1-5", *DECL)
        self.assertTrue(any(":3: src:1-5: line 1 not covered" in p for p in res.problems), res.out)

    def test_several_locators_for_one_run_are_judged_together(self):
        # a generated row splits a run into stretches: the hull of the locators is what must match
        self.assertClean(self.strict(q(1), q(8, 9), "@ref src:1; src:8-9", *DECL))
        res = self.strict(q(1), q(8, 9), "@ref src:1; src:8", *DECL)
        self.assertProblem(res, 1, "not exact", "src:1-9", "reach src:1-8")

    def test_one_ref_below_two_runs_of_a_block_may_span_both(self):
        self.assertClean(self.strict(q(1), "-- an aside", q(2, 3), "@ref src:1-3", *DECL))

    def test_refs_between_the_runs_of_a_block_count_but_one_above_the_first_run_does_not(self):
        self.assertClean(self.strict(q(1), "@ref src:1", q(2, 3), "@ref src:2-3", *DECL))
        res = self.strict("@ref src:1-3", q(1, 3), "@ref src:2", *DECL)
        self.assertTrue(any("not exact" in p and "reach src:2-2" in p for p in res.problems), res.out)

    def test_each_id_is_judged_on_its_own(self):
        self.assertClean(self.strict(q(1, 3), qa(1, 2), "@ref src:1-3 src:amend:1-2", *DECL))
        res = self.strict(q(1, 3), qa(1, 2), "@ref src:1-3 src:amend:1", *DECL)
        self.assertProblem(res, 2, "not exact", "src:amend:1-2", "reach src:amend:1-1")

    def test_later_refs_may_be_narrower(self):
        self.assertClean(self.strict(q(1, 3), "@ref src:1-3", *DECL, "@ref src:2-3", *DECL))

    def test_without_strict_a_narrow_first_ref_is_fine(self):
        self.assertClean(self.check(q(2, 3), q(5), "@ref src:2-3", *DECL, refs=True))


class TestCommandLine(Base):
    def cli(self, *args):
        p = subprocess.run([sys.executable, "-I", SRCREFS, *args], capture_output=True, text=True, encoding="utf-8")
        return p.returncode, p.stdout, p.stderr

    def test_quote_single_line(self):
        code, out, err = self.cli("quote", self.raw, "1")
        self.assertEqual((code, out, err), (0, f"-- src:1 | {LAW[0]}\n", ""))

    def test_quote_range_skips_blank_lines_and_squeezes_whitespace(self):
        code, out, _ = self.cli("quote", self.raw, "4", "7")
        self.assertEqual(code, 0)
        self.assertEqual(out.split("\n")[:-1], ["-- src:4 | Trang 12", "-- src:5 | " + LAW[4], "-- src:7 | " + LAW[6]])

    def test_quote_output_is_normalised_to_nfc(self):
        raw = self.write("nfd.txt", unicodedata.normalize("NFD", "\n".join(LAW)) + "\n")
        _, out, _ = self.cli("quote", raw, "1")
        self.assertEqual(out, f"-- src:1 | {LAW[0]}\n")

    def test_quoteid_uses_the_stem_of_raw(self):
        code, out, _ = self.cli("quoteid", os.path.join(self.dir, "amend.txt"), "1", "2")
        self.assertEqual(code, 0)
        self.assertEqual(out.split("\n")[:-1], [f"-- src:amend:{i + 1} | {AMEND[i]}" for i in range(2)])

    def test_pasted_quote_output_passes_the_gate(self):
        _, out1, _ = self.cli("quote", self.raw, "1", "9")
        _, out2, _ = self.cli("quoteid", os.path.join(self.dir, "amend.txt"), "1", "2")
        enc = self.write("pasted.l4", out1 + out2)
        code, out, _ = self.cli("check", self.raw, enc)
        self.assertEqual(code, 0, out)
        self.assertIn("srcrefs check: 10 src: lines, 1 runs, 0 locators, 0 problems", out)

    def test_quote_past_the_end_fails(self):
        for args in (("5", "99"), ("0",), ("3", "2")):
            code, out, err = self.cli("quote", self.raw, *args)
            self.assertEqual((code, out), (1, ""), args)
            self.assertIn("not inside", err)

    def test_quote_needs_numbers(self):
        self.assertEqual(self.cli("quote", self.raw, "x")[0], 2)
        self.assertEqual(self.cli("quote", self.raw)[0], 2)

    def test_check_exit_status_and_summary(self):
        good = self.write("good.l4", q(1) + "\n")
        bad = self.write("bad.l4", "-- src:1 | wrong\n")
        code, out, _ = self.cli("check", self.raw, good)
        self.assertEqual((code, out), (0, "srcrefs check: 1 src: lines, 1 runs, 0 locators, 0 problems\n"))
        code, out, _ = self.cli("check", self.raw, bad)
        self.assertEqual(code, 1)
        self.assertEqual(out, f"{bad}:1: src:1-1 quotation is not a slice of those lines\nsrcrefs check: 1 src: lines, 1 runs, 0 locators, 1 problems\n")

    def test_refs_flag_may_come_before_or_after_the_paths(self):
        f = self.write("f.l4", "\n".join([q(1), *DECL]) + "\n")
        for args in (("--refs", self.raw, f), (self.raw, "--refs", f), (self.raw, f, "--refs")):
            code, out, _ = self.cli("check", *args)
            self.assertEqual(code, 1, args)
            self.assertIn("orphan quotation", out)

    def test_usage_errors_exit_2(self):
        f = self.write("f.l4", "\n")
        self.assertEqual(self.cli()[0], 2)
        self.assertEqual(self.cli("frobnicate", self.raw)[0], 2)
        self.assertEqual(self.cli("check", self.raw)[0], 2)  # no FILE
        self.assertEqual(self.cli("check", "--wat", self.raw, f)[0], 2)
        code, out, err = self.cli("check", os.path.join(self.dir, "no-such-raw.txt"), f)
        self.assertEqual((code, out), (2, ""))
        self.assertIn("cannot read RAW", err)

    def test_runs_isolated_with_python_dash_I(self):
        # the tool imports only the standard library, so -I (which drops the script directory
        # from sys.path) must be enough
        f = self.write("f.l4", q(1) + "\n@ref src:1\n")
        code, out, _ = self.cli("check", "--refs", self.raw, f)
        self.assertEqual(code, 0, out)


if __name__ == "__main__":
    unittest.main(verbosity=1)
