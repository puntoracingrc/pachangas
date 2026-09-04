import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test, { afterEach } from "node:test";
import { attachVenueAutocomplete, loadGooglePlaces, type VenuePlace } from "../app/googlePlacesClient";

const originalGlobals = new Map<string, PropertyDescriptor | undefined>();

function setGlobal(name: string, value: unknown) {
  if (!originalGlobals.has(name)) originalGlobals.set(name, Object.getOwnPropertyDescriptor(globalThis, name));
  Object.defineProperty(globalThis, name, { configurable: true, value, writable: true });
}

afterEach(() => {
  for (const [name, descriptor] of originalGlobals) {
    if (descriptor) Object.defineProperty(globalThis, name, descriptor);
    else delete (globalThis as Record<string, unknown>)[name];
  }
  originalGlobals.clear();
});

class FakeElement extends EventTarget {
  async = false;
  classNames = new Set<string>();
  classList = { add: (name: string) => this.classNames.add(name) };
  dataset: Record<string, string> = {};
  insertedElement: FakeElement | null = null;
  onerror: (() => void) | null = null;
  onload: (() => void) | null = null;
  onRemove?: () => void;
  placeholder = "";
  removed = false;
  src = "";
  style: Record<string, string> = {};
  value = "";

  insertAdjacentElement(_position: string, element: Element) {
    this.insertedElement = element as unknown as FakeElement;
    return element;
  }

  remove() {
    this.removed = true;
    this.onRemove?.();
  }
}

function installWidgetEnvironment({
  legacy,
  newWidget,
}: {
  legacy?: new (input: HTMLInputElement, options: Record<string, unknown>) => unknown;
  newWidget?: new () => HTMLElement;
}) {
  const fakeWindow = {
    clearTimeout,
    google: {
      maps: {
        places: {
          ...(legacy ? { Autocomplete: legacy } : {}),
          ...(newWidget ? { PlaceAutocompleteElement: newWidget } : {}),
        },
      },
    },
    setTimeout,
  };
  setGlobal("window", fakeWindow);
  setGlobal("customElements", { whenDefined: async () => undefined });
  return fakeWindow;
}

function installScriptEnvironment() {
  const scripts: FakeElement[] = [];
  let nextTimer = 1;
  const timers = new Map<number, () => void>();
  const fakeWindow: Record<string, unknown> = {
    clearTimeout: (id: number) => timers.delete(id),
    setTimeout: (callback: () => void) => {
      const id = nextTimer++;
      timers.set(id, callback);
      return id;
    },
  };
  const document = {
    createElement: (tagName: string) => {
      assert.equal(tagName, "script");
      const script = new FakeElement();
      script.onRemove = () => {
        const index = scripts.indexOf(script);
        if (index >= 0) scripts.splice(index, 1);
      };
      return script;
    },
    head: {
      appendChild: (script: FakeElement) => {
        scripts.push(script);
        return script;
      },
    },
    querySelector: () => scripts[0] ?? null,
  };
  setGlobal("window", fakeWindow);
  setGlobal("document", document);
  setGlobal("customElements", { whenDefined: async () => undefined });
  return { fakeWindow, scripts, timers };
}

const flush = () => new Promise<void>((resolve) => setImmediate(resolve));

test("Google Places loads one shared script with the current widget contract", async () => {
  const { fakeWindow, scripts } = installScriptEnvironment();
  const first = loadGooglePlaces("test-api-key");
  const second = loadGooglePlaces("test-api-key");

  assert.equal(scripts.length, 1);
  const url = new URL(scripts[0].src);
  assert.equal(url.origin, "https://maps.googleapis.com");
  assert.equal(url.searchParams.get("libraries"), "places");
  assert.equal(url.searchParams.get("loading"), "async");
  assert.equal(url.searchParams.get("v"), "weekly");

  fakeWindow.google = { maps: { places: { Autocomplete: class {} } } };
  (fakeWindow.__pachangasGooglePlacesReady as () => void)();
  await Promise.all([first, second]);
  await loadGooglePlaces("test-api-key");
  assert.equal(scripts.length, 1);
});

test("script errors and timeouts clear failed state so a later retry can succeed", async () => {
  const { fakeWindow, scripts, timers } = installScriptEnvironment();

  const scriptFailure = loadGooglePlaces("test-api-key");
  scripts[0].onerror?.();
  await assert.rejects(scriptFailure, /No se pudo cargar Google Places/);
  assert.equal(scripts.length, 0);
  assert.equal(fakeWindow.__pachangasPlacesPromise, undefined);

  const timeoutFailure = loadGooglePlaces("test-api-key");
  assert.equal(scripts.length, 1);
  [...timers.values()][0]();
  await assert.rejects(timeoutFailure, /tardado demasiado/);
  assert.equal(scripts.length, 0);
  assert.equal(fakeWindow.__pachangasPlacesPromise, undefined);

  const retry = loadGooglePlaces("test-api-key");
  fakeWindow.google = { maps: { places: { Autocomplete: class {} } } };
  (fakeWindow.__pachangasGooglePlacesReady as () => void)();
  await retry;
  assert.equal(scripts.length, 1);
});

test("the new widget selects canonical details, invalidates edits and surfaces gmp-error", async () => {
  class PlaceAutocompleteElement extends FakeElement {
    includedPrimaryTypes?: string[];
    includedRegionCodes?: string[];
  }
  installWidgetEnvironment({ newWidget: PlaceAutocompleteElement as unknown as new () => HTMLElement });

  const input = new FakeElement();
  input.placeholder = "Crear campo: nombre";
  const places: VenuePlace[] = [];
  const errors: string[] = [];
  let invalidations = 0;
  let fetchedFields: string[] = [];
  const cleanup = await attachVenueAutocomplete({
    apiKey: "test-api-key",
    input: input as unknown as HTMLInputElement,
    onError: (message) => errors.push(message),
    onPlace: (place) => places.push(place),
    onSelectionInvalidated: () => invalidations += 1,
    types: ["sports_complex"],
  });

  assert.ok(input.insertedElement);
  const activeWidget = input.insertedElement as PlaceAutocompleteElement;
  assert.deepEqual(activeWidget.includedRegionCodes, ["es"]);
  assert.deepEqual(activeWidget.includedPrimaryTypes, ["sports_complex"]);
  assert.equal(activeWidget.placeholder, input.placeholder);
  assert.equal(input.style.display, "none");
  assert.equal(input.insertedElement, activeWidget);

  activeWidget.dispatchEvent(new Event("input"));
  assert.equal(invalidations, 1);

  const place = {
    addressComponents: [
      { longText: "Barcelona", types: ["locality"] },
      { longText: "España", types: ["country"] },
    ],
    displayName: "Recinto deportivo",
    fetchFields: async ({ fields }: { fields: string[] }) => {
      fetchedFields = fields;
    },
    formattedAddress: "Dirección verificada",
    id: "provider-place-id",
    location: { lat: () => 41.0, lng: () => 2.0 },
  };
  const select = Object.assign(new Event("gmp-select"), {
    placePrediction: { toPlace: () => place },
  });
  activeWidget.dispatchEvent(select);
  await flush();

  assert.deepEqual(fetchedFields, ["id", "displayName", "formattedAddress", "location", "addressComponents"]);
  assert.deepEqual(places, [{
    address: "Dirección verificada",
    city: "Barcelona",
    country: "España",
    lat: 41,
    lng: 2,
    name: "Recinto deportivo",
    placeId: "provider-place-id",
    province: undefined,
  }]);
  assert.equal(input.value, "Recinto deportivo");

  activeWidget.dispatchEvent(select);
  await flush();
  assert.equal(places.length, 1, "a duplicate provider event must not deliver the same selection twice");

  activeWidget.dispatchEvent(new Event("gmp-error"));
  assert.equal(invalidations, 2);
  assert.match(errors[0], /No podemos buscar ubicaciones/);
  assert.doesNotMatch(errors[0], /test-api-key|provider-place-id/);

  cleanup();
  assert.equal(input.style.display, "");
  assert.equal(activeWidget.removed, true);
  activeWidget.dispatchEvent(select);
  await flush();
  assert.equal(places.length, 1, "events after cleanup must be ignored");
});

test("rapid selections, failed details and incomplete places never deliver stale state", async () => {
  class PlaceAutocompleteElement extends FakeElement {}
  installWidgetEnvironment({ newWidget: PlaceAutocompleteElement as unknown as new () => HTMLElement });

  const input = new FakeElement();
  const places: VenuePlace[] = [];
  const errors: string[] = [];
  let resolveFirst = () => undefined;
  const firstFields = new Promise<void>((resolve) => {
    resolveFirst = resolve;
  });
  await attachVenueAutocomplete({
    apiKey: "test-api-key",
    input: input as unknown as HTMLInputElement,
    onError: (message) => errors.push(message),
    onPlace: (place) => places.push(place),
  });

  assert.ok(input.insertedElement);
  const activeWidget = input.insertedElement;
  const makeEvent = (place: Record<string, unknown>) => Object.assign(new Event("gmp-select"), {
    placePrediction: { toPlace: () => place },
  });
  activeWidget.dispatchEvent(makeEvent({
    displayName: "Primero",
    fetchFields: () => firstFields,
    formattedAddress: "Dirección 1",
    id: "first",
  }));
  activeWidget.dispatchEvent(makeEvent({
    displayName: "Segundo",
    fetchFields: async () => undefined,
    formattedAddress: "Dirección 2",
    id: "second",
    location: { lat: Number.NaN, lng: Number.POSITIVE_INFINITY },
  }));
  await flush();
  resolveFirst();
  await flush();

  assert.equal(places.length, 1);
  assert.equal(places[0].placeId, "second");
  assert.equal(places[0].lat, undefined);
  assert.equal(places[0].lng, undefined);

  activeWidget.dispatchEvent(makeEvent({
    fetchFields: async () => {
      throw new Error("raw provider error with test-api-key");
    },
  }));
  await flush();
  assert.match(errors.at(-1) ?? "", /No podemos buscar ubicaciones/);
  assert.doesNotMatch(errors.at(-1) ?? "", /raw provider|test-api-key/);

  activeWidget.dispatchEvent(makeEvent({
    displayName: "Sin dirección",
    fetchFields: async () => undefined,
    id: "incomplete",
  }));
  await flush();
  assert.match(errors.at(-1) ?? "", /No pudimos verificar/);
  assert.equal(places.length, 1);
});

test("legacy autocomplete remains the fallback with Spain restriction and cleanup", async () => {
  let callback = () => undefined;
  let options: Record<string, unknown> = {};
  let removed = false;
  let result: Record<string, unknown> = {
    address_components: [{ long_name: "España", types: ["country"] }],
    formatted_address: "Dirección verificada",
    geometry: { location: { lat: () => 41, lng: () => 2 } },
    name: "Campo legacy",
    place_id: "legacy-place-id",
  };
  class Autocomplete {
    constructor(_input: HTMLInputElement, nextOptions: Record<string, unknown>) {
      options = nextOptions;
    }
    addListener(_name: string, nextCallback: () => void) {
      callback = nextCallback;
      return { remove: () => { removed = true; } };
    }
    getPlace() {
      return result;
    }
  }
  installWidgetEnvironment({ legacy: Autocomplete as unknown as new (input: HTMLInputElement, options: Record<string, unknown>) => unknown });

  const input = new FakeElement();
  const places: VenuePlace[] = [];
  const errors: string[] = [];
  let invalidations = 0;
  const cleanup = await attachVenueAutocomplete({
    apiKey: "test-api-key",
    input: input as unknown as HTMLInputElement,
    onError: (message) => errors.push(message),
    onPlace: (place) => places.push(place),
    onSelectionInvalidated: () => invalidations += 1,
  });

  assert.deepEqual(options.componentRestrictions, { country: "es" });
  input.dispatchEvent(new Event("input"));
  assert.equal(invalidations, 1);
  callback();
  assert.equal(places[0].placeId, "legacy-place-id");

  result = { name: "Texto incompleto" };
  callback();
  assert.equal(places.length, 1);
  assert.equal(invalidations, 2);
  assert.match(errors[0], /No pudimos verificar/);

  cleanup();
  assert.equal(removed, true);
});

test("the official field form stays fail-closed and persists through server authority", async () => {
  const [page, helper, previewRunner, serviceWorker, manifest] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/googlePlacesClient.ts", import.meta.url), "utf8"),
    readFile(new URL("./google-places-preview-selection-e2e.mjs", import.meta.url), "utf8"),
    readFile(new URL("../app/service-worker-source.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/manifest.ts", import.meta.url), "utf8"),
  ]);
  const addVenue = page.slice(page.indexOf("function addVenue"), page.indexOf("function venueUsage"));

  assert.match(page, /onError: \(message\) => \{[\s\S]*setVenuePlaceStatus\("error"\)/);
  assert.match(page, /onSelectionInvalidated: \(\) => \{[\s\S]*setSelectedVenuePlace\(null\)/);
  assert.match(page, /<button type="submit" disabled=\{!selectedVenuePlace\}>Guardar campo<\/button>/);
  assert.match(page, /<strong>Dirección verificada<\/strong>/);
  assert.match(page, /save_pachanga_payload_authoritative_v2/);
  assert.match(page, /operation_id: id\(\)/);
  assert.match(page, /expected_revision: remotePayloadRevisionRef\.current/);
  assert.doesNotMatch(addVenue, /\.from\(|\.insert\(|\.update\(/);
  assert.match(addVenue, /placeId: selectedVenuePlace\.placeId/);
  assert.match(addVenue, /lat: selectedVenuePlace\.lat/);
  assert.match(addVenue, /lng: selectedVenuePlace\.lng/);
  assert.match(helper, /addEventListener\("gmp-error"/);
  assert.match(helper, /placePrediction\?\.toPlace\(\)/);
  assert.match(helper, /await place\.fetchFields/);
  assert.match(previewRunner, /\^Invalid InterceptionId\\\.\?\$/);
  assert.match(previewRunner, /onUnexpectedProtocolError\(error\)/);
  assert.match(previewRunner, /runtimeFailures\.push\(sanitizeDiagnostic/);
  assert.doesNotMatch(serviceWorker, /Google Places|maps\.googleapis\.com/);
  assert.doesNotMatch(manifest, /Google Places|maps\.googleapis\.com/);
});
