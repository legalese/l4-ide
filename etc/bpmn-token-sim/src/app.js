// Browser entry for the P2a harness. Bundled by build.mjs into dist/app.js.
//
// Exposes `window.harness`, which run.mjs drives through Playwright. Nothing in
// here decides anything: it loads a diagram, switches the token simulator on,
// and reports what the simulator's own services say about it.

import BpmnModeler from "bpmn-js/lib/Modeler";
import TokenSimulationModule from "bpmn-js-token-simulation";
import SimulationSupportModule from "bpmn-js-token-simulation/lib/simulation-support";
import Animation from "bpmn-js-token-simulation/lib/animation/Animation";
import {
  ANIMATION_CREATED_EVENT,
  SCOPE_CREATE_EVENT,
} from "bpmn-js-token-simulation/lib/util/EventHelper";
import randomColor from "randomcolor";

import "bpmn-js/dist/assets/diagram-js.css";
import "bpmn-js/dist/assets/bpmn-js.css";
import "bpmn-js/dist/assets/bpmn-font/css/bpmn.css";
import "bpmn-js-token-simulation/assets/css/bpmn-js-token-simulation.css";

const container = document.getElementById("canvas");

// A token's travel along a sequence flow is, in the simulator, a
// requestAnimationFrame animation (lib/animation/Animation.js) whose `done`
// fires the flow's exit and the next element's entry. Two tokens released by
// one parallel split therefore arrive in whichever order their animations
// complete — and at the 100x speed this harness asks for, both take about one
// frame, so which finishes first depends on where the frame boundary falls.
// That is timing, not routing, and it made `history` (a path in fired order)
// differ between two runs of the same fixture (consultation: `Task_1, Task_4`
// one run, `Task_4, Task_1` the next). (`config.animation.randomize` is not
// the fix: TokenAnimation stores it as `this.randomize` and reads
// `this._randomize`, so the duration was never random to begin with.)
//
// This replaces the animation with one that completes each token's travel on
// a zero-delay timer, in the order the simulator started them — the order of
// the split's outgoing flows in the document. Same `animation` service
// contract (animate / pause / play / clearAnimations on scope destroy), no
// token graphic, so nothing changes in a screenshot taken at rest.
function InstantAnimation(config, canvas, eventBus, scopeFilter) {
  Animation.call(this, config, canvas, eventBus, scopeFilter);
}
InstantAnimation.prototype = Object.create(Animation.prototype);
InstantAnimation.prototype.constructor = InstantAnimation;
InstantAnimation.$inject = Animation.$inject;
InstantAnimation.prototype.createAnimation = function (
  connection,
  scope,
  done = () => {},
) {
  let timer = null;
  let paused = false;
  let pending = true;
  const fire = () => {
    timer = null;
    if (!pending) return;
    pending = false;
    this._animations.delete(animation);
    done();
  };
  const animation = {
    scope,
    element: connection,
    show() {},
    hide() {},
    setSpeed() {},
    pause() {
      paused = true;
      if (timer !== null) clearTimeout(timer);
      timer = null;
    },
    play() {
      paused = false;
      if (pending && timer === null) timer = setTimeout(fire, 0);
    },
    remove() {
      pending = false;
      if (timer !== null) clearTimeout(timer);
      timer = null;
    },
  };
  this._animations.add(animation);
  this._eventBus.fire(ANIMATION_CREATED_EVENT, { animation });
  if (!paused) animation.play();
  return animation;
};

// Each token scope is coloured — its count badge, its "Finished" tag, its log
// lines — from a palette the simulator draws once per page with an unseeded
// `randomColor({ count: 60 })` (lib/features/colored-scopes/ColoredScopes.js),
// so the same run screenshots in different colours every time. This is that
// service verbatim, with a seed, so a screenshot is a function of the run.
function SeededColoredScopes(eventBus) {
  const yiq = (hex) => {
    const r = parseInt(hex.substr(1, 2), 16);
    const g = parseInt(hex.substr(3, 2), 16);
    const b = parseInt(hex.substr(5, 2), 16);
    return (r * 299 + g * 587 + b * 114) / 1000;
  };
  const colors = randomColor({ count: 60, seed: 4 }).filter(
    (c) => yiq(c) < 200,
  );
  let idx = 0;
  eventBus.on(SCOPE_CREATE_EVENT, 1500, ({ scope }) => {
    const { element } = scope;
    if (element && element.type === "bpmn:MessageFlow") {
      scope.colors = { primary: "#999", auxiliary: "#FFF" };
    } else if (scope.parent) {
      scope.colors = scope.parent.colors;
    } else {
      const primary = colors[idx++ % colors.length];
      scope.colors = {
        primary,
        auxiliary: yiq(primary) >= 128 ? "#111" : "#fff",
      };
    }
  });
}
SeededColoredScopes.$inject = ["eventBus"];

const modeler = new BpmnModeler({
  container,
  additionalModules: [
    TokenSimulationModule,
    SimulationSupportModule,
    {
      animation: ["type", InstantAnimation],
      coloredScopes: ["type", SeededColoredScopes],
    },
  ],
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

// The log panel, one record per entry. The simulator renders each entry as
// `<span class="bts-text">…</span><span class="bts-scope" data-scope-id=…>`
// (lib/features/log/Log.js); the scope id is read from its own span rather
// than parsed out of the text, so masking it later cannot touch real text.
function log() {
  const entries = container.querySelectorAll(".bts-log .bts-entry");
  return [...entries].map((e) => {
    const text = e.querySelector(".bts-text");
    const scope = e.querySelector(".bts-scope[data-scope-id]");
    return {
      text: (text ? text.textContent : e.textContent)
        .replace(/\s+/g, " ")
        .trim(),
      scope: scope ? scope.getAttribute("data-scope-id") : null,
    };
  });
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
