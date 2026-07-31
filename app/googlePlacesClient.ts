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
  includedRegionCodes?: string[];
  placeholder?: string;
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

function parseAddressComponent(components: GoogleAddressComponent[] | undefined, type: string) {
  const component = components?.find((item) => item.types.includes(type));
  return component?.long_name ?? component?.longText;
}

function coordinateValue(value: number | (() => number) | undefined) {
  return typeof value === "function" ? value() : value;
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
    lat: place.geometry?.location?.lat(),
    lng: place.geometry?.location?.lng(),
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
    await googleWindow.__pachangasPlacesPromise;
    await ensurePlacesAutocompleteAvailable();
    return;
  }

  googleWindow.__pachangasPlacesPromise = new Promise<void>((resolve, reject) => {
    const existingScript = document.querySelector<HTMLScriptElement>(googlePlacesScriptSelector);
    if (existingScript) {
      if (existingScript.dataset.pachangasGooglePlacesLoaded === "true" || googleWindow.google?.maps) {
        resolve();
        return;
      }

      const timeoutId = window.setTimeout(() => {
        reject(new Error("Google Places ha tardado demasiado en responder."));
      }, 10000);

      existingScript.addEventListener("load", () => {
        window.clearTimeout(timeoutId);
        existingScript.dataset.pachangasGooglePlacesLoaded = "true";
        resolve();
      }, { once: true });
      existingScript.addEventListener("error", () => {
        window.clearTimeout(timeoutId);
        reject(new Error("No se pudo cargar Google Places."));
      }, { once: true });
      return;
    }

    const script = document.createElement("script");
    const url = new URL("https://maps.googleapis.com/maps/api/js");
    const timeoutId = window.setTimeout(() => {
      reject(new Error("Google Places ha tardado demasiado en responder."));
    }, 10000);

    googleWindow.__pachangasGooglePlacesReady = () => {
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
    script.onerror = () => {
      window.clearTimeout(timeoutId);
      delete googleWindow.__pachangasGooglePlacesReady;
      reject(new Error("No se pudo cargar Google Places."));
    };
    document.head.appendChild(script);
  }).catch((error: unknown) => {
    delete googleWindow.__pachangasPlacesPromise;
    throw error;
  });

  await googleWindow.__pachangasPlacesPromise;
  await ensurePlacesAutocompleteAvailable();
  if (googleWindow.google?.maps?.places?.PlaceAutocompleteElement) {
    await waitForPlaceAutocompleteElement();
  }
}

function attachNewPlaceAutocomplete({
  input,
  onPlace,
}: {
  input: HTMLInputElement;
  onPlace: (place: VenuePlace) => void;
}) {
  const PlaceAutocompleteElement = googleMapsWindow().google?.maps?.places?.PlaceAutocompleteElement;
  if (!PlaceAutocompleteElement || typeof customElements === "undefined") return null;

  const autocompleteElement = new PlaceAutocompleteElement();
  autocompleteElement.classList.add("pachangas-place-autocomplete");
  autocompleteElement.includedRegionCodes = ["es"];
  autocompleteElement.placeholder = input.placeholder || "Busca con Google Places";
  input.style.display = "none";
  input.insertAdjacentElement("beforebegin", autocompleteElement);

  const handleSelect = async (event: Event) => {
    const selectEvent = event as GooglePlaceSelectEvent;
    const placePrediction = selectEvent.placePrediction ?? selectEvent.detail?.placePrediction;
    const place = placePrediction?.toPlace();
    if (!place) return;

    await place.fetchFields?.({
      fields: ["id", "displayName", "formattedAddress", "location", "addressComponents"],
    });

    const venuePlace = newPlaceResultToVenuePlace(place);
    if (!venuePlace) return;

    input.value = venuePlace.name;
    onPlace(venuePlace);
  };

  autocompleteElement.addEventListener("gmp-select", handleSelect);

  return () => {
    autocompleteElement.removeEventListener("gmp-select", handleSelect);
    autocompleteElement.remove();
    input.style.display = "";
  };
}

export async function attachVenueAutocomplete({
  apiKey,
  input,
  onPlace,
  types,
}: {
  apiKey: string;
  input: HTMLInputElement;
  onPlace: (place: VenuePlace) => void;
  types?: string[];
}) {
  await loadGooglePlaces(apiKey);

  const Autocomplete = googleMapsWindow().google?.maps?.places?.Autocomplete;
  if (!Autocomplete) {
    const newPlacesCleanup = attachNewPlaceAutocomplete({ input, onPlace });
    if (newPlacesCleanup) return newPlacesCleanup;
    throw new Error("Google Places no está disponible.");
  }

  const autocomplete = new Autocomplete(input, {
    componentRestrictions: { country: "es" },
    fields: ["address_components", "formatted_address", "geometry", "name", "place_id"],
    ...(types?.length ? { types } : {}),
  });

  const listener = autocomplete.addListener("place_changed", () => {
    const venuePlace = placeResultToVenuePlace(autocomplete.getPlace());
    if (venuePlace) onPlace(venuePlace);
  });

  return () => listener.remove();
}
