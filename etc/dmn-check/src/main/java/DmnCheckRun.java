import de.redsix.dmncheck.result.Severity;
import de.redsix.dmncheck.result.ValidationResult;
import de.redsix.dmncheck.util.ValidatorLoader;
import de.redsix.dmncheck.validators.core.Validator;
import org.camunda.bpm.model.dmn.Dmn;
import org.camunda.bpm.model.dmn.DmnModelInstance;
import org.camunda.bpm.model.dmn.instance.Decision;
import org.camunda.bpm.model.dmn.instance.InputEntry;
import org.camunda.bpm.model.dmn.instance.OutputEntry;
import org.camunda.bpm.model.dmn.instance.Rule;
import org.camunda.bpm.model.xml.instance.ModelElementInstance;

import java.io.File;
import java.io.InputStream;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;
import java.util.TreeMap;
import java.util.stream.Collectors;

/**
 * Run every dmn-check validator over each DMN file, and say which validator said what.
 *
 *   java DmnCheckRun [--tsv FINDINGS.tsv] [--fail-on-warning] FILE.dmn [FILE2.dmn ...]
 *
 * WHY THIS AND NOT de.redsix.dmncheck.cli.Main. The CLI is a thin shell over the same
 * validators (PluginBase.testFile reads the file with Dmn.readModelFromFile and applies
 * every validator), and this class does the same work. It exists because the CLI
 * cannot answer the questions this harness is for, and fails quietly on two of them:
 *
 *   * a file with NO findings prints nothing at all, so "checked and clean" and
 *     "never looked at" are the same output;
 *   * a finding does not name the validator that produced it;
 *   * a file that cannot be read logs the exception message WITHOUT the file name;
 *   * one validator that throws aborts the remaining validators for that file.
 *
 * What is the same: the validator set (ValidatorLoader.getValidators, the CLI's own
 * default), the model reader (Dmn.readModelFromFile, Camunda 7's camunda-dmn-model),
 * and the severities, which are the validators' own. The README records a
 * cross-check of this class's totals against the CLI's over the same files.
 *
 * Nothing here executes a decision. dmn-check reads structure, and a clean verdict is
 * "none of these validators objected", not "this model is right".
 *
 * The last line is a VERDICT banner, printed whenever the run happened at all. The
 * launcher and selftest.sh assert on the banner, not on the exit code, so that
 * "exited 0 without running anything" cannot read as a pass.
 *
 * Exit status: 0 when every file was read, no validator crashed, and there were no
 * ERROR findings (and no WARNINGs either, with --fail-on-warning). That is dmn-check's
 * own rule (PluginBase.testFile) and the Camunda leg's (errors fail the run).
 */
public final class DmnCheckRun {

  private static int files = 0;
  private static int read = 0;
  private static int unreadable = 0;
  private static int crashes = 0;
  private static int errors = 0;
  private static int warnings = 0;
  private static int harnessErrors = 0;

  /** validator simple name -> {errors, warnings} */
  private static final TreeMap<String, int[]> byValidator = new TreeMap<>();

  public static void main(String[] argv) throws Exception {
    List<String> paths = new ArrayList<>();
    String tsvPath = null;
    boolean failOnWarning = false;
    for (int i = 0; i < argv.length; i++) {
      if (argv[i].equals("--tsv") && i + 1 < argv.length) {
        tsvPath = argv[++i];
      } else if (argv[i].equals("--fail-on-warning")) {
        failOnWarning = true;
      } else {
        paths.add(argv[i]);
      }
    }
    if (paths.isEmpty()) {
      System.err.println("usage: DmnCheckRun [--tsv out.tsv] [--fail-on-warning] FILE.dmn ...");
      System.exit(2);
    }

    // OBSERVED, off the jar that is on the classpath, not the constant the launcher
    // passed in: the banner has to be evidence about WHICH dmn-check looked at the file.
    String version = observedVersion();
    String expected = System.getProperty("l4.dmncheck.version.expected", "");
    if (!expected.isEmpty() && !expected.equals(version)) {
      System.out.println(
          "VERSION MISMATCH: pom.xml pins " + expected + " but the classpath loaded " + version
              + " -- delete the cached cp.txt (see run.sh) or reconcile the pin.");
      harnessErrors++;
    }

    // ValidatorLoader finds validators by SCANNING the classpath. A scan that finds
    // nothing would make every file "clean", so zero validators is a broken run.
    List<Validator> validators = ValidatorLoader.getValidators(null, null);
    if (validators.isEmpty()) {
      System.out.println("BROKEN  ValidatorLoader found no validators on the classpath");
      System.out.println("dmn-check " + version + " VERDICT: 0 validator(s) loaded   <<< FAILED");
      System.exit(1);
    }

    PrintWriter tsv = tsvPath == null ? null : new PrintWriter(new File(tsvPath), "UTF-8");
    if (tsv != null) {
      tsv.println("file\tvalidator\tseverity\telement_type\tparent_type\tdecision\telement_id\tmessage");
    }

    for (String path : paths) {
      check(new File(path), validators, tsv);
    }
    if (tsv != null) {
      tsv.close();
    }

    System.out.println();
    System.out.println("BY VALIDATOR (of " + validators.size() + " loaded)");
    for (Validator v : validators.stream()
        .sorted((a, b) -> name(a).compareTo(name(b)))
        .collect(Collectors.toList())) {
      int[] c = byValidator.getOrDefault(name(v), new int[2]);
      System.out.println(
          String.format("  %-42s %5d error(s) %5d warning(s)", name(v), c[0], c[1]));
    }

    boolean ok =
        files > 0
            && unreadable == 0
            && crashes == 0
            && harnessErrors == 0
            && errors == 0
            && (!failOnWarning || warnings == 0);
    System.out.println();
    System.out.println(
        "dmn-check " + version + " (JDK " + System.getProperty("java.version") + ") VERDICT: "
            + files + " file(s), " + read + " read, " + unreadable + " unreadable, " + errors
            + " error(s), " + warnings + " warning(s), " + crashes + " validator crash(es), "
            + validators.size() + " validator(s)" + (ok ? "" : "   <<< FAILED"));
    System.exit(ok ? 0 : 1);
  }

  private static void check(File f, List<Validator> validators, PrintWriter tsv) {
    files++;
    System.out.println();
    System.out.println("=== " + f.getPath() + " ===");

    DmnModelInstance model;
    try {
      model = Dmn.readModelFromFile(f);
    } catch (Throwable t) {
      unreadable++;
      System.out.println("  UNREADABLE  " + oneLine(String.valueOf(t)));
      tsvRow(tsv, f, "(read)", "ERROR", "", "", "", "", String.valueOf(t));
      return;
    }
    read++;

    int found = 0;
    for (Validator v : validators) {
      List<ValidationResult> results;
      try {
        results = v.apply(model);
      } catch (Throwable t) {
        // dmn-check's own CLI would abort the file here; keep going so one crashing
        // validator does not hide what the other twenty found.
        crashes++;
        found++;
        System.out.println("  CRASH       " + name(v) + " threw " + oneLine(String.valueOf(t)));
        tsvRow(tsv, f, name(v), "CRASH", "", "", "", "", String.valueOf(t));
        continue;
      }
      for (ValidationResult r : results) {
        found++;
        boolean isError = r.getSeverity() == Severity.ERROR;
        int[] c = byValidator.computeIfAbsent(name(v), k -> new int[2]);
        if (isError) {
          errors++;
          c[0]++;
        } else {
          warnings++;
          c[1]++;
        }
        ModelElementInstance e = r.getElement();
        System.out.println(
            String.format("  %-10s %s  %s: %s", r.getSeverity(), name(v), describe(e), oneLine(r.getMessage())));
        tsvRow(
            tsv,
            f,
            name(v),
            r.getSeverity().toString(),
            e.getElementType().getTypeName(),
            parentTypeOf(e),
            decisionOf(e),
            nullToEmpty(e.getAttributeValue("id")),
            r.getMessage());
      }
    }
    if (found == 0) {
      System.out.println("  (no findings)");
    }
  }

  private static String name(Validator v) {
    return v.getClass().getSimpleName();
  }

  private static String parentTypeOf(ModelElementInstance e) {
    ModelElementInstance p = e.getParentElement();
    return p == null ? "" : p.getElementType().getTypeName();
  }

  /** The enclosing decision's name, so a finding can be located without reading XML. */
  private static String decisionOf(ModelElementInstance e) {
    for (ModelElementInstance p = e; p != null; p = p.getParentElement()) {
      if (p instanceof Decision) {
        return nullToEmpty(p.getAttributeValue("name"));
      }
    }
    return "";
  }

  private static String describe(ModelElementInstance e) {
    StringBuilder sb = new StringBuilder(e.getElementType().getTypeName());
    String id = e.getAttributeValue("id");
    String nm = e.getAttributeValue("name");
    if (id != null) {
      sb.append(" #").append(id);
    } else if (nm != null) {
      sb.append(" '").append(nm).append('\'');
    } else {
      // An element with neither is usually a REFERENCE (<inputData href="#..."/>
      // inside a <decisionService>) that camunda-dmn-model types by its local name.
      // Say where it lives, so the finding explains itself.
      ModelElementInstance p = e.getParentElement();
      if (p != null) {
        String pid = p.getAttributeValue("id");
        sb.append(" (no id or name; inside ")
            .append(p.getElementType().getTypeName())
            .append(pid == null ? "" : " #" + pid)
            .append(')');
      }
    }
    if (e instanceof Rule) {
      Rule r = (Rule) e;
      String in = r.getInputEntries().stream().map(InputEntry::getTextContent).collect(Collectors.joining(","));
      String out = r.getOutputEntries().stream().map(OutputEntry::getTextContent).collect(Collectors.joining(","));
      sb.append(" [").append(trunc(oneLine(in), 70)).append(" -> ").append(trunc(oneLine(out), 40)).append(']');
    }
    String d = decisionOf(e);
    if (!d.isEmpty()) {
      sb.append(" in decision '").append(d).append('\'');
    }
    return sb.toString();
  }

  private static String observedVersion() {
    try (InputStream in =
        ValidatorLoader.class.getResourceAsStream(
            "/META-INF/maven/de.redsix/dmn-check-validators/pom.properties")) {
      if (in == null) {
        return "unknown";
      }
      Properties p = new Properties();
      p.load(in);
      return p.getProperty("version", "unknown");
    } catch (Exception e) {
      return "unknown";
    }
  }

  private static void tsvRow(
      PrintWriter tsv,
      File f,
      String validator,
      String severity,
      String type,
      String parentType,
      String decision,
      String id,
      String msg) {
    if (tsv == null) {
      return;
    }
    tsv.println(
        String.join(
            "\t",
            clean(f.getPath()),
            clean(validator),
            clean(severity),
            clean(type),
            clean(parentType),
            clean(decision),
            clean(id),
            clean(msg)));
  }

  private static String clean(String s) {
    return s.replace('\t', ' ').replace('\n', ' ').replace('\r', ' ');
  }

  private static String oneLine(String s) {
    return trunc(clean(s), 400);
  }

  private static String trunc(String s, int n) {
    return s.length() <= n ? s : s.substring(0, n - 1) + "…";
  }

  private static String nullToEmpty(String s) {
    return s == null ? "" : s;
  }
}
