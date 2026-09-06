"""R10 probe: can docassemble.base parse + assemble an interview with no server?

Expected outcome A (good): assemble() raises/returns pointing at the first
undefined variable's question -> headless harness is viable at altitude (a).
Expected outcome B: import-time or config-time failure -> fall back to
TestContext (altitude b) or a dockerised server (altitude c).
"""

import traceback

YAML = """---
question: |
  Was the loss caused by rodents?
yesno: caused_by_rodents
---
code: |
  covered = not caused_by_rodents
---
mandatory: True
question: |
  Verdict
subquestion: |
  Covered: ${ covered }
"""

try:
    import docassemble.base.config as config

    config.load(arguments=[], filename="da-root/config.yml", in_celery=False)
    print("config.load: OK")
except Exception as e:
    print("config.load failed:", repr(e))

try:
    # Stub pyzbar (barcode reading) so util.py imports without libzbar; the
    # harness never decodes barcodes. Clean alternative: brew install zbar.
    import sys
    import types

    _pyzbar_mod = types.ModuleType("pyzbar.pyzbar")
    _pyzbar_mod.decode = lambda *a, **k: []
    _pyzbar_pkg = types.ModuleType("pyzbar")
    _pyzbar_pkg.pyzbar = _pyzbar_mod
    sys.modules.setdefault("pyzbar", _pyzbar_pkg)
    sys.modules.setdefault("pyzbar.pyzbar", _pyzbar_mod)

    # Register a minimal hookimpl plugin so docassemble.base runs serverless.
    # The pluggy seam is new in docassemble 1.10.0; this is the whole trick.
    import pluggy

    hookimpl = pluggy.HookimplMarker("docassemble")

    class HeadlessPlugin:
        @hookimpl
        def get_configuration(self):
            return config.daconfig

        @hookimpl
        def get_default_language(self):
            return "en"

        @hookimpl
        def get_default_dialect(self):
            return "us"

        @hookimpl
        def get_default_locale(self):
            return "US.utf8"

        @hookimpl
        def get_default_voice(self):
            return None

        @hookimpl
        def get_default_timezone(self):
            return "America/New_York"

        @hookimpl
        def get_default_country(self):
            return "US"

        @hookimpl
        def get_debug_status(self):
            return True

        @hookimpl
        def get_hostname(self):
            return "localhost"

        @hookimpl
        def get_main_page_parts(self):
            return {}

        @hookimpl
        def get_default_table_class(self):
            return "table table-striped"

        @hookimpl
        def get_default_thead_class(self):
            return "table-primary"

        @hookimpl
        def url_finder(self, file_reference, kwargs):
            return ""

        @hookimpl
        def absolute_filename(self, the_file):
            return the_file

    from docassemble.base.plugin_manager import pm

    pm.register(HeadlessPlugin())

    import docassemble.base.parse as parse
    import docassemble.base.functions as functions

    print("import parse: OK")

    from docassemble.base.interview_source import InterviewSourceString
    from docassemble.base.thread_context import empty_globals, global_context

    ctx = global_context(empty_globals())
    ctx.__enter__()

    source = InterviewSourceString(content=YAML, path="test.yml", package="docassemble.l4probe")
    interview = parse.Interview(source=source)
    print("get_interview: OK,", len(interview.questions_list), "blocks")

    current_info = {
        "user": {
            "is_anonymous": False,
            "is_authenticated": True,
            "theid": 1,
            "the_user_id": 1,
            "roles": ["user"],
            "firstname": "Probe",
            "lastname": "User",
            "email": "probe@example.com",
            "country": "US",
            "subdivisionfirst": None,
            "subdivisionsecond": None,
            "subdivisionthird": None,
            "organization": None,
            "timezone": "America/New_York",
            "language": "en",
            "session_uid": "probe-uid",
            "device_id": "probe-device",
        },
        "session": "probe",
        "secret": None,
        "yaml_filename": "test.yml",
        "url": None,
        "url_root": None,
        "encrypted": False,
        "interface": "cli",
        "arguments": {},
    }
    status = parse.InterviewStatus(current_info=current_info)
    user_dict = parse.get_initial_dict()
    functions.this_thread.current_info = current_info
    interview.assemble(user_dict, status)
    print("assemble pass 1: question is", status.question.question_type,
          "->", repr(status.question.name))

    # Answer the question and re-assemble: the drive loop in miniature.
    user_dict["caused_by_rodents"] = True
    status2 = parse.InterviewStatus(current_info=current_info)
    interview.assemble(user_dict, status2)
    print("assemble pass 2: question type:", status2.question.question_type)
    print("verdict screen text:", status2.question_text, "/", status2.subquestion_text)
    print("covered =", user_dict.get("covered"))
except Exception as e:
    print("assemble path raised:", type(e).__name__, str(e)[:200])
    tb = traceback.format_exc()
    print(tb[-1500:])

# If we got an InterviewStatus with a populated question, print it.
try:
    q = status.question
    print("status.question type:", getattr(q, "question_type", None))
    print("fields:", [getattr(f, "saveas_code", None) or str(f) for f in getattr(status, "get_field_list", lambda: [])()])
except Exception as e:
    print("status inspect failed:", repr(e))
