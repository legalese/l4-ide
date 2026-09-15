// Browser entry for the P2a harness. Bundled by build.mjs into dist/app.js.
//
// Exposes `window.harness`, which run.mjs drives through Playwright. Nothing in
// here decides anything: it loads a diagram, switches the token simulator on,
// and reports what the simulator's own services say about it.

import BpmnModeler from "bpmn-js/lib/Modeler";
import TokenSimulationModule from "bpmn-js-token-simulation";
import SimulationSupportModule from "bpmn-js-token-simulation/lib/simulation-support";

import "bpmn-js/dist/assets/diagram-js.css";
import "bpmn-js/dist/assets/bpmn-js.css";
import "bpmn-js/dist/assets/bpmn-font/css/bpmn.css";
import "bpmn-js-token-simulation/assets/css/bpmn-js-token-simulation.css";

const container = document.getElementById("canvas");

const modeler = new BpmnModeler({
  container,
  additionalModules: [TokenSimulationModule, SimulationSupportModule],
});

function get(name) {
  return modeler.get(name);
}

function bo(element) {
  return element.businessObject;
}

function describeElement(element) {
  const b = bo(element);
  const defs = (b.eventDefinitions || []).map((d) => d.$type);
  const mi = b.loopCharacteristics;
  return {
    id: element.id,
    type: b.$type,
    name: b.name || null,
    eventDefinitions: defs,
    multiInstance: mi
      ? {
          type: mi.$type,
          isSequential: !!mi.isSequential,
          loopCardinality: !!mi.loopCardinality,
          loopDataInputRef: !!mi.loopDataInputRef,
          // The text of the condition as bpmn-moddle imported it, so the JSON
          // can say the simulator was *given* it (whether it reads it is a
          // question for its source, not for this census).
          completionCondition: mi.completionCondition
            ? mi.completionCondition.body || null
            : null,
        }
      : null,
    cancelActivity: b.cancelActivity === undefined ? null : !!b.cancelActivity,
    attachedTo: b.attachedToRef ? b.attachedToRef.id : null,
    gatewayDirection: b.gatewayDirection || null,
    outgoing: (element.outgoing || []).map((f) => f.id),
    incoming: (element.incoming || []).map((f) => f.id),
  };
}

function isFlowNode(element) {
  const t = bo(element).$type;
  return (
    !element.labelTarget &&
    !element.waypoints &&
    !/^bpmn:(Process|Participant|Lane|Collaboration|LaneSet)$/.test(t)
  );
}

// What the simulator currently holds: one entry per live scope, with the
// element it sits on and the events the user could trigger from it.
function snapshot() {
  const simulator = get("simulator");
  const scopes = simulator.findScopes({ trait: undefined }) || [];
  const live = scopes.filter((s) => !s.destroyed);
  return {
    scopes: live.map((s) => ({
      id: s.id,
      element: s.element.id,
      elementType: bo(s.element).$type,
      parent: s.parent ? s.parent.id : null,
      completed: !!s.completed,
      failed: !!s.failed,
      running: !!s.running,
      subscriptions: [...s.subscriptions].map((sub) => ({
        element: sub.element ? sub.element.id : null,
        type: sub.event.type,
        interrupting: !!sub.event.interrupting,
        boundary: !!sub.event.boundary,
      })),
    })),
  };
}

// The trigger pads the simulator offers right now, by element id. This is the
// UI's own notion of "what can the user do next", read straight from the DOM
// the same way SimulationSupport.getElementTrigger does.
function triggers() {
  const pads = container.querySelectorAll(
    ".djs-overlays .bts-context-pad:not(.hidden)",
  );
  const out = [];
  pads.forEach((pad) => {
    const overlay = pad.closest(".djs-overlays");
    out.push({
      element: overlay && overlay.getAttribute("data-container-id"),
      title: pad.getAttribute("title"),
    });
  });
  return out;
}

function history() {
  return get("simulationSupport").getHistory();
}

function trace() {
  return get("simulationTrace")
    .getAll()
    .map((ev) => ({
      action: ev.action,
      element: ev.element ? ev.element.id : null,
      scope: ev.scope ? ev.scope.id : null,
      initiator:
        ev.initiator && ev.initiator.element ? ev.initiator.element.id : null,
    }));
}

function log() {
  const entries = container.querySelectorAll(".bts-log .bts-entry");
  return [...entries].map((e) => e.textContent.replace(/\s+/g, " ").trim());
}

function unsupported() {
  const es = get("elementSupport").getUnsupportedElements() || [];
  return es.map((e) => e.id);
}

function fitViewport() {
  const canvas = get("canvas");
  canvas.zoom("fit-viewport", "auto");
  // Leave a margin so the simulator's palette and pads do not sit on the pool edge.
  canvas.zoom(canvas.zoom() * 0.88, "auto");
}

window.harness = {
  async load(xml) {
    const result = await modeler.importXML(xml);
    fitViewport();
    return {
      warnings: result.warnings.map((w) => String(w.message || w)),
      elements: get("elementRegistry").filter(isFlowNode).map(describeElement),
    };
  },

  toggle(active) {
    get("simulationSupport").toggleSimulation(active);
    // The trace only starts recording when asked; start it once mode is on.
    if (active) get("simulationTrace").start();
    // Animations are wall-clock; ask for the fastest speed the UI offers.
    try {
      get("animation").setAnimationSpeed(100);
    } catch (e) {
      /* older API */
    }
    fitViewport();
    return { unsupported: unsupported() };
  },

  // Put a pause point on every activity so a token that reaches one stops
  // there instead of running through. Without this, ActivityBehavior.enter
  // exits immediately (lib/simulator/behaviors/ActivityBehavior.js).
  pauseAtActivities() {
    const simulator = get("simulator");
    const registry = get("elementRegistry");
    const paused = [];
    registry.forEach((el) => {
      const t = bo(el).$type;
      if (
        /^bpmn:(Task|UserTask|BusinessRuleTask|ManualTask|ServiceTask|ScriptTask|CallActivity|SubProcess)$/.test(
          t,
        ) &&
        !el.labelTarget
      ) {
        simulator.waitAtElement(el, true);
        paused.push(el.id);
      }
    });
    return paused;
  },

  trigger(id) {
    get("simulationSupport").triggerElement(id);
    return true;
  },

  // Resolve once the job queue has drained and the animation has had a
  // moment; the simulator is synchronous apart from token animation.
  settle(ms = 400) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  },

  state() {
    return {
      snapshot: snapshot(),
      triggers: triggers(),
      history: history(),
      log: log(),
    };
  },

  trace,
  fitViewport,

  reset() {
    get("resetSimulation").resetSimulation();
    // SimulationTrace has start/stop/getAll and no clear; a reset that kept
    // the old events would let one scenario's end events bleed into the next.
    get("simulationTrace")._events.length = 0;
    fitViewport();
  },

  // Choose which arm an exclusive gateway takes, by index into its outgoing
  // sequence flows in document order. This is exactly what clicking the
  // gateway in the UI cycles through (ExclusiveGatewaySettings.setSequenceFlow).
  setGatewayArm(gatewayId, index) {
    const gateway = get("elementRegistry").get(gatewayId);
    const outgoing = gateway.outgoing.filter(
      (f) => bo(f).$type === "bpmn:SequenceFlow",
    );
    const flow = outgoing[index];
    if (!flow)
      throw new Error(`gateway ${gatewayId} has no outgoing #${index}`);
    get("simulator").setConfig(gateway, { activeOutgoing: flow });
    return flow.id;
  },

  gateways() {
    return get("elementRegistry")
      .filter(
        (el) => bo(el).$type === "bpmn:ExclusiveGateway" && !el.labelTarget,
      )
      .map((el) => ({
        id: el.id,
        arms: el.outgoing
          .filter((f) => bo(f).$type === "bpmn:SequenceFlow")
          .map((f) => f.id),
      }))
      .filter((g) => g.arms.length > 1);
  },

  hideOverlayUi(hide) {
    // The log panel's text is captured in the JSON; hidden in screenshots so it
    // does not sit on top of the bottom lane. The palette and pads stay.
    document.body.classList.toggle("harness-hide-ui", !!hide);
  },
};
