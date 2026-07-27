import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.kie.api.KieServices;
import org.kie.api.builder.KieBuilder;
import org.kie.api.builder.KieFileSystem;
import org.kie.api.builder.Message;
import org.kie.api.io.Resource;
import org.kie.api.runtime.KieContainer;
import org.kie.dmn.api.core.DMNContext;
import org.kie.dmn.api.core.DMNDecisionResult;
import org.kie.dmn.api.core.DMNMessage;
import org.kie.dmn.api.core.DMNModel;
import org.kie.dmn.api.core.DMNResult;
import org.kie.dmn.api.core.DMNRuntime;
import org.kie.dmn.api.core.DMNType;
import org.kie.dmn.api.core.ast.BusinessKnowledgeModelNode;
import org.kie.dmn.api.core.ast.DecisionNode;
import org.kie.dmn.api.core.ast.DecisionServiceNode;
import org.kie.dmn.api.core.ast.InputDataNode;
import org.kie.dmn.validation.DMNValidator;
import org.kie.dmn.validation.DMNValidatorFactory;
import org.kie.internal.io.ResourceFactory;
import org.xml.sax.ErrorHandler;
import org.xml.sax.SAXParseException;

import javax.xml.XMLConstants;
import javax.xml.transform.stream.StreamSource;
import javax.xml.validation.Schema;
import javax.xml.validation.SchemaFactory;
import javax.xml.validation.Validator;
import java.io.File;
import java.math.BigDecimal;
import java.net.URL;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Take an emitted DMN file to Drools/KIE and report what the ENGINE says, as
 * opposed to what a schema or a metamodel parser says.
 *
 *   java KieDmnCheck FILE.dmn [--ctx ctx.json | --cases cases.json] [FILE2.dmn ...]
 *
 * --ctx supplies one input context and checks only that the model RAN. --cases
 * supplies a list of {name, context, expect} and additionally checks WHAT IT
 * ANSWERED. Prefer --cases: "5/5 SUCCEEDED" is a liveness claim, and the failure
 * this harness exists for is a wrong non-null value, not a missing one. The
 * Camunda misparse of `annual income` answers `true`, which every status check
 * and every null check in here would wave through (see 13.2 of the spec).
 *
 * Under --cases the check is symmetric: every decision the model evaluates must
 * be named in `expect`, and every name in `expect` must be a decision. Adding a
 * decision without an expectation is therefore a failure, not a silent gap.
 *
 * Four legs, in the order a real deployment meets them:
 *
 *   XSD    JAXP/Xerces against the DMN 1.3 schema that ships inside
 *          kie-dmn-validation's own jar (so there is nothing to download).
 *   VALID  org.kie.dmn.validation: SCHEMA + MODEL + COMPILATION.
 *   BUILD  KieBuilder, which is what a deployment actually runs. A model can
 *          validate and still fail to build.
 *   EVAL   evaluateAll with the supplied context, plus evaluateDecisionService
 *          for every decision service in the file.
 *
 * WHY ALL FOUR. No single leg is sufficient, and each row below is a measured
 * case in which the others are silent (§13.6 of the DMN spec):
 *
 *   cyclic decision service        XSD valid, validator clean, build clean, and
 *                                  every decision reports SUCCEEDED = null. The
 *                                  only signal is an ERROR in DMNResult's own
 *                                  message list.
 *   service with no outputDecision validator ERROR, build CLEAN, runtime throws.
 *   variable/@name mismatch        validator ERROR, but it evaluates correctly:
 *                                  the validator over-reports.
 *   input absent / wrong key       everything clean; the decision is SKIPPED.
 *
 * Hence the failure set: any validator ERROR, any build ERROR, any DMNResult
 * message at ERROR, any decision that is SUCCEEDED with a null value, any
 * decision SKIPPED, and any decision FAILED. A harness that counted only FAILED
 * would exit 0 on the first row. Do not relax this.
 *
 * Warnings are counted and printed but are NOT fatal here; the caller decides.
 * The reason is the third row: the KIE validator is known to over-report, so
 * making WARN fatal inside the harness would put a policy decision in the wrong
 * place. jl4/tests-cli asserts on the warning count in the verdict banner
 * instead, where relaxing it takes a visible edit.
 *
 * On success the last line is a VERDICT banner. The test harness asserts the
 * BANNER, not the exit code, so that "exited 0 without running anything" — which
 * is what a broken skip path looks like — cannot read as a pass.
 */
public final class KieDmnCheck {

  private static final String XSD_RESOURCE =
      "/org/kie/dmn/validation/org/omg/spec/DMN/20191111/DMN13.xsd";

  private static int errors = 0;
  private static int warnings = 0;
  private static int decisions = 0;
  private static int succeeded = 0;
  private static int files = 0;
  private static int cases = 0;
  private static int checked = 0;
  private static int matched = 0;

  public static void main(String[] argv) throws Exception {
    // FILE.dmn [--ctx c.json | --cases cs.json] ...: the flag attaches to the
    // file before it, so several files can be checked in one JVM.
    List<String[]> jobs = new ArrayList<>(); // {file, ctxOrNull, casesOrNull}
    for (int i = 0; i < argv.length; i++) {
      if (argv[i].equals("--ctx") || argv[i].equals("--cases")) {
        int slot = argv[i].equals("--ctx") ? 1 : 2;
        if (jobs.isEmpty() || i + 1 >= argv.length) {
          System.err.println(
              "KieDmnCheck: " + argv[i] + " must follow a .dmn file and name a .json file");
          System.exit(2);
        }
        jobs.get(jobs.size() - 1)[slot] = argv[++i];
        continue;
      }
      jobs.add(new String[] {argv[i], null, null});
    }
    if (jobs.isEmpty()) {
      System.err.println("usage: KieDmnCheck FILE.dmn [--ctx c.json | --cases cs.json] ...");
      System.exit(2);
    }

    Schema schema = loadSchema();
    // OBSERVED, not echoed: read off the jar that is actually on the classpath.
    // The version in the banner has to be evidence about which engine looked at
    // the file, which a constant passed in by the launcher is not.
    String version = KieServices.Factory.get().getClass().getPackage().getImplementationVersion();
    if (version == null) {
      version = "unknown";
    }
    // ...and cross-checked against the pin in pom.xml, so that a stale cached
    // classpath or an edited pom cannot leave the banner naming a version that
    // was never loaded.
    String expected = System.getProperty("l4.kie.version.expected", "");
    if (!expected.isEmpty() && !expected.equals(version)) {
      System.out.println(
          "VERSION MISMATCH: pom.xml pins " + expected + " but the classpath loaded " + version
              + " -- delete the cached cp.txt (see run.sh) or reconcile the pin.");
      errors++;
    }

    for (String[] job : jobs) {
      run(
          schema,
          new File(job[0]),
          job[1] == null ? null : new File(job[1]),
          job[2] == null ? null : new File(job[2]));
    }

    boolean ok =
        errors == 0 && decisions > 0 && succeeded == decisions && matched == checked;
    System.out.println();
    System.out.println(
        "KIE " + version + " VERDICT: " + files + " file(s), " + cases + " case(s), "
            + errors + " error(s), " + warnings + " warning(s), "
            + succeeded + "/" + decisions + " decision(s) SUCCEEDED, "
            + matched + "/" + checked + " value(s) as expected"
            + (ok ? "" : "   <<< FAILED"));
    System.exit(ok ? 0 : 1);
  }

  /**
   * The DMN 1.3 XSD is a resource inside kie-dmn-validation's jar, so there is
   * nothing to fetch and nothing to keep in step by hand. Its {@code xsd:import}s
   * (DMNDI13, DC, DI) are relative, and JAXP resolves them against the jar: URL.
   */
  private static Schema loadSchema() {
    URL url = KieDmnCheck.class.getResource(XSD_RESOURCE);
    if (url == null) {
      System.out.println("XSD    UNAVAILABLE (" + XSD_RESOURCE + " not on the classpath)");
      errors++;
      return null;
    }
    try {
      SchemaFactory sf = SchemaFactory.newInstance(XMLConstants.W3C_XML_SCHEMA_NS_URI);
      return sf.newSchema(url);
    } catch (Exception e) {
      System.out.println("XSD    UNAVAILABLE (" + e + ")");
      errors++;
      return null;
    }
  }

  private static void run(Schema schema, File f, File ctxFile, File casesFile) throws Exception {
    files++;
    System.out.println();
    System.out.println("=== " + f.getName() + " ===");

    if (schema != null) {
      Validator v = schema.newValidator();
      final List<String> msgs = new ArrayList<>();
      final boolean[] bad = {false};
      v.setErrorHandler(
          new ErrorHandler() {
            public void warning(SAXParseException e) {
              msgs.add("warn " + e.getMessage());
            }

            public void error(SAXParseException e) {
              bad[0] = true;
              msgs.add("error " + e.getMessage());
            }

            public void fatalError(SAXParseException e) {
              bad[0] = true;
              msgs.add("fatal " + e.getMessage());
            }
          });
      try {
        v.validate(new StreamSource(f));
      } catch (Exception e) {
        bad[0] = true;
        msgs.add("threw " + e);
      }
      System.out.println("XSD    " + (bad[0] ? "INVALID" : "valid"));
      for (String m : msgs) {
        System.out.println("       " + m);
      }
      if (bad[0]) {
        errors++;
      }
    }

    // ---- the KIE validator ------------------------------------------------
    List<DMNMessage> ms;
    try {
      ms =
          DMNValidatorFactory.newValidator()
              .validate(
                  f,
                  DMNValidator.Validation.VALIDATE_SCHEMA,
                  DMNValidator.Validation.VALIDATE_MODEL,
                  DMNValidator.Validation.VALIDATE_COMPILATION);
    } catch (Throwable t) {
      System.out.println("VALID  THREW " + t);
      errors++;
      return;
    }
    long errs = ms.stream().filter(m -> m.getSeverity() == DMNMessage.Severity.ERROR).count();
    long warns = ms.stream().filter(m -> m.getSeverity() == DMNMessage.Severity.WARN).count();
    System.out.println(
        "VALID  " + (ms.isEmpty() ? "clean" : errs + " error(s), " + warns + " warning(s)"));
    for (DMNMessage m : ms) {
      System.out.println("       " + m.getSeverity() + " [" + m.getMessageType() + "] " + m.getText());
    }
    errors += errs;
    warnings += warns;

    // ---- KieBuilder: what a deployment does -------------------------------
    KieServices kies = KieServices.Factory.get();
    KieFileSystem kfs = kies.newKieFileSystem();
    Resource res = ResourceFactory.newFileResource(f);
    res.setSourcePath("src/main/resources/" + f.getName());
    kfs.write(res);
    KieBuilder kb = kies.newKieBuilder(kfs).buildAll();
    List<Message> bmsgs = kb.getResults().getMessages();
    long berrs = bmsgs.stream().filter(m -> m.getLevel() == Message.Level.ERROR).count();
    System.out.println(
        "BUILD  " + (bmsgs.isEmpty() ? "clean" : berrs + " error(s) / " + bmsgs.size() + " message(s)"));
    for (Message m : bmsgs) {
      System.out.println("       " + m.getLevel() + " " + m.getText());
    }
    if (berrs > 0) {
      errors += berrs;
      return;
    }

    KieContainer kc = kies.newKieContainer(kb.getKieModule().getReleaseId());
    DMNRuntime rt = kc.newKieSession().getKieRuntime(DMNRuntime.class);
    List<DMNModel> models = rt.getModels();
    if (models.isEmpty()) {
      System.out.println("MODEL  NO MODELS LOADED");
      errors++;
      return;
    }

    List<Case> jobCases = new ArrayList<>();
    if (casesFile != null) {
      jobCases.addAll(readCases(casesFile));
    }
    if (ctxFile != null || jobCases.isEmpty()) {
      // --ctx, or neither: one unnamed case with no expectations.
      jobCases.add(new Case("(context only)", readContext(ctxFile), null));
    }

    for (DMNModel model : models) {
      System.out.println("MODEL  " + model.getName() + "  ns=" + model.getNamespace());
      for (DMNMessage m : model.getMessages()) {
        System.out.println("       msg " + m.getSeverity() + " " + m.getText());
      }
      List<String> ins = new ArrayList<>();
      for (InputDataNode n : model.getInputs()) {
        ins.add(n.getName() + ":" + typeOf(n.getType()));
      }
      System.out.println("       inputData     " + ins);
      List<String> ds = new ArrayList<>();
      for (DecisionNode n : model.getDecisions()) {
        ds.add(n.getName());
      }
      System.out.println("       decisions     " + ds);
      List<String> bkms = new ArrayList<>();
      for (BusinessKnowledgeModelNode n : model.getBusinessKnowledgeModels()) {
        bkms.add(n.getName());
      }
      System.out.println("       BKMs          " + bkms);
      List<String> svcs = new ArrayList<>();
      for (DecisionServiceNode n : model.getDecisionServices()) {
        svcs.add(n.getName());
      }
      System.out.println("       decisionSvcs  " + svcs);

      for (Case c : jobCases) {
        cases++;
        Map<String, Object> ctx = c.context;
        System.out.println("CASE   " + c.name);
        System.out.println("EVAL   context " + ctx);
        DMNContext dctx = rt.newContext();
        ctx.forEach(dctx::set);
        DMNResult r;
        try {
          r = rt.evaluateAll(model, dctx);
        } catch (Throwable t) {
          System.out.println("       evaluateAll THREW " + t);
          errors++;
          continue;
        }
        for (DMNMessage m : r.getMessages()) {
          System.out.println("       msg " + m.getSeverity() + " " + m.getText());
          // A DMNResult-level ERROR is the ONLY signal a cyclic decision service
          // gives: every decision still reports SUCCEEDED.
          if (m.getSeverity() == DMNMessage.Severity.ERROR) {
            errors++;
          }
        }
        List<String> seen = new ArrayList<>();
        for (DMNDecisionResult dr : r.getDecisionResults()) {
          decisions++;
          seen.add(dr.getDecisionName());
          Object val = dr.getResult();
          DMNDecisionResult.DecisionEvaluationStatus st = dr.getEvaluationStatus();
          String flag = "";
          if (st == DMNDecisionResult.DecisionEvaluationStatus.SUCCEEDED && val == null) {
            flag = "   <<< SUCCEEDED-BUT-NULL";
          } else if (st == DMNDecisionResult.DecisionEvaluationStatus.SKIPPED) {
            flag = "   <<< SKIPPED";
          } else if (st == DMNDecisionResult.DecisionEvaluationStatus.SUCCEEDED) {
            succeeded++;
          } else {
            flag = "   <<< " + st;
          }
          // The value check. A status of SUCCEEDED says the decision ran; only
          // this says it was right.
          if (c.expect != null) {
            if (!c.expect.containsKey(dr.getDecisionName())) {
              flag += "   <<< NO EXPECTATION for this decision";
              errors++;
            } else {
              checked++;
              Object want = c.expect.get(dr.getDecisionName());
              if (sameValue(want, val)) {
                matched++;
              } else {
                flag += "   <<< EXPECTED " + show(want);
              }
            }
          }
          System.out.println(
              "       " + pad(dr.getDecisionName(), 34) + " " + pad(String.valueOf(st), 22)
                  + " = " + show(val) + flag);
        }
        if (c.expect != null) {
          for (String want : c.expect.keySet()) {
            if (!seen.contains(want)) {
              System.out.println("       " + pad(want, 34) + "   <<< EXPECTED but the model has no such decision");
              errors++;
            }
          }
        }

        for (DecisionServiceNode n : model.getDecisionServices()) {
          DMNContext c2 = rt.newContext();
          ctx.forEach(c2::set);
          try {
            DMNResult rs = rt.evaluateDecisionService(model, c2, n.getName());
            System.out.println("SVC    " + n.getName() + " -> " + show(rs.getContext().getAll()));
            for (DMNMessage m : rs.getMessages()) {
              System.out.println("       msg " + m.getSeverity() + " " + m.getText());
              if (m.getSeverity() == DMNMessage.Severity.ERROR) {
                errors++;
              }
            }
          } catch (Throwable t) {
            System.out.println("SVC    " + n.getName() + " THREW " + t);
            errors++;
          }
        }
      }
    }
  }

  /**
   * One named input context, plus the value every decision must produce under it.
   *
   * <p>{@code expect} is null for a bare {@code --ctx}, which checks only that the model RAN.
   */
  private static final class Case {
    final String name;
    final Map<String, Object> context;
    final Map<String, Object> expect;

    Case(String name, Map<String, Object> context, Map<String, Object> expect) {
      this.name = name;
      this.context = context;
      this.expect = expect;
    }
  }

  /**
   * Read {@code {"cases": [{name, context, expect}, ...]}}. Any other key at the top level (such as
   * the {@code note} the shipped fixture carries) is ignored.
   */
  private static List<Case> readCases(File casesFile) throws Exception {
    List<Case> out = new ArrayList<>();
    JsonNode root = new ObjectMapper().readTree(casesFile);
    JsonNode arr = root.get("cases");
    if (arr == null || !arr.isArray() || arr.size() == 0) {
      System.err.println("KieDmnCheck: " + casesFile + " has no non-empty `cases` array");
      System.exit(2);
    }
    int i = 0;
    for (JsonNode c : arr) {
      i++;
      String name = c.hasNonNull("name") ? c.get("name").asText() : ("case " + i);
      Map<String, Object> ctx = objToFeel(c.get("context"));
      // A case with no `expect` would silently degrade to a liveness check, which
      // is the very thing --cases exists to replace. Refuse it.
      if (!c.hasNonNull("expect")) {
        System.err.println("KieDmnCheck: case `" + name + "` has no `expect` block");
        System.exit(2);
      }
      out.add(new Case(name, ctx, objToFeel(c.get("expect"))));
    }
    return out;
  }

  private static Map<String, Object> objToFeel(JsonNode n) {
    Map<String, Object> m = new LinkedHashMap<>();
    if (n == null) {
      return m;
    }
    Iterator<Map.Entry<String, JsonNode>> it = n.fields();
    while (it.hasNext()) {
      Map.Entry<String, JsonNode> e = it.next();
      m.put(e.getKey(), jsonToFeel(e.getValue()));
    }
    return m;
  }

  /**
   * Expected-vs-actual, across the representation gap.
   *
   * <p>KIE hands numbers back as {@link BigDecimal}; the fixture supplies them through the same
   * {@code jsonToFeel} path, so both sides are BigDecimal — but {@code equals} on BigDecimal is
   * scale-sensitive ({@code 2500} != {@code 2500.0}), which would make an expectation fail for a
   * reason that has nothing to do with the answer. {@code compareTo} is the right comparison.
   */
  private static boolean sameValue(Object want, Object got) {
    if (want == null || got == null) {
      return want == got;
    }
    if (want instanceof BigDecimal && got instanceof BigDecimal) {
      return ((BigDecimal) want).compareTo((BigDecimal) got) == 0;
    }
    if (want instanceof List && got instanceof List) {
      List<?> a = (List<?>) want;
      List<?> b = (List<?>) got;
      if (a.size() != b.size()) {
        return false;
      }
      for (int i = 0; i < a.size(); i++) {
        if (!sameValue(a.get(i), b.get(i))) {
          return false;
        }
      }
      return true;
    }
    if (want instanceof Map && got instanceof Map) {
      Map<?, ?> a = (Map<?, ?>) want;
      Map<?, ?> b = (Map<?, ?>) got;
      if (!a.keySet().equals(b.keySet())) {
        return false;
      }
      for (Map.Entry<?, ?> e : a.entrySet()) {
        if (!sameValue(e.getValue(), b.get(e.getKey()))) {
          return false;
        }
      }
      return true;
    }
    return want.equals(got);
  }

  private static Map<String, Object> readContext(File ctxFile) throws Exception {
    Map<String, Object> ctx = new LinkedHashMap<>();
    if (ctxFile == null) {
      return ctx;
    }
    JsonNode root = new ObjectMapper().readTree(ctxFile);
    Iterator<Map.Entry<String, JsonNode>> it = root.fields();
    while (it.hasNext()) {
      Map.Entry<String, JsonNode> e = it.next();
      ctx.put(e.getKey(), jsonToFeel(e.getValue()));
    }
    return ctx;
  }

  private static String typeOf(DMNType t) {
    return t == null ? "?" : String.valueOf(t.getName());
  }

  private static String pad(String s, int n) {
    StringBuilder b = new StringBuilder(s == null ? "null" : s);
    while (b.length() < n) {
      b.append(' ');
    }
    return b.toString();
  }

  private static String show(Object o) {
    if (o == null) {
      return "NULL";
    }
    if (o instanceof BigDecimal) {
      return ((BigDecimal) o).toPlainString();
    }
    return String.valueOf(o);
  }

  /** FEEL numbers are decimal, so a JSON number must not become a double. */
  private static Object jsonToFeel(JsonNode n) {
    if (n.isNull()) {
      return null;
    }
    if (n.isBoolean()) {
      return n.asBoolean();
    }
    if (n.isNumber()) {
      return new BigDecimal(n.asText());
    }
    if (n.isTextual()) {
      return n.asText();
    }
    if (n.isArray()) {
      List<Object> l = new ArrayList<>();
      n.forEach(x -> l.add(jsonToFeel(x)));
      return l;
    }
    if (n.isObject()) {
      Map<String, Object> m = new LinkedHashMap<>();
      n.fields().forEachRemaining(e -> m.put(e.getKey(), jsonToFeel(e.getValue())));
      return m;
    }
    return n.asText();
  }

  private KieDmnCheck() {}
}
