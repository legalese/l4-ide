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
 *   java KieDmnCheck FILE.dmn [--ctx ctx.json] [FILE2.dmn ...]
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

  public static void main(String[] argv) throws Exception {
    // FILE.dmn [--ctx ctx.json] ...: --ctx attaches to the file before it, so
    // several files can be checked in one JVM with a context each.
    List<String[]> jobs = new ArrayList<>(); // {file, ctxOrNull}
    for (int i = 0; i < argv.length; i++) {
      if (argv[i].equals("--ctx")) {
        if (jobs.isEmpty() || i + 1 >= argv.length) {
          System.err.println("KieDmnCheck: --ctx must follow a .dmn file and name a .json file");
          System.exit(2);
        }
        jobs.get(jobs.size() - 1)[1] = argv[++i];
        continue;
      }
      jobs.add(new String[] {argv[i], null});
    }
    if (jobs.isEmpty()) {
      System.err.println("usage: KieDmnCheck FILE.dmn [--ctx ctx.json] ...");
      System.exit(2);
    }

    Schema schema = loadSchema();
    String version = KieServices.Factory.get().getClass().getPackage().getImplementationVersion();
    if (version == null) {
      version = "unknown";
    }

    for (String[] job : jobs) {
      run(schema, new File(job[0]), job[1] == null ? null : new File(job[1]));
    }

    boolean ok = errors == 0 && decisions > 0 && succeeded == decisions;
    System.out.println();
    System.out.println(
        "KIE " + version + " VERDICT: " + files + " file(s), " + errors + " error(s), "
            + warnings + " warning(s), " + succeeded + "/" + decisions + " decision(s) SUCCEEDED"
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

  private static void run(Schema schema, File f, File ctxFile) throws Exception {
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

    Map<String, Object> ctx = readContext(ctxFile);

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
      for (DMNDecisionResult dr : r.getDecisionResults()) {
        decisions++;
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
        System.out.println(
            "       " + pad(dr.getDecisionName(), 34) + " " + pad(String.valueOf(st), 22)
                + " = " + show(val) + flag);
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
