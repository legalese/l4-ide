// Second-opinion BPMN checker built on jBPM / KIE (Drools), an engine that is a
// genuinely independent implementation from bpmn-js.
//
// Driven by ../check-bpmn-kie.sh, which is the supported entry point: it
// resolves the pinned dependencies, compiles this file, and SKIPS LOUDLY when
// the Java toolchain is absent. Read that script's header first.
//
// WHY A THIRD CHECKER AT ALL. `etc/validate-bpmn.mjs` answers "will Camunda
// Modeler open this?" and `etc/check-bpmn-soundness.mjs` answers "can the token
// game get stuck?". Both are ours. This one is somebody else's: when it agrees
// that a diagram deadlocks, that agreement is evidence our hand-written token
// semantics are right, because the two implementations share no code and no
// assumptions. It exists to corroborate, not to gate. See the measured results
// in ../../jl4/examples/bpmn/unsound/README.md.
//
// WHAT IT DOES
//   PHASE 0  adapt   jBPM will not even look at the exporter's output as
//                    emitted. Every adaptation is applied in memory and PRINTED,
//                    because each printed line IS a flavor axis between jBPM and
//                    Camunda. Nothing structural is touched: no node, no
//                    sequence flow and no gateway is added, removed or rewired,
//                    with the single exception of A2, which BPMN 2.0 itself
//                    defines as equivalent.
//   PHASE 1  compile through KieBuilder, which runs jBPM's own
//                    RuleFlowProcessValidator.
//   PHASE 2  execute in a KieSession with every work item auto-completing, and
//                    then judge the outcome.
//
// WHAT PHASE 2 JUDGES
//   deadlock      the instance is left ACTIVE: it can reach no end state. This
//                 is the historical exporter defect — a converging parallel
//                 gateway that counted edges rather than tokens. The parked node
//                 instances are named.
//   duplication   in an ACYCLIC process, a node that fires more than once means
//                 tokens were merged by a gateway that passes them through
//                 instead of synchronising them, so everything downstream
//                 happens twice. Cyclicity is tested first and the rule is
//                 skipped when a loop exists, because a loop makes repeat firing
//                 legitimate.
//   fault         an error end event reached is a MODELLED terminal state and is
//                 reported as such, not as a defect.
//
// WHAT IT DOES *NOT* CHECK — read this before trusting a pass
//   * Nothing about the DIAGRAM. jBPM ignores BPMNDI entirely, so every layout
//     defect in the exporter's history is invisible here. `validate-bpmn.mjs` is
//     what covers drawing, and only for presence, not sanity.
//   * Only ONE execution path. Work items auto-complete and boundary timers are
//     therefore never reached, so this explores a single interleaving. It can
//     prove a deadlock exists; it can NEVER prove one absent. That is precisely
//     what `check-bpmn-soundness.mjs` does instead, by exhausting every reachable
//     marking — which is why the soundness check, not this one, is the gate.
//   * Safeness in general. The duplication rule above is a single-run
//     approximation of S4, and it is the check jBPM's own "did it complete?"
//     verdict is blind to: an XOR join placed after a parallel split completes
//     happily while running its whole tail twice.
//   * Whether the adapted file still means what the original meant. A1 and A5
//     supply bindings the exporter never emits; if the exporter starts emitting
//     them, these adaptations must be revisited.
//   * Anything at all about a file it refused in PHASE 0 or PHASE 1.
//
// Exit: 0 = every file compiled and reached an accepted terminal state.
//       1 = a finding. 2 = usage. Never silent.

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.*;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.dom.DOMSource;
import javax.xml.transform.stream.StreamResult;

import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

import org.kie.api.KieServices;
import org.kie.api.builder.KieBuilder;
import org.kie.api.builder.KieFileSystem;
import org.kie.api.builder.Message;
import org.kie.api.builder.ReleaseId;
import org.kie.api.builder.Results;
import org.kie.api.event.process.DefaultProcessEventListener;
import org.kie.api.event.process.ProcessNodeTriggeredEvent;
import org.kie.api.definition.process.NodeContainer;
import org.kie.api.definition.process.Process;
import org.kie.api.definition.process.WorkflowProcess;
import org.kie.api.runtime.KieContainer;
import org.kie.api.runtime.KieSession;
import org.kie.api.runtime.process.NodeInstance;
import org.kie.api.runtime.process.ProcessInstance;
import org.kie.api.runtime.process.WorkItem;
import org.kie.api.runtime.process.WorkItemHandler;
import org.kie.api.runtime.process.WorkItemManager;
import org.kie.api.runtime.process.WorkflowProcessInstance;

public class KieBpmnCheck {

  static final String BPMN = "http://www.omg.org/spec/BPMN/20100524/MODEL";
  static final String BPMNDI = "http://www.omg.org/spec/BPMN/20100524/DI";
  static final String DC = "http://www.omg.org/spec/DD/20100524/DC";
  static final String XSI = "http://www.w3.org/2001/XMLSchema-instance";

  static int problems = 0;

  public static void main(String[] args) throws Exception {
    List<String> files = new ArrayList<>();
    for (String a : args) {
      if (a.startsWith("-")) continue;
      files.add(a);
    }
    if (files.isEmpty()) {
      System.err.println("usage: KieBpmnCheck FILE.bpmn [FILE.bpmn ...]");
      System.err.println("(normally invoked through etc/check-bpmn-kie.sh)");
      System.exit(2);
    }

    System.out.println("jBPM/KIE second opinion  (jbpm-bpmn2 " + jbpmVersion()
        + ", JDK " + System.getProperty("java.version") + ")");

    for (String f : files) {
      try {
        check(new File(f));
      } catch (Throwable t) {
        problems++;
        System.out.println("  HARNESS ERROR " + t.getClass().getName() + ": " + t.getMessage());
      }
    }

    System.out.println();
    System.out.println(problems == 0
        ? "RESULT: no findings. Every file compiled under jBPM and reached an accepted terminal state."
        : "RESULT: " + problems + " file(s) with findings.");
    System.exit(problems == 0 ? 0 : 1);
  }

  static String jbpmVersion() {
    Package p = ProcessInstance.class.getPackage();
    String v = p == null ? null : p.getImplementationVersion();
    return v == null ? "pinned, see etc/kie/pom.xml" : v;
  }

  // -------------------------------------------------------------------------

  static void check(File file) throws Exception {
    System.out.println();
    System.out.println("=========================================================");
    System.out.println("FILE  " + file.getName());
    System.out.println("=========================================================");

    DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
    dbf.setNamespaceAware(true);
    DocumentBuilder db = dbf.newDocumentBuilder();
    // Never reach the network for a schema; a missing DTD must not hang a check.
    db.setEntityResolver((pub, sys) -> new org.xml.sax.InputSource(new java.io.StringReader("")));
    Document doc = db.parse(file);

    List<String> adaptations = adapt(doc);
    System.out.println("[PHASE 0 adapt] " + adaptations.size() + " adaptation(s) — each one is a jBPM-vs-Camunda flavor axis");
    for (String a : adaptations) System.out.println("   " + a);

    String xml = serialize(doc);

    // ---------- PHASE 1: compile ----------
    KieServices ks = KieServices.Factory.get();
    ReleaseId rid = ks.newReleaseId("l4.check", "c" + Math.abs(file.getName().hashCode()), "1.0");
    KieFileSystem kfs = ks.newKieFileSystem();
    kfs.generateAndWritePomXML(rid);
    kfs.write("src/main/resources/proc.bpmn2", xml.getBytes(StandardCharsets.UTF_8));

    KieBuilder kb = ks.newKieBuilder(kfs);
    kb.buildAll();
    Results res = kb.getResults();
    List<Message> errs = res.getMessages(Message.Level.ERROR);

    System.out.println("[PHASE 1 compile] errors=" + errs.size());
    for (Message m : errs) System.out.println("   ERROR   " + firstLine(m.getText()));
    if (!errs.isEmpty()) {
      problems++;
      System.out.println("   -> jBPM REJECTS this file. NOT EXECUTED, so nothing below was checked.");
      return;
    }

    KieContainer kc = ks.newKieContainer(rid);
    boolean acyclic = isAcyclic(doc);
    if (!acyclic)
      System.out.println("   note: the process has a cycle, so the duplication rule is not applied");

    for (Process p : kc.getKieBase().getProcesses()) run(kc, p, acyclic);
  }

  /** Keep multi-line Drools stack dumps from swamping the report. */
  static String firstLine(String s) {
    if (s == null) return "(no message)";
    int i = s.indexOf('\n');
    String head = i == -1 ? s : s.substring(0, i) + " [...]";
    return head.length() > 300 ? head.substring(0, 300) + " [...]" : head;
  }

  // -------------------------------------------------------------------------
  // PHASE 0 — the adaptations, each one a recorded flavor axis
  // -------------------------------------------------------------------------

  static List<String> adapt(Document doc) {
    List<String> log = new ArrayList<>();
    Element proc = first(doc, BPMN, "process");
    if (proc == null) return log;

    // The exporter deliberately marks the diagram non-executable so Camunda will
    // not apply executable-process validation to a picture. To execute it we
    // must flip that -- in this in-memory copy only, never in the exporter.
    if ("false".equals(proc.getAttribute("isExecutable"))) {
      proc.setAttribute("isExecutable", "true");
      log.add("A0  isExecutable false -> true (in memory only; the exporter's choice is deliberate)");
    }

    // A1  abstract <task> has no implementation binding, so jBPM cannot run it.
    //     Camunda and bpmn-moddle accept it. Engine-vs-modeller, not a defect.
    List<Element> tasks = all(doc, BPMN, "task");
    for (Element t : tasks) doc.renameNode(t, BPMN, "bpmn:userTask");
    if (!tasks.isEmpty())
      log.add("A1  <task> -> <userTask> x" + tasks.size()
          + "  (jBPM needs a task type; Camunda accepts abstract <task>)");

    // A2  an end event with N>1 incoming flows is an implicit merge in which
    //     EACH arriving token ends independently, so N single-incoming copies is
    //     exactly equivalent. jBPM's EndNode/FaultNode reject >1 incoming.
    int cloned = fanOutEndEvents(doc, proc);
    if (cloned > 0)
      log.add("A2  split multi-incoming end event(s) into " + cloned
          + " extra copy/copies  (spec-legal implicit merge; jBPM rejects >1 incoming)");

    // A3  a diverging exclusive gateway with no conditionExpression and no
    //     default cannot be decided by ANY engine. This is not a flavor
    //     difference -- it is a real gap in the exporter, the F4 seam where a
    //     referenced DMN decision would supply the guard. We supply a
    //     deterministic stand-in purely so execution can proceed.
    int guards = addMissingGuards(doc, proc);
    if (guards > 0)
      log.add("A3  supplied " + guards + " missing conditionExpression(s) on diverging exclusive gateway(s)"
          + "  — NOT a flavor axis: the exporter emits no guard at all, so no engine could decide the branch");

    // A5  a timer event definition with no timeDuration/timeCycle/timeDate has
    //     no trigger for jBPM to bind.
    int timers = addMissingTimerBodies(doc);
    if (timers > 0)
      log.add("A5  supplied " + timers + " missing timeDuration(s) on timer event definition(s)");

    return log;
  }

  static int fanOutEndEvents(Document doc, Element proc) {
    Map<String, List<Element>> incoming = new LinkedHashMap<>();
    for (Element f : all(doc, BPMN, "sequenceFlow"))
      incoming.computeIfAbsent(f.getAttribute("targetRef"), k -> new ArrayList<>()).add(f);

    List<Element> lanes = all(doc, BPMN, "lane");
    Element plane = first(doc, BPMNDI, "BPMNPlane");
    int cloned = 0;
    for (Element end : all(doc, BPMN, "endEvent")) {
      String eid = end.getAttribute("id");
      List<Element> inc = incoming.getOrDefault(eid, Collections.emptyList());
      if (inc.size() <= 1) continue;
      Element baseShape = shapeFor(doc, eid);
      for (int i = 1; i < inc.size(); i++) {
        String nid = eid + "__" + i;
        Element clone = (Element) end.cloneNode(true);
        clone.setAttribute("id", nid);
        // Child ids (an errorEventDefinition, say) must stay unique too.
        for (Element sub : descendants(clone))
          if (!sub.getAttribute("id").isEmpty()) sub.setAttribute("id", sub.getAttribute("id") + "__" + i);
        proc.appendChild(clone);
        inc.get(i).setAttribute("targetRef", nid);
        cloned++;
        // Keep the lane complete so the pool still lists every node.
        for (Element lane : lanes) {
          boolean here = false;
          for (Element ref : childElements(lane, BPMN, "flowNodeRef"))
            if (eid.equals(text(ref))) here = true;
          if (here) {
            Element ref = doc.createElementNS(BPMN, "bpmn:flowNodeRef");
            ref.setTextContent(nid);
            lane.appendChild(ref);
            break;
          }
        }
        // Keep diagram interchange complete so validate-bpmn.mjs would still pass.
        if (baseShape != null && plane != null) {
          Element sh = (Element) baseShape.cloneNode(true);
          sh.setAttribute("id", "Shape_" + nid);
          sh.setAttribute("bpmnElement", nid);
          Element b = first(sh, DC, "Bounds");
          if (b != null) {
            try {
              b.setAttribute("y", String.valueOf((int) Double.parseDouble(b.getAttribute("y")) + 90 * i));
            } catch (NumberFormatException ignore) { }
          }
          plane.appendChild(sh);
        }
      }
    }
    return cloned;
  }

  static int addMissingGuards(Document doc, Element proc) {
    Map<String, List<Element>> outgoing = new LinkedHashMap<>();
    for (Element f : all(doc, BPMN, "sequenceFlow"))
      outgoing.computeIfAbsent(f.getAttribute("sourceRef"), k -> new ArrayList<>()).add(f);

    int added = 0;
    for (Element gw : all(doc, BPMN, "exclusiveGateway")) {
      List<Element> outs = outgoing.getOrDefault(gw.getAttribute("id"), Collections.emptyList());
      if (outs.size() < 2) continue;
      if (!gw.getAttribute("default").isEmpty()) continue;
      for (int i = 0; i < outs.size(); i++) {
        Element f = outs.get(i);
        if (!childElements(f, BPMN, "conditionExpression").isEmpty()) continue;
        Element c = doc.createElementNS(BPMN, "bpmn:conditionExpression");
        c.setAttributeNS(XSI, "xsi:type", "bpmn:tFormalExpression");
        c.setAttribute("language", "http://www.java.com/java");
        // Deterministic: take the first branch, so the run is reproducible.
        c.setTextContent(i == 0 ? "return true;" : "return false;");
        f.appendChild(c);
        added++;
      }
    }
    return added;
  }

  static int addMissingTimerBodies(Document doc) {
    int added = 0;
    for (Element td : all(doc, BPMN, "timerEventDefinition")) {
      if (!childElements(td, BPMN, "timeDuration").isEmpty()) continue;
      if (!childElements(td, BPMN, "timeCycle").isEmpty()) continue;
      if (!childElements(td, BPMN, "timeDate").isEmpty()) continue;
      Element d = doc.createElementNS(BPMN, "bpmn:timeDuration");
      d.setAttributeNS(XSI, "xsi:type", "bpmn:tFormalExpression");
      d.setTextContent("PT1H");
      td.appendChild(d);
      added++;
    }
    return added;
  }

  // -------------------------------------------------------------------------
  // PHASE 2 — execute and judge
  // -------------------------------------------------------------------------

  static void run(KieContainer kc, Process p, boolean acyclic) {
    Set<String> workNames = new LinkedHashSet<>();
    if (p instanceof WorkflowProcess) collectWork((WorkflowProcess) p, workNames);
    workNames.addAll(Arrays.asList("Human Task", "Task", "Service Task", "Email", "Log", "Rest"));

    KieSession ks = null;
    try {
      ks = kc.newKieSession();
      WorkItemManager mgr = ks.getWorkItemManager();
      for (String n : workNames) mgr.registerWorkItemHandler(n, new AutoComplete());

      final List<String> faults = new ArrayList<>();
      final Map<String, Integer> fires = new LinkedHashMap<>();
      ks.addEventListener(new DefaultProcessEventListener() {
        @Override
        public void beforeNodeTriggered(ProcessNodeTriggeredEvent e) {
          org.kie.api.definition.process.Node n = e.getNodeInstance().getNode();
          if (n == null) return;
          String kind = n.getClass().getSimpleName();
          String label = (n.getName() == null || n.getName().isEmpty() ? "(unnamed)" : n.getName())
              + " [" + kind + "]";
          fires.merge(label, 1, Integer::sum);
          if (kind.equals("FaultNode")) faults.add(n.getName() == null ? kind : n.getName());
        }
      });

      ProcessInstance pi = ks.startProcess(p.getId());
      int state = pi.getState();

      if (state == ProcessInstance.STATE_ACTIVE) {
        System.out.println("[PHASE 2 execute] DEADLOCK — left ACTIVE, cannot reach any end state");
        problems++;
        if (pi instanceof WorkflowProcessInstance) {
          Collection<NodeInstance> live = ((WorkflowProcessInstance) pi).getNodeInstances();
          System.out.println("   " + live.size() + " node instance(s) still holding a token:");
          for (NodeInstance ni : live) {
            org.kie.api.definition.process.Node n = ni.getNode();
            System.out.println("      * " + (n == null ? "?"
                : (n.getName() == null || n.getName().isEmpty() ? "(unnamed)" : n.getName())
                  + " [" + n.getClass().getSimpleName() + "]"));
          }
        }
        return;
      }

      // A node that fires twice in an acyclic process means tokens were passed
      // through a merge instead of synchronised at a join.
      //
      // Join nodes are EXCLUDED, and getting this wrong is an easy false
      // positive. jBPM triggers a converging gateway once per ARRIVING TOKEN --
      // a correct synchronising AND-join is therefore triggered n times and
      // activates once, which is exactly what `consultation.bpmn` does. The
      // signal that separates a real merge defect from a correct join is
      // therefore what happens DOWNSTREAM of it: after a sound AND-join the
      // successor fires once, whereas an XOR gateway used to merge parallel
      // branches passes each token straight through and the successor fires
      // twice. So count every node except the joins themselves.
      List<String> dup = new ArrayList<>();
      if (acyclic)
        for (Map.Entry<String, Integer> e : fires.entrySet())
          if (e.getValue() > 1 && !e.getKey().endsWith("[Join]"))
            dup.add(e.getKey() + " fired " + e.getValue() + "x");

      if (state == ProcessInstance.STATE_ABORTED && !faults.isEmpty())
        System.out.println("[PHASE 2 execute] ABORTED via error end event " + faults
            + " — a modelled terminal state, not a liveness defect");
      else if (state == ProcessInstance.STATE_COMPLETED)
        System.out.println("[PHASE 2 execute] COMPLETED — reaches an end state on the path explored");
      else {
        System.out.println("[PHASE 2 execute] state=" + state + " — unexpected");
        problems++;
      }

      if (!dup.isEmpty()) {
        System.out.println("   DUPLICATION — the process is acyclic, so firing twice means a merge"
            + " passed tokens through where a join should have synchronised them:");
        for (String d : dup) System.out.println("      * " + d);
        System.out.println("   Everything downstream of that merge happens more than once.");
        problems++;
      }
    } catch (Throwable t) {
      problems++;
      System.out.println("[PHASE 2 execute] THREW " + t.getClass().getName() + ": " + t.getMessage());
    } finally {
      if (ks != null) try { ks.dispose(); } catch (Throwable ignore) { }
    }
  }

  static void collectWork(NodeContainer c, Set<String> out) {
    for (org.kie.api.definition.process.Node n : c.getNodes()) {
      try {
        Object w = n.getClass().getMethod("getWork").invoke(n);
        if (w != null) {
          Object name = w.getClass().getMethod("getName").invoke(w);
          if (name != null) out.add(name.toString());
        }
      } catch (Exception ignore) { /* not a work-item node */ }
      if (n instanceof NodeContainer) collectWork((NodeContainer) n, out);
    }
  }

  static class AutoComplete implements WorkItemHandler {
    public void executeWorkItem(WorkItem wi, WorkItemManager mgr) {
      mgr.completeWorkItem(wi.getId(), new HashMap<>());
    }
    public void abortWorkItem(WorkItem wi, WorkItemManager mgr) { }
  }

  // -------------------------------------------------------------------------
  // helpers
  // -------------------------------------------------------------------------

  /** Depth-first search over sequence flows for a back edge. */
  static boolean isAcyclic(Document doc) {
    Map<String, List<String>> succ = new HashMap<>();
    Set<String> nodes = new LinkedHashSet<>();
    for (Element f : all(doc, BPMN, "sequenceFlow")) {
      String s = f.getAttribute("sourceRef"), t = f.getAttribute("targetRef");
      nodes.add(s);
      nodes.add(t);
      succ.computeIfAbsent(s, k -> new ArrayList<>()).add(t);
    }
    Map<String, Integer> mark = new HashMap<>(); // 1 = on stack, 2 = done
    Deque<String[]> stack = new ArrayDeque<>();
    for (String root : nodes) {
      if (mark.getOrDefault(root, 0) != 0) continue;
      stack.push(new String[] { root, "enter" });
      while (!stack.isEmpty()) {
        String[] top = stack.pop();
        if (top[1].equals("exit")) { mark.put(top[0], 2); continue; }
        if (mark.getOrDefault(top[0], 0) == 2) continue;
        mark.put(top[0], 1);
        stack.push(new String[] { top[0], "exit" });
        for (String n : succ.getOrDefault(top[0], Collections.emptyList())) {
          int m = mark.getOrDefault(n, 0);
          if (m == 1) return false; // back edge
          if (m == 0) stack.push(new String[] { n, "enter" });
        }
      }
    }
    return true;
  }

  static Element shapeFor(Document doc, String elementId) {
    for (Element s : all(doc, BPMNDI, "BPMNShape"))
      if (elementId.equals(s.getAttribute("bpmnElement"))) return s;
    return null;
  }

  static List<Element> all(Document doc, String ns, String local) {
    List<Element> out = new ArrayList<>();
    NodeList nl = doc.getElementsByTagNameNS(ns, local);
    for (int i = 0; i < nl.getLength(); i++) out.add((Element) nl.item(i));
    return out;
  }

  static Element first(Document doc, String ns, String local) {
    NodeList nl = doc.getElementsByTagNameNS(ns, local);
    return nl.getLength() == 0 ? null : (Element) nl.item(0);
  }

  static Element first(Element el, String ns, String local) {
    NodeList nl = el.getElementsByTagNameNS(ns, local);
    return nl.getLength() == 0 ? null : (Element) nl.item(0);
  }

  static List<Element> childElements(Element parent, String ns, String local) {
    List<Element> out = new ArrayList<>();
    NodeList nl = parent.getChildNodes();
    for (int i = 0; i < nl.getLength(); i++) {
      Node n = nl.item(i);
      if (n.getNodeType() == Node.ELEMENT_NODE && ns.equals(n.getNamespaceURI())
          && local.equals(n.getLocalName())) out.add((Element) n);
    }
    return out;
  }

  static List<Element> descendants(Element root) {
    List<Element> out = new ArrayList<>();
    NodeList nl = root.getElementsByTagName("*");
    for (int i = 0; i < nl.getLength(); i++) out.add((Element) nl.item(i));
    return out;
  }

  static String text(Element el) {
    return el.getTextContent() == null ? "" : el.getTextContent().trim();
  }

  static String serialize(Document doc) throws Exception {
    Transformer tr = TransformerFactory.newInstance().newTransformer();
    ByteArrayOutputStream bos = new ByteArrayOutputStream();
    tr.transform(new DOMSource(doc), new StreamResult(bos));
    return new String(bos.toByteArray(), StandardCharsets.UTF_8);
  }
}
