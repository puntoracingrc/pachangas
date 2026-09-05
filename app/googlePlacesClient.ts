"use client";

export type VenuePlace = {
  address: string;
  city?: string;
  country?: string;
  lat?: number;
  lng?: number;
  name: string;
  placeId: string;
  province?: string;
};

type GoogleMapsListener = {
  remove: () => void;
};

type GoogleAddressComponent = {
  long_name?: string;
  longText?: string;
  short_name?: string;
  shortText?: string;
  types: string[];
};

type GooglePlaceResult = {
  address_components?: GoogleAddressComponent[];
  formatted_address?: string;
  geometry?: {
    location?: {
      lat: () => number;
      lng: () => number;
    };
  };
  name?: string;
  place_id?: string;
};

type GoogleAutocomplete = {
  addListener: (eventName: "place_changed", callback: () => void) => GoogleMapsListener;
  getPlace: () => GooglePlaceResult;
};

type GoogleAutocompleteConstructor = new (
  input: HTMLInputElement,
  options: {
    componentRestrictions?: { country: string | string[] };
    fields: string[];
    types?: string[];
  },
) => GoogleAutocomplete;

type GooglePlace = {
  addressComponents?: GoogleAddressComponent[];
  displayName?: string | { text?: string };
  formattedAddress?: string;
  id?: string;
  location?: {
    lat?: number | (() => number);
    lng?: number | (() => number);
  };
  fetchFields?: (options: { fields: string[] }) => Promise<void>;
};

type GooglePlaceAutocompleteElement = HTMLElement & {
  includedPrimaryTypes?: string[];
  includedRegionCodes?: string[];
  placeholder?: string;
  value?: string;
};

type GooglePlaceAutocompleteElementConstructor = new () => GooglePlaceAutocompleteElement;

type GooglePlacePrediction = {
  toPlace: () => GooglePlace;
};

type GooglePlaceSelectEvent = Event & {
  detail?: {
    placePrediction?: GooglePlacePrediction;
  };
  placePrediction?: GooglePlacePrediction;
};

type GoogleMapsWindow = Window & {
  __pachangasPlacesPromise?: Promise<void>;
  __pachangasGooglePlacesReady?: () => void;
  google?: {
    maps?: {
      importLibrary?: (libraryName: "places") => Promise<{
        Autocomplete?: GoogleAutocompleteConstructor;
        PlaceAutocompleteElement?: GooglePlaceAutocompleteElementConstructor;
      }>;
      places?: {
        Autocomplete?: GoogleAutocompleteConstructor;
        PlaceAutocompleteElement?: GooglePlaceAutocompleteElementConstructor;
      };
    };
  };
};

const googlePlacesScriptSelector = 'script[data-pachangas-google-places="true"]';
const googlePlacesSearchError = "No podemos buscar ubicaciones ahora mismo. Revisa la conexión e inténtalo de nuevo.";
const googlePlacesSelectionError = "No pudimos verificar esta ubicación. Elige otra sugerencia.";

function parseAddressComponent(components: GoogleAddressComponent[] | undefined, type: string) {
  const component = components?.find((item) => item.types.includes(type));
  return component?.long_name ?? component?.longText;
}

function coordinateValue(value: number | (() => number) | undefined) {
  const coordinate = typeof value === "function" ? value() : value;
  return Number.isFinite(coordinate) ? coordinate : undefined;
}

function placeDisplayName(place: GooglePlace) {
  return typeof place.displayName === "string" ? place.displayName : place.displayName?.text;
}

function placeResultToVenuePlace(place: GooglePlaceResult): VenuePlace | null {
  if (!place.place_id || !place.name || !place.formatted_address) return null;

  return {
    address: place.formatted_address,
    city:
      parseAddressComponent(place.address_components, "locality") ??
      parseAddressComponent(place.address_components, "postal_town") ??
      parseAddressComponent(place.address_components, "administrative_area_level_3"),
    country: parseAddressComponent(place.address_components, "country"),
    lat: coordinateValue(place.geometry?.location?.lat),
    lng: coordinateValue(place.geometry?.location?.lng),
    name: place.name,
    placeId: place.place_id,
    province: parseAddressComponent(place.address_components, "administrative_area_level_2"),
  };
}

function newPlaceResultToVenuePlace(place: GooglePlace): VenuePlace | null {
  const name = placeDisplayName(place);
  if (!place.id || !name || !place.formattedAddress) return null;

  return {
    address: place.formattedAddress,
    city:
      parseAddressComponent(place.addressComponents, "locality") ??
      parseAddressComponent(place.addressComponents, "postal_town") ??
      parseAddressComponent(place.addressComponents, "administrative_area_level_3"),
    country: parseAddressComponent(place.addressComponents, "country"),
    lat: coordinateValue(place.location?.lat),
    lng: coordinateValue(place.location?.lng),
    name,
    placeId: place.id,
    province: parseAddressComponent(place.addressComponents, "administrative_area_level_2"),
  };
}

function googleMapsWindow() {
  return window as GoogleMapsWindow;
}

async function waitForPlaceAutocompleteElement() {
  if (typeof customElements === "undefined") return;
  await Promise.race([
    customElements.whenDefined("gmp-place-autocomplete"),
    new Promise((_, reject) => {
      window.setTimeout(() => reject(new Error("Google Places ha tardado demasiado en inicializar el selector.")), 5000);
    }),
  ]);
}

async function ensurePlacesAutocompleteAvailable() {
  const maps = googleMapsWindow().google?.maps;
  if (maps?.places?.Autocomplete || maps?.places?.PlaceAutocompleteElement) return;

  const placesLibrary = await maps?.importLibrary?.("places");
  if (placesLibrary && maps) {
    maps.places = { ...(maps.places ?? {}), ...placesLibrary };
  }

  if (maps?.places?.Autocomplete || maps?.places?.PlaceAutocompleteElement) {
    return;
  }

  throw new Error("Google Places no está disponible. Revisa que Maps JavaScript API y Places API estén activadas para esta clave.");
}

export async function loadGooglePlaces(apiKey: string) {
  const googleWindow = googleMapsWindow();
  if (googleWindow.google?.maps?.places?.Autocomplete || googleWindow.google?.maps?.places?.PlaceAutocompleteElement) return;
  if (googleWindow.__pachangasPlacesPromise) {
    try {
      await googleWindow.__pachangasPlacesPromise;
      await ensurePlacesAutocompleteAvailable();
    } catch (error) {
      delete googleWindow.__pachangasPlacesPromise;
      throw error;
    }
    return;
  }

  googleWindow.__pachangasPlacesPromise = new Promise<void>((resolve, reject) => {
    const existingScript = document.querySelector<HTMLScriptElement>(googlePlacesScriptSelector);
    if (existingScript) {
      if (existingScript.dataset.pachangasGooglePlacesLoaded === "true" || googleWindow.google?.maps) {
        resolve();
        return;
      }

      let settled = false;
      const fail = (message: string) => {
        if (settled) return;
        settled = true;
        window.clearTimeout(timeoutId);
        existingScript.remove();
        reject(new Error(message));
      };
      const timeoutId = window.setTimeout(() => fail("Google Places ha tardado demasiado en responder."), 10000);

      existingScript.addEventListener("load", () => {
        if (settled) return;
        settled = true;
        window.clearTimeout(timeoutId);
        existingScript.dataset.pachangasGooglePlacesLoaded = "true";
        resolve();
      }, { once: true });
      existingScript.addEventListener("error", () => fail("No se pudo cargar Google Places."), { once: true });
      return;
    }

    const script = document.createElement("script");
    const url = new URL("https://maps.googleapis.com/maps/api/js");
    let settled = false;
    const fail = (message: string) => {
      if (settled) return;
      settled = true;
      window.clearTimeout(timeoutId);
      script.remove();
      delete googleWindow.__pachangasGooglePlacesReady;
      reject(new Error(message));
    };
    const timeoutId = window.setTimeout(() => fail("Google Places ha tardado demasiado en responder."), 10000);

    googleWindow.__pachangasGooglePlacesReady = () => {
      if (settled) return;
      settled = true;
      window.clearTimeout(timeoutId);
      script.dataset.pachangasGooglePlacesLoaded = "true";
      resolve();
      delete googleWindow.__pachangasGooglePlacesReady;
    };

    url.searchParams.set("key", apiKey);
    url.searchParams.set("libraries", "places");
    url.searchParams.set("loading", "async");
    url.searchParams.set("v", "weekly");
    url.searchParams.set("callback", "__pachangasGooglePlacesReady");

    script.async = true;
    script.dataset.pachangasGooglePlaces = "true";
    script.src = url.toString();
    script.onload = () => {
      script.dataset.pachangasGooglePlacesLoaded = "true";
    };
    script.onerror = () => fail("No se pudo cargar Google Places.");
    document.head.appendChild(script);
  }).catch((error: unknown) => {
    delete googleWindow.__pachangasPlacesPromise;
    throw error;
  });

  try {
    await googleWindow.__pachangasPlacesPromise;
    await ensurePlacesAutocompleteAvailable();
    if (googleWindow.google?.maps?.places?.PlaceAutocompleteElement) {
      await waitForPlaceAutocompleteElement();
    }
  } catch (error) {
    delete googleWindow.__pachangasPlacesPromise;
    throw error;
  }
}

function attachNewPlaceAutocomplete({
  input,
  onError,
  onPlace,
  onSelectionInvalidated,
  types,
}: {
  input: HTMLInputElement;
  onError?: (message: string) => void;
  onPlace: (place: VenuePlace) => void;
  onSelectionInvalidated?: () => void;
  types?: string[];
}) {
  const PlaceAutocompleteElement = googleMapsWindow().google?.maps?.places?.PlaceAutocompleteElement;
  if (!PlaceAutocompleteElement || typeof customElements === "undefined") return null;

  const autocompleteElement = new PlaceAutocompleteElement();
  autocompleteElement.classList.add("pachangas-place-autocomplete");
  if (types?.length) autocompleteElement.includedPrimaryTypes = types;
  autocompleteElement.includedRegionCodes = ["es"];
  autocompleteElement.placeholder = input.placeholder || "Busca con Google Places";
  autocompleteElement.value = input.value;
  input.style.display = "none";
  input.insertAdjacentElement("beforebegin", autocompleteElement);

  let active = true;
  let selectionRevision = 0;
  let deliveredPlaceId: string | null = null;

  const invalidateSelection = () => {
    selectionRevision += 1;
    deliveredPlaceId = null;
    onSelectionInvalidated?.();
  };

  const reportError = (message: string) => {
    invalidateSelection();
    onError?.(message);
  };

  const handleInput = () => {
    if (active) invalidateSelection();
  };

  const handleError = () => {
    if (active) reportError(googlePlacesSearchError);
  };

  const handleSelect = async (event: Event) => {
    if (!active) return;
    const requestRevision = ++selectionRevision;
    const selectEvent = event as GooglePlaceSelectEvent;
    const placePrediction = selectEvent.placePrediction ?? selectEvent.detail?.placePrediction;
    const place = placePrediction?.toPlace();
    if (!place) {
      reportError(googlePlacesSelectionError);
      return;
    }

    try {
      await place.fetchFields?.({
        fields: ["id", "displayName", "formattedAddress", "location", "addressComponents"],
      });
    } catch {
      if (active && requestRevision === selectionRevision) reportError(googlePlacesSearchError);
      return;
    }

    if (!active || requestRevision !== selectionRevision) return;

    const venuePlace = newPlaceResultToVenuePlace(place);
    if (!venuePlace) {
      reportError(googlePlacesSelectionError);
      return;
    }
    if (deliveredPlaceId === venuePlace.placeId) return;

    deliveredPlaceId = venuePlace.placeId;
    input.value = venuePlace.name;
    onPlace(venuePlace);
  };

  autocompleteElement.addEventListener("input", handleInput);
  autocompleteElement.addEventListener("gmp-error", handleError);
  autocompleteElement.addEventListener("gmp-select", handleSelect);

  return () => {
    active = false;
    selectionRevision += 1;
    autocompleteElement.removeEventListener("input", handleInput);
    autocompleteElement.removeEventListener("gmp-error", handleError);
    autocompleteElement.removeEventListener("gmp-select", handleSelect);
    autocompleteElement.remove();
    input.style.display = "";
  };
}

export async function attachVenueAutocomplete({
  apiKey,
  input,
  onError,
  onPlace,
  onSelectionInvalidated,
  types,
}: {
  apiKey: string;
  input: HTMLInputElement;
  onError?: (message: string) => void;
  onPlace: (place: VenuePlace) => void;
  onSelectionInvalidated?: () => void;
  types?: string[];
}) {
  await loadGooglePlaces(apiKey);

  const newPlacesCleanup = attachNewPlaceAutocomplete({ input, onError, onPlace, onSelectionInvalidated, types });
  if (newPlacesCleanup) return newPlacesCleanup;

  const Autocomplete = googleMapsWindow().google?.maps?.places?.Autocomplete;
  if (!Autocomplete) {
    throw new Error("Google Places no está disponible.");
  }

  const autocomplete = new Autocomplete(input, {
    componentRestrictions: { country: "es" },
    fields: ["address_components", "formatted_address", "geometry", "name", "place_id"],
    ...(types?.length ? { types } : {}),
  });

  const handleInput = () => onSelectionInvalidated?.();
  input.addEventListener("input", handleInput);

  const listener = autocomplete.addListener("place_changed", () => {
    const venuePlace = placeResultToVenuePlace(autocomplete.getPlace());
    if (venuePlace) {
      onPlace(venuePlace);
      return;
    }
    onSelectionInvalidated?.();
    onError?.(googlePlacesSelectionError);
  });

  return () => {
    input.removeEventListener("input", handleInput);
    listener.remove();
  };
}
