/**
 * `LadderController` — every browser-facing behaviour of an interactive ladder, and no
 * framework (EMBEDDABLE.md §3.1, E1-IDE-INTEGRATION.md:104 as amended 2026-07-27).
 *
 * The split, and it is the whole point: the controller owns **layout + the DOM**. It does
 * not own valuation, evaluation, or the verdict — those belong to a model, and the model
 * already exists (`LadderModel`). The seam is `ViewSpec` in, a delegated `ClickAct` out.
 * Layout lives here rather than host-side because it is parameterised by `TextMetrics`, the
 * one genuinely browser-shaped input; put it host-side and every consumer re-writes the same
 * three lines and picks its own metrics backend — which is exactly the bug this replaces,
 * where both demos ran on `estimateMetrics`.
 *
 * Pure halves live next door on purpose: `viewport.ts` (seam S6's arithmetic) and `flip.ts`
 * (the FLIP index + delta) are DOM-free and unit-tested. What is left in this file is
 * listener plumbing, `innerHTML`, sizing, `requestAnimationFrame` and `ResizeObserver` — and
 * that residue is what the manual checklist below exists for.
 *
 * ## Manual gate (there is no DOM test environment, deliberately)
 *
 * A `jsdom`/`happy-dom` dependency is the merge-queue hazard EMBEDDABLE.md §3.5 flags, and it
 * would buy machine coverage of ~90 lines of event-to-argument translation. So the untested-
 * by-machine surface is exactly: listener attach/detach, `innerHTML`, `setPointerCapture`,
 * the double-rAF, `ResizeObserver`. Its gate is this list.
 *
 * Each item names what to LOOK at, not just what to do — "the diagram appeared" passes a
 * checklist while pan/zoom is entirely dead, because every viewport-dependent method
 * early-returns on a null `#vb` in silence (see `#viewport`, which measures `clientWidth`
 * on the `<svg>`: if a host's height chain is broken that reads 0, `#draw` skips the
 * viewBox, and `fit`/`zoom`/`pan`/`#onWheel` all no-op with nothing in the console).
 *
 *  1. `npm run standalone -w @repo/ladder-svg`, open `standalone/dist/index.html`:
 *     a click on a box cycles it; a click on a caret folds AND animates; drag pans;
 *     ⌘/ctrl-wheel zooms AT THE CURSOR — watch the `viewBox` ATTRIBUTE change in devtools,
 *     which is the check that distinguishes "zoom works" from "zoom silently no-ops";
 *     a PLAIN wheel scrolls the page BEFORE anything has been clicked (after a click the
 *     host has focus and zooms, which is EMBEDDABLE §3.3's stated rule, not a bug);
 *     double-click fits; the `fit` button visibly RE-FRAMES; a drag that ENDS on a box does
 *     not cycle it; resizing the window keeps the picture framed.
 *  2. Still in demo 1, and this is the one item with a written claim riding on it: zoom in
 *     ~3×, then fold a group. The boxes must land where they end up, NOT overshoot by ~3×.
 *     That is the FLIP-scale question — `#playFlip` passes 1 to `flipMoves` on the reasoning
 *     that a CSS transform inside an `<svg>` resolves in user units, and seam S6's row in
 *     E1-IDE-INTEGRATION.md records that as a correction to the plan. If it overshoots, the
 *     code and that spec row are wrong TOGETHER and must be retracted together.
 *  3. `npm run playground -w @repo/ladder-svg`, paste an inert-style module: hydration still
 *     splices, `lad-ref` dotting still appears (that is `onRender` working), collapse still
 *     works, the sentence list still updates.
 *  4. `npm run dev -w l4-ladder-visualizer`: `LadderSvg` renders beside `Flow`; the header
 *     shows a VERDICT word, not "evaluates to …"; the sidebar assigns T/F/? and the picture
 *     follows; reset works; a repeated atom changes in BOTH positions.
 *  5. Same page, tick `dark palette (seam S8)`: the DIAGRAM turns dark, not just the card
 *     behind it, and the header's verdict colour follows it. (That is `setTheme` — the prop
 *     used to be read once at mount, which made the checkbox a no-op that a checklist would
 *     have ticked.)
 */
import { layout } from "@repo/ladder-core";
import type {
  ClickAct,
  FunDecl,
  Pt,
  Scene,
  TextMetrics,
  Theme,
  ViewSpec,
} from "@repo/ladder-core";
import { sceneToSvg } from "./svg.js";
import { canvasMetrics } from "./metrics.js";
import { paletteFor } from "./palette.js";
import type { Palette } from "./palette.js";
import {
  DEFAULT_LIMITS,
  clampBox,
  fitBox,
  panBy,
  refit,
  viewBoxAttr,
  zoomAt,
} from "./viewport.js";
import type { Box, Size, ZoomLimits } from "./viewport.js";
import { flipIndex, flipKeyFor, flipMoves } from "./flip.js";
import type { FlipKey, Pos } from "./flip.js";

export interface LadderControllerOpts {
  /** Metrics for layout. Default `canvasMetrics()`; a headless caller injects `measure`,
   *  or skips metrics entirely via `renderScene`. */
  readonly metrics?: TextMetrics;
  /** `"screen"` | `"ink"` | a full `Palette` (seam S8). Default `"screen"`. Changeable
   *  afterwards with `setTheme` — a host whose theme can flip at runtime needs that. */
  readonly theme?: Theme | Palette;
  /** Off ⇒ NO listeners are attached at all: a static picture. Default true.
   *  It also turns `panZoom` off by default, because EMBEDDABLE.md §4.2 defines the
   *  `interactive`-absent contract as "no listeners, **no pan/zoom**, no cursor change" —
   *  and because `panZoom` is what imposes the definite-height requirement on the host.
   *  `{ interactive: false, panZoom: true }` is still reachable, and is a fitted-but-static
   *  picture: no gestures, but the `ResizeObserver` still keeps it framed. */
  readonly interactive?: boolean;
  /** FLIP between scenes. Default true. */
  readonly animate?: boolean;
  /** viewBox pan/zoom + fit (seam S6). Defaults to whatever `interactive` is. Off ⇒ the
   *  pre-Step-4 sizing (`max-width:100%; height:auto`) and the host's own `overflow`
   *  scrolling, which is the static/print/doc-figure contract. */
  readonly panZoom?: boolean;
  /** Multiples of the FIT scale; default `{ min: 0.5, max: 8 }`. */
  readonly zoomLimits?: ZoomLimits;
  readonly onAct?: (act: ClickAct) => void;
  /**
   * Called immediately after the new `<svg>` is in the host and sized, BEFORE the FLIP
   * invert. The one hook a host needs to decorate individual nodes it cannot express as a
   * `ViewSpec`: `standalone/playground.ts` marks `lad-ref` / `lad-hydrated` this way. Do not
   * mutate geometry here — the FLIP baseline has already been captured.
   */
  readonly onRender?: (svg: SVGSVGElement, scene: Scene) => void;
}

/** Cumulative pointer travel, in px, past which a gesture counts as a pan and the trailing
 *  `click` is suppressed. Without this every pan that starts on a box ends by cycling it. */
const DRAG_SLOP = 3;

/**
 * Which act (if any) an element's data-attrs denote. Pure and exported so the routing rule
 * is testable without a DOM. `svg.ts`'s `actAttr` emits at most one of the two, so the
 * precedence never fires in practice; it is defensive.
 */
export function actFromAttrs(
  dataValue: string | null,
  dataFold: string | null,
): ClickAct | null {
  if (dataValue !== null) {
    const id = Number(dataValue);
    return Number.isFinite(id) && dataValue.trim() !== ""
      ? { t: "value", id }
      : null;
  }
  if (dataFold !== null) {
    const id = Number(dataFold);
    return Number.isFinite(id) && dataFold.trim() !== ""
      ? { t: "fold", id }
      : null;
  }
  return null;
}

export class LadderController {
  readonly #host: HTMLElement;
  readonly #metrics: TextMetrics;
  #pal: Palette;
  readonly #interactive: boolean;
  readonly #animate: boolean;
  readonly #panZoom: boolean;
  readonly #limits: ZoomLimits;
  readonly #onAct?: (act: ClickAct) => void;
  readonly #onRender?: (svg: SVGSVGElement, scene: Scene) => void;

  #fn: FunDecl;
  #lastScene: Scene | null = null;
  #lastSvgString = "";
  #svg: SVGSVGElement | null = null;
  #content: Size = { w: 0, h: 0 };
  #vb: Box | null = null;
  #vpCache: Size = { w: 0, h: 0 };

  #dragging = false;
  #dragged = false;
  #dragTravel = 0;
  #lastPointer: Pt = { x: 0, y: 0 };
  #raf1 = 0;
  #raf2 = 0;
  #ro: ResizeObserver | null = null;
  #destroyed = false;
  /** What the constructor overwrote on the caller's element, so `destroy()` can put it back
   *  rather than leaving a stray tab stop and a clipped box behind. */
  #addedTabindex = false;
  #priorOverflow = "";
  #priorPosition = "";

  constructor(host: HTMLElement, fn: FunDecl, opts: LadderControllerOpts = {}) {
    this.#host = host;
    this.#fn = fn;
    this.#metrics = opts.metrics ?? canvasMetrics();
    this.#pal = paletteFor(opts.theme ?? "screen");
    this.#interactive = opts.interactive ?? true;
    this.#animate = opts.animate ?? true;
    // `panZoom` follows `interactive` unless it is asked for explicitly. EMBEDDABLE §4.2
    // defines the static contract as "no listeners, no pan/zoom", and pan/zoom is also what
    // requires the host to have a definite height — so `{ interactive: false }` alone must
    // not silently leave a static embed sized `height:100%` inside an auto-height parent.
    this.#panZoom = opts.panZoom ?? this.#interactive;
    this.#limits = opts.zoomLimits ?? DEFAULT_LIMITS;
    this.#onAct = opts.onAct;
    this.#onRender = opts.onRender;

    if (this.#panZoom) {
      // the viewBox only means something against a fixed viewport, so the host must clip
      // rather than scroll — and it must have a definite height (the demos and the Svelte
      // shell each set one in their own CSS).
      this.#priorOverflow = host.style.overflow;
      this.#priorPosition = host.style.position;
      host.style.overflow = "hidden";
      if (!host.style.position) host.style.position = "relative";
    }

    // EVERY listener is attached once, here, on the HOST — never on the <svg>, which
    // `innerHTML` replaces on every render. That is why `app.ts`'s O(nodes) per-render
    // re-attach disappears rather than moving.
    if (this.#interactive) {
      host.addEventListener("click", this.#onClick);
      if (this.#panZoom) {
        host.addEventListener("pointerdown", this.#onPointerDown);
        host.addEventListener("pointermove", this.#onPointerMove);
        host.addEventListener("pointerup", this.#onPointerUp);
        host.addEventListener("pointercancel", this.#onPointerCancel);
        host.addEventListener("wheel", this.#onWheel, { passive: false });
        host.addEventListener("dblclick", this.#onDblClick);
        host.addEventListener("keydown", this.#onKeyDown);
        if (!host.hasAttribute("tabindex")) {
          host.setAttribute("tabindex", "0");
          this.#addedTabindex = true;
        }
      }
    }

    // The observer is a SIZING concern, not an interaction one, so it sits outside the
    // `interactive` guard: without it the viewBox aspect drifts from the viewport's the
    // moment the container changes shape, `preserveAspectRatio` starts letterboxing, and
    // viewport.ts's whole invariant is void. A fitted-but-static embed needs it most,
    // because it has no gesture with which to recover.
    if (this.#panZoom) {
      this.#ro =
        typeof ResizeObserver !== "undefined"
          ? new ResizeObserver(() => this.#onResize())
          : null;
      this.#ro?.observe(host);
    }
  }

  /* --------------------------------------------------------------------- rendering */

  /** Lay out under `vs` with the injected metrics, draw, and FLIP from the previous scene.
   *  Returns the Scene so the host can read `size` / prims (Step 6b's overlay will). */
  render(vs: ViewSpec): Scene {
    const scene = layout(this.#fn, vs, this.#metrics);
    this.#draw(scene);
    return scene;
  }

  /** Escape hatch for a caller that already has a Scene (a worker, a cache, a golden).
   *  Bypasses metrics entirely; still FLIPs, still routes clicks. */
  renderScene(scene: Scene): void {
    this.#draw(scene);
  }

  /**
   * Swap the source tree — a live re-fetch, or a host that rebuilds the drawn tree each
   * frame. By default this invalidates the FLIP baseline and refits, because a different
   * tree has no meaningful correspondence with the old one.
   *
   * `keepBaseline` is for the case where it does: `standalone/playground.ts` rebuilds its
   * display tree on EVERY render (hydration splices a referenced DECIDE in place), and there
   * the FLIP is exactly the affordance that shows what happened.
   */
  setFunDecl(fn: FunDecl, keepBaseline = false): void {
    this.#fn = fn;
    if (!keepBaseline) {
      this.#lastScene = null;
      this.#vb = null;
    }
  }

  /**
   * Re-theme in place (seam S8). The palette is a constructor option, but a host's theme can
   * flip while the diagram is on screen — a dark-mode toggle, a `--vscode-*` change under
   * Step 5 — and remounting to recolour would throw away the user's pan/zoom and the FLIP
   * baseline. Re-emits the last Scene with no animation and no refit, so nothing moves but
   * the colours. A no-op before the first draw; the constructor's `theme` already applies.
   */
  setTheme(theme: Theme | Palette): void {
    this.#pal = paletteFor(theme);
    if (this.#lastScene) this.#draw(this.#lastScene, false);
  }

  /** The last emitted string, verbatim — for a host that wants to export or cache it. */
  toSvgString(): string {
    return this.#lastSvgString;
  }

  #draw(scene: Scene, animate = true): void {
    if (this.#destroyed) return;
    const oldIdx =
      animate && this.#animate && this.#lastScene
        ? flipIndex(this.#lastScene)
        : null;
    const sizeChanged =
      !this.#lastScene ||
      relDiff(this.#lastScene.size.w, scene.size.w) > 0.02 ||
      relDiff(this.#lastScene.size.h, scene.size.h) > 0.02;

    this.#content = { w: scene.size.w, h: scene.size.h };
    this.#lastSvgString = sceneToSvg(scene, this.#pal);
    this.#host.innerHTML = this.#lastSvgString;

    const svg = this.#host.querySelector("svg");
    this.#svg = svg as SVGSVGElement | null;
    if (this.#svg) {
      this.#applySizing(this.#svg);
      if (this.#panZoom) {
        const vp = this.#viewport();
        if (vp.w > 0 && vp.h > 0) {
          // fit on the first draw and whenever the picture changes shape; otherwise keep
          // the user where they were (a value cycle must not yank the view).
          this.#vb =
            !this.#vb || sizeChanged
              ? fitBox(this.#content, vp)
              : clampBox(this.#vb, this.#content);
          this.#vpCache = vp;
          this.#applyViewBox();
        }
        // a host that is 0×0 (display:none, or not yet laid out) leaves `#vb` null and
        // keeps the emitted `viewBox="0 0 w h"`; the ResizeObserver fits when it appears.
      }
      this.#onRender?.(this.#svg, scene);
      if (oldIdx) this.#playFlip(this.#svg, oldIdx, scene);
    }
    this.#lastScene = scene;
  }

  #applySizing(svg: SVGSVGElement): void {
    if (this.#panZoom) {
      // `height:auto` is incompatible with a viewBox-driven zoom: the element needs a fixed
      // viewport for the viewBox to mean anything, so the host supplies the height.
      svg.setAttribute("width", "100%");
      svg.setAttribute("height", "100%");
      svg.setAttribute("preserveAspectRatio", "xMidYMid meet");
      svg.style.display = "block";
      svg.style.touchAction = "none"; // pointer pan on touch
      // The EMITTED backdrop rect is sized to the content box, which used to be the whole
      // picture because the viewBox was `0 0 w h`. Under pan/zoom it is not: `fitBox` leaves
      // FIT_PAD on each side and `clampBox` permits CLAMP_MARGIN of overscroll, and those
      // bands would show the host page through. Painting the live element (not the emitted
      // string, which stays byte-identical) closes them.
      svg.style.background = this.#pal.bg;
    } else {
      svg.style.maxWidth = "100%";
      svg.style.height = "auto";
      svg.style.display = "block";
    }
  }

  #applyViewBox(): void {
    if (this.#svg && this.#vb)
      this.#svg.setAttribute("viewBox", viewBoxAttr(this.#vb));
  }

  /* ------------------------------------------------------------------------- FLIP */

  #playFlip(svg: SVGSVGElement, oldIdx: Map<FlipKey, Pos>, scene: Scene): void {
    const byKey = new Map<FlipKey, SVGElement>();
    svg.querySelectorAll<SVGElement>("[data-fnid]").forEach((el) => {
      const fnid = el.getAttribute("data-fnid");
      if (fnid !== null) byKey.set(flipKeyFor(el.tagName, fnid), el);
    });

    const play: SVGElement[] = [];
    // scale 1: a CSS transform on an element inside an <svg> resolves in the SVG's own user
    // coordinate system, so a CONTENT-space delta is already in the right units. See
    // `flipMoves`' doc — multiplying by the zoom here would over-shoot by the zoom factor.
    for (const mv of flipMoves(oldIdx, flipIndex(scene), 1)) {
      const el = byKey.get(mv.key);
      if (!el) continue;
      el.style.transition = "none";
      if (mv.kind === "move")
        el.style.transform = `translate(${mv.dx}px, ${mv.dy}px)`;
      else el.style.opacity = "0";
      play.push(el);
    }
    const wires = Array.from(svg.querySelectorAll<SVGElement>(".lad-wire"));
    wires.forEach((el) => {
      el.style.transition = "none";
      el.style.opacity = "0";
    });

    cancelAnimationFrame(this.#raf1);
    cancelAnimationFrame(this.#raf2);
    this.#raf1 = requestAnimationFrame(() => {
      this.#raf2 = requestAnimationFrame(() => {
        play.forEach((el) => {
          el.style.transition =
            "transform 300ms cubic-bezier(.2,.7,.2,1), opacity 300ms ease";
          el.style.transform = "";
          el.style.opacity = "";
        });
        wires.forEach((el) => {
          el.style.transition = "opacity 320ms ease";
          el.style.opacity = "";
        });
      });
    });
  }

  /* -------------------------------------------------------------- seam S6: viewport */

  fit(): void {
    if (!this.#panZoom) return;
    const vp = this.#viewport();
    if (vp.w <= 0 || vp.h <= 0) return;
    this.#vb = fitBox(this.#content, vp);
    this.#vpCache = vp;
    this.#applyViewBox();
  }

  /** `at` is in VIEWPORT px (origin = the SVG's top-left); default = the viewport centre. */
  zoom(factor: number, at?: Pt): void {
    if (!this.#panZoom || !this.#vb) return;
    const vp = this.#viewport();
    if (vp.w <= 0 || vp.h <= 0) return;
    const anchor = at ?? { x: vp.w / 2, y: vp.h / 2 };
    this.#vb = zoomAt(
      this.#vb,
      vp,
      factor,
      anchor,
      this.#content,
      this.#limits,
    );
    this.#applyViewBox();
  }

  /** Pointer-space px: positive `dx` drags the content to the right. */
  pan(dx: number, dy: number): void {
    if (!this.#panZoom || !this.#vb) return;
    const vp = this.#viewport();
    if (vp.w <= 0 || vp.h <= 0) return;
    this.#vb = panBy(this.#vb, vp, dx, dy, this.#content);
    this.#applyViewBox();
  }

  /** The SVG's rendered box. Measured on the `<svg>` and not the host, because the host may
   *  carry padding (both demos do) and the viewBox aspect must match what is actually
   *  painted or `preserveAspectRatio` letterboxes and every anchor drifts. */
  #viewport(): Size {
    const el = this.#svg ?? this.#host;
    return { w: el.clientWidth, h: el.clientHeight };
  }

  #rect(): { left: number; top: number } {
    const el = this.#svg ?? this.#host;
    const r = el.getBoundingClientRect();
    return { left: r.left, top: r.top };
  }

  /* ---------------------------------------------------------------------- listeners */

  #onClick = (e: MouseEvent) => {
    if (this.#dragged) {
      this.#dragged = false;
      return;
    }
    const target = e.target as Element | null;
    if (!target || typeof target.closest !== "function") return;
    // `closest` works on SVG elements, so a click landing on a <tspan> inside a
    // <text data-value> resolves to the text — which is precisely why delegation beats the
    // per-node listeners it replaces.
    const el = target.closest("[data-value],[data-fold]");
    if (!el || !this.#host.contains(el)) return;
    const act = actFromAttrs(
      el.getAttribute("data-value"),
      el.getAttribute("data-fold"),
    );
    // the controller REPORTS an act; it never interprets one. `playground.ts` branches on
    // its own hydration sets inside `onAct`, and that is the split EMBEDDABLE §3.2 draws.
    if (act) this.#onAct?.(act);
  };

  #onPointerDown = (e: PointerEvent) => {
    if (e.button !== 0) return;
    this.#dragging = true;
    this.#dragged = false;
    this.#dragTravel = 0;
    this.#lastPointer = { x: e.clientX, y: e.clientY };
    try {
      this.#host.setPointerCapture(e.pointerId);
    } catch {
      /* capture is an optimisation; the gesture still works without it */
    }
    this.#host.style.cursor = "grabbing";
  };

  #onPointerMove = (e: PointerEvent) => {
    if (!this.#dragging) return;
    const dx = e.clientX - this.#lastPointer.x;
    const dy = e.clientY - this.#lastPointer.y;
    this.#lastPointer = { x: e.clientX, y: e.clientY };
    this.#dragTravel += Math.abs(dx) + Math.abs(dy);
    if (this.#dragTravel > DRAG_SLOP) this.#dragged = true;
    this.pan(dx, dy);
  };

  #onPointerUp = (e: PointerEvent) => {
    if (!this.#dragging) return;
    this.#dragging = false;
    try {
      this.#host.releasePointerCapture(e.pointerId);
    } catch {
      /* not captured */
    }
    this.#host.style.cursor = "";
    // `#dragged` is deliberately LEFT SET here: a normal pointerup is followed by a `click`,
    // and that click is the one to suppress. `#onClick` clears the flag as it swallows it.
  };

  /** A cancelled gesture — touch scroll takeover, a system gesture, capture loss — is NOT
   *  followed by a `click`, so the suppression flag has no click to be spent on. Leaving it
   *  set would silently eat the user's next real click on a box or a caret. */
  #onPointerCancel = (e: PointerEvent) => {
    this.#onPointerUp(e);
    this.#dragged = false;
  };

  #onWheel = (e: WheelEvent) => {
    if (!this.#vb) return;
    // EMBEDDABLE §3.3's hard rule: "a wiki page that traps the scrollwheel is worse than one
    // with a wide picture." A trackpad pinch arrives as a wheel event with ctrlKey set.
    const focused = this.#hasFocus();
    if (!(e.ctrlKey || e.metaKey || focused)) return;
    e.preventDefault();
    const r = this.#rect();
    this.zoom(Math.exp(-e.deltaY * 0.0015), {
      x: e.clientX - r.left,
      y: e.clientY - r.top,
    });
  };

  #onDblClick = () => this.fit();

  #onKeyDown = (e: KeyboardEvent) => {
    const vp = this.#viewport();
    switch (e.key) {
      case "+":
      case "=":
        this.zoom(1.2);
        break;
      case "-":
      case "_":
        this.zoom(1 / 1.2);
        break;
      case "0":
      case "f":
        this.fit();
        break;
      // a pan of 10% of the viewport; note the sign — ArrowRight moves the WINDOW right,
      // which is the opposite of dragging the content right.
      case "ArrowLeft":
        this.pan(vp.w * 0.1, 0);
        break;
      case "ArrowRight":
        this.pan(-vp.w * 0.1, 0);
        break;
      case "ArrowUp":
        this.pan(0, vp.h * 0.1);
        break;
      case "ArrowDown":
        this.pan(0, -vp.h * 0.1);
        break;
      default:
        return;
    }
    e.preventDefault();
  };

  #hasFocus(): boolean {
    const active =
      typeof document !== "undefined" ? document.activeElement : null;
    return !!active && this.#host.contains(active);
  }

  #onResize(): void {
    if (!this.#panZoom || !this.#svg) return;
    const vp = this.#viewport();
    if (vp.w <= 0 || vp.h <= 0) return;
    const prev = this.#vpCache;
    // The user's zoom SURVIVES a resize — only a scene-shape change refits (see `#draw`).
    // A host that was 0×0 at mount has nothing to preserve, so it fits instead.
    this.#vb =
      !this.#vb || prev.w <= 0 || prev.h <= 0
        ? fitBox(this.#content, vp)
        : clampBox(refit(this.#vb, vp, prev), this.#content);
    this.#vpCache = vp;
    this.#applyViewBox();
  }

  /* ------------------------------------------------------------------------ teardown */

  destroy(): void {
    if (this.#destroyed) return;
    this.#destroyed = true;
    const host = this.#host;
    host.removeEventListener("click", this.#onClick);
    host.removeEventListener("pointerdown", this.#onPointerDown);
    host.removeEventListener("pointermove", this.#onPointerMove);
    host.removeEventListener("pointerup", this.#onPointerUp);
    host.removeEventListener("pointercancel", this.#onPointerCancel);
    host.removeEventListener("wheel", this.#onWheel);
    host.removeEventListener("dblclick", this.#onDblClick);
    host.removeEventListener("keydown", this.#onKeyDown);
    this.#ro?.disconnect();
    this.#ro = null;
    cancelAnimationFrame(this.#raf1);
    cancelAnimationFrame(this.#raf2);
    // Put the host back the way it was found. The constructor writes to the CALLER's element
    // (§ the `panZoom` block above), and a host outliving its controller — Track E swapping
    // renderers, or a second controller on the same node — would otherwise keep a stray tab
    // stop, a clipped box, and (if destroyed mid-drag) a stuck `cursor: grabbing`.
    host.style.overflow = this.#priorOverflow;
    host.style.position = this.#priorPosition;
    host.style.cursor = "";
    if (this.#addedTabindex) {
      host.removeAttribute("tabindex");
      this.#addedTabindex = false;
    }
    host.innerHTML = "";
    this.#svg = null;
    this.#lastScene = null;
  }
}

const relDiff = (a: number, b: number) =>
  Math.abs(a - b) / Math.max(Math.abs(a), Math.abs(b), 1);
