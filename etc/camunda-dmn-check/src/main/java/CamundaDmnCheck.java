import com.fasterxml.jackson.databind.ObjectMapper;
import io.camunda.zeebe.dmn.DecisionContext;
import io.camunda.zeebe.dmn.DecisionEngine;
import io.camunda.zeebe.dmn.DecisionEngineFactory;
import io.camunda.zeebe.dmn.DecisionEvaluationResult;
import io.camunda.zeebe.dmn.ParsedDecision;
import io.camunda.zeebe.dmn.ParsedDecisionRequirementsGraph;
import org.msgpack.jackson.dataformat.MessagePackFactory;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Take an emitted DMN 1.3 file to Camunda 8 and report what the ENGINE says.
 *
 *   java CamundaDmnCheck FILE.dmn [--ctx ctx.json | --cases cases.json] [FILE2.dmn ...]
 *
 * --ctx supplies one input context and checks only that the model RAN. --cases
 * supplies a list of {name, context, expect} and additionally checks WHAT IT
 * ANSWERED, symmetrically: every decision must be named in `expect`, and every
 * name in `expect` must be a decision, so adding a decision without an
 * expectation is a failure rather than a silent gap.
 *
 * PREFER --cases, and the reason is measured on THIS engine. `5/5 evaluated` is
 * a liveness claim. Given a model declaring `annual income` = 100000, `annual` =
 * 5 and `come` = [1,2,5], Camunda 8.7.6 answers `true` to the expression
 * `annual income` -- identically to `annual in come` -- where KIE 8.44 answers
 * 100000. That is a wrong NON-NULL value, so the null check below does not catch
 * it and neither does isFailure(). Only an expected value does.
 *
 * Two legs, which is all Camunda 8 offers on the evaluation side:
 *
 *   PARSE  DecisionEngine.parse() + isValid(). There is no separate validator
 *          API: a Camunda model is either loadable or it is not.
 *   EVAL   evaluateDecisionById for every decision the parse found, with the
 *          supplied context. Required decisions are evaluated transitively.
 *
 * WHY PARSE MATTERS MORE HERE THAN ANYWHERE ELSE. Camunda 8 fails whole-file. A
 * <knowledgeRequirement> whose requiredKnowledge points at a <decisionService>
 * makes parse() throw ClassCastException — DecisionServiceImpl cannot be cast to
 * BusinessKnowledgeModel — and the entire DRG is rejected before any decision
 * runs, with no diagnostic naming the cause. Deleting that one element makes the
 * same file parse and evaluate. That is measured (§13.4) and it is the whole
 * reason DmnFlavor exists. So parse() is wrapped in a catch of Throwable, not of
 * Exception: an Error here must be reported, not propagated as a crash that
 * looks like a broken harness.
 *
 * A decision that evaluates to null is counted as a failure -- necessary, but on
 * its own not sufficient, per the measurement above. Reading only isFailure()
 * would pass a file that answers null; reading only isFailure() and null would
 * pass a file that answers `true` where a number was meant.
 *
 * On success the last line is a VERDICT banner. The test harness asserts the
 * BANNER, not the exit code, so that "exited 0 without running anything" cannot
 * read as a pass.
 */
public final class CamundaDmnCheck {

  private static final ObjectMapper MSGPACK = new ObjectMapper(new MessagePackFactory());
  private static final ObjectMapper JSON = new ObjectMapper();

  private static int files = 0;
  private static int parsed = 0;
  private static int decisions = 0;
  private static int evaluated = 0;
  private static int errors = 0;
  private static int cases = 0;
  private static int checked = 0;
  private static int matched = 0;

  public static void main(String[] argv) throws Exception {
    List<String[]> jobs = new ArrayList<>(); // {file, ctxOrNull, casesOrNull}
    for (int i = 0; i < argv.length; i++) {
      if (argv[i].equals("--ctx") || argv[i].equals("--cases")) {
        int slot = argv[i].equals("--ctx") ? 1 : 2;
        if (jobs.isEmpty() || i + 1 >= argv.length) {
          System.err.println(
              "CamundaDmnCheck: " + argv[i] + " must follow a .dmn file and name a .json file");
          System.exit(2);
        }
        jobs.get(jobs.size() - 1)[slot] = argv[++i];
        continue;
      }
      jobs.add(new String[] {argv[i], null, null});
    }
    if (jobs.isEmpty()) {
      System.err.println("usage: CamundaDmnCheck FILE.dmn [--ctx c.json | --cases cs.json] ...");
      System.exit(2);
    }

    // OBSERVED, off the jar that is actually on the classpath -- not the constant
    // the launcher passed in. The banner has to be evidence about WHICH ENGINE
    // looked at the file, and a number echoed from a shell variable is not that.
    Package p = DecisionEngineFactory.class.getPackage();
    String version = p == null ? null : p.getImplementationVersion();
    if (version == null) {
      version = "unknown";
    }
    // ...and cross-checked against the pin in pom.xml, so that a stale cached
    // classpath or an edited pom cannot leave the banner naming a version that
    // was never loaded.
    String expected = System.getProperty("l4.camunda.version.expected", "");
    if (!expected.isEmpty() && !expected.equals(version)) {
      System.out.println(
          "VERSION MISMATCH: pom.xml pins " + expected + " but the classpath loaded " + version
              + " -- delete the cached cp.txt (see run.sh) or reconcile the pin.");
      errors++;
    }

    DecisionEngine engine = DecisionEngineFactory.createDecisionEngine();
    for (String[] job : jobs) {
      run(
          engine,
          new File(job[0]),
          job[1] == null ? null : new File(job[1]),
          job[2] == null ? null : new File(job[2]));
    }

    boolean ok =
        errors == 0
            && parsed == files
            && files > 0
            && decisions > 0
            && evaluated == decisions
            && matched == checked;
    System.out.println();
    System.out.println(
        "Camunda " + version + " (zeebe-dmn) VERDICT: " + files + " file(s), " + cases
            + " case(s), " + parsed + " parsed, " + errors + " error(s), " + evaluated + "/"
            + decisions + " decision(s) evaluated, " + matched + "/" + checked
            + " value(s) as expected" + (ok ? "" : "   <<< FAILED"));
    System.exit(ok ? 0 : 1);
  }

  private static void run(DecisionEngine engine, File f, File ctxFile, File casesFile)
      throws Exception {
    files++;
    System.out.println();
    System.out.println("=== " + f.getName() + " ===");

    ParsedDecisionRequirementsGraph drg;
    try (InputStream in = new FileInputStream(f)) {
      drg = engine.parse(in);
    } catch (Throwable t) {
      // parse() throws, whole-file, on a knowledgeRequirement -> decisionService.
      System.out.println("PARSE  THREW " + t);
      errors++;
      return;
    }
    if (!drg.isValid()) {
      System.out.println("PARSE  INVALID: " + drg.getFailureMessage());
      errors++;
      return;
    }
    parsed++;
    System.out.println(
        "PARSE  ok: " + drg.getName() + " (" + drg.getDecisions().size() + " decision(s))");

    List<Case> jobCases = new ArrayList<>();
    if (casesFile != null) {
      jobCases.addAll(readCases(casesFile));
    }
    if (ctxFile != null || jobCases.isEmpty()) {
      // --ctx, or neither: one unnamed case with no expectations.
      jobCases.add(new Case("(context only)", readContext(ctxFile), null));
    }

    for (Case c : jobCases) {
      cases++;
      final Map<String, Object> vars = c.context;
      System.out.println("CASE   " + c.name);
      System.out.println("EVAL   context " + vars);
      DecisionContext ctx = () -> vars;

      // Camunda names a decision by NAME in the model but addresses it by ID
      // here; the expectations are written against the name, which is the FEEL
      // name and therefore the thing under test.
      List<String> seen = new ArrayList<>();
      for (ParsedDecision d : drg.getDecisions()) {
        decisions++;
        seen.add(d.getName());
        DecisionEvaluationResult r;
        try {
          r = engine.evaluateDecisionById(drg, d.getId(), ctx);
        } catch (Throwable t) {
          System.out.println("       " + pad(d.getName(), 40) + " THREW " + t);
          errors++;
          continue;
        }
        if (r.isFailure()) {
          System.out.println(
              "       " + pad(d.getName(), 40) + " FAILED " + trim(r.getFailureMessage()));
          errors++;
          continue;
        }
        byte[] bs = new byte[r.getOutput().capacity()];
        r.getOutput().getBytes(0, bs);
        Object val = MSGPACK.readValue(bs, Object.class);
        if (val == null) {
          // Necessary but not sufficient: see the class comment. A mis-resolved
          // FEEL name does not throw, and often does not even answer null.
          System.out.println("       " + pad(d.getName(), 40) + " = NULL   <<< EVALUATED-TO-NULL");
          errors++;
          continue;
        }
        evaluated++;
        String flag = "";
        if (c.expect != null) {
          if (!c.expect.containsKey(d.getName())) {
            flag = "   <<< NO EXPECTATION for this decision";
            errors++;
          } else {
            checked++;
            Object want = c.expect.get(d.getName());
            if (sameValue(want, val)) {
              matched++;
            } else {
              flag = "   <<< EXPECTED " + want;
            }
          }
        }
        System.out.println("       " + pad(d.getName(), 40) + " = " + val + flag);
      }
      if (c.expect != null) {
        for (String want : c.expect.keySet()) {
          if (!seen.contains(want)) {
            System.out.println(
                "       " + pad(want, 40) + "   <<< EXPECTED but the model has no such decision");
            errors++;
          }
        }
      }
    }
  }

  /** One named input context, plus the value every decision must produce under it. */
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
   * Read {@code {"cases": [{name, context, expect}, ...]}}. Any other top-level key (such as the
   * {@code note} the shipped fixture carries) is ignored. A case without {@code expect} is refused
   * rather than degraded to a liveness check.
   */
  @SuppressWarnings("unchecked")
  private static List<Case> readCases(File casesFile) throws Exception {
    List<Case> out = new ArrayList<>();
    Map<String, Object> root = JSON.readValue(casesFile, Map.class);
    Object arr = root.get("cases");
    if (!(arr instanceof List) || ((List<Object>) arr).isEmpty()) {
      System.err.println("CamundaDmnCheck: " + casesFile + " has no non-empty `cases` array");
      System.exit(2);
    }
    int i = 0;
    for (Object o : (List<Object>) arr) {
      i++;
      Map<String, Object> c = (Map<String, Object>) o;
      String name = c.get("name") == null ? ("case " + i) : String.valueOf(c.get("name"));
      if (c.get("expect") == null) {
        System.err.println("CamundaDmnCheck: case `" + name + "` has no `expect` block");
        System.exit(2);
      }
      out.add(
          new Case(
              name,
              (Map<String, Object>) c.getOrDefault("context", new LinkedHashMap<String, Object>()),
              (Map<String, Object>) c.get("expect")));
    }
    return out;
  }

  /**
   * Expected-vs-actual, across the representation gap.
   *
   * <p>The engine hands results back as MessagePack, so a FEEL number arrives as whatever Jackson
   * decodes it to -- Integer, Long, Double or BigInteger, depending on magnitude and scale -- while
   * the fixture's numbers come off plain JSON. Comparing those with {@code equals} would fail on
   * representation rather than on the answer, so numbers are compared as {@link BigDecimal}.
   */
  private static boolean sameValue(Object want, Object got) {
    if (want == null || got == null) {
      return want == got;
    }
    if (want instanceof Number && got instanceof Number) {
      return new BigDecimal(want.toString()).compareTo(new BigDecimal(got.toString())) == 0;
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

  @SuppressWarnings("unchecked")
  private static Map<String, Object> readContext(File ctxFile) throws Exception {
    if (ctxFile == null) {
      return new LinkedHashMap<>();
    }
    return JSON.readValue(ctxFile, Map.class);
  }

  private static String pad(String s, int n) {
    StringBuilder b = new StringBuilder(s == null ? "null" : s);
    while (b.length() < n) {
      b.append(' ');
    }
    return b.toString();
  }

  private static String trim(String s) {
    if (s == null) {
      return "(no message)";
    }
    return s.length() > 400 ? s.substring(0, 400) + "..." : s;
  }

  private CamundaDmnCheck() {}
}
