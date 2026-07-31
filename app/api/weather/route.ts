import { NextResponse } from "next/server";

type GoogleForecastHour = {
  cloudCover?: number;
  feelsLikeTemperature?: { degrees?: number };
  interval?: { startTime?: string };
  precipitation?: { probability?: { percent?: number } };
  relativeHumidity?: number;
  temperature?: { degrees?: number };
  weatherCondition?: {
    description?: { text?: string };
    type?: string;
  };
  wind?: {
    speed?: {
      unit?: string;
      value?: number;
    };
  };
};

type GoogleForecastResponse = {
  forecastHours?: GoogleForecastHour[];
  nextPageToken?: string;
};

const weatherHourMs = 60 * 60 * 1000;
const weatherDayMs = 24 * weatherHourMs;
const weatherForecastLimitHours = 7 * 24;
const weatherForecastLimitMs = weatherForecastLimitHours * weatherHourMs;
const weatherForecastPastToleranceMs = weatherHourMs;
const weatherForecastFreshWindowMs = weatherDayMs;
const weatherShortCacheSeconds = 2 * 60 * 60;
const weatherLongCacheSeconds = 24 * 60 * 60;
const weatherPageSize = 24;

function jsonResponse(body: unknown, status = 200, cache = "no-store") {
  return NextResponse.json(body, {
    status,
    headers: {
      "Cache-Control": cache,
    },
  });
}

function weatherCacheSeconds(targetMs: number, nowMs: number) {
  return targetMs - nowMs <= weatherForecastFreshWindowMs ? weatherShortCacheSeconds : weatherLongCacheSeconds;
}

function publicCache(seconds: number) {
  return `public, max-age=${seconds}, s-maxage=${seconds}`;
}

function numericParam(value: string | null) {
  if (!value) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function finiteNumber(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function windKmh(hour: GoogleForecastHour) {
  const value = finiteNumber(hour.wind?.speed?.value);
  if (value === null) return null;
  const unit = hour.wind?.speed?.unit;
  return unit === "METERS_PER_SECOND" ? value * 3.6 : value;
}

function forecastTime(hour: GoogleForecastHour) {
  return hour.interval?.startTime ?? "";
}

function closestForecast(hours: GoogleForecastHour[], targetMs: number) {
  return hours.reduce<GoogleForecastHour | null>((closest, hour) => {
    const time = Date.parse(forecastTime(hour));
    if (Number.isNaN(time)) return closest;
    if (!closest) return hour;
    const closestTime = Date.parse(forecastTime(closest));
    return Math.abs(time - targetMs) < Math.abs(closestTime - targetMs) ? hour : closest;
  }, null);
}

async function fetchForecastPage(apiKey: string, lat: number, lng: number, hours: number, revalidateSeconds: number, pageToken?: string) {
  const url = new URL("https://weather.googleapis.com/v1/forecast/hours:lookup");
  url.searchParams.set("key", apiKey);
  url.searchParams.set("location.latitude", String(lat));
  url.searchParams.set("location.longitude", String(lng));
  url.searchParams.set("hours", String(hours));
  url.searchParams.set("pageSize", String(weatherPageSize));
  url.searchParams.set("languageCode", "es");
  url.searchParams.set("unitsSystem", "METRIC");
  if (pageToken) url.searchParams.set("pageToken", pageToken);

  const response = await fetch(url, {
    headers: { Accept: "application/json" },
    next: { revalidate: revalidateSeconds },
  });

  if (!response.ok) {
    throw new Error(`Google Weather ${response.status}`);
  }

  return (await response.json()) as GoogleForecastResponse;
}

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const lat = numericParam(searchParams.get("lat"));
  const lng = numericParam(searchParams.get("lng"));
  const at = searchParams.get("at");

  if (lat === null || lng === null || !at) {
    return jsonResponse({ available: false, message: "Faltan coordenadas o fecha del partido." }, 400);
  }

  const targetMs = Date.parse(at);
  if (Number.isNaN(targetMs)) {
    return jsonResponse({ available: false, message: "Fecha del partido no válida." }, 400);
  }

  const now = Date.now();
  if (targetMs < now - weatherForecastPastToleranceMs) {
    return jsonResponse({ available: false, message: "La previsión solo está disponible para próximos partidos." });
  }

  const msUntilMatch = targetMs - now;
  if (msUntilMatch > weatherForecastLimitMs) {
    const msUntilAvailable = Math.max(0, msUntilMatch - weatherForecastLimitMs);
    const daysUntilAvailable = Math.max(1, Math.ceil(msUntilAvailable / weatherDayMs));
    return jsonResponse({
      available: false,
      message: `Previsión del tiempo disponible en ${daysUntilAvailable} ${daysUntilAvailable === 1 ? "día" : "días"}.`,
    }, 200, publicCache(weatherShortCacheSeconds));
  }

  const apiKey = process.env.GOOGLE_WEATHER_API_KEY ?? process.env.GOOGLE_MAPS_API_KEY ?? process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;
  if (!apiKey) {
    return jsonResponse({ available: false, message: "Falta configurar GOOGLE_WEATHER_API_KEY en el servidor." });
  }

  try {
    const cacheSeconds = weatherCacheSeconds(targetMs, now);
    const hoursUntilMatch = Math.ceil(msUntilMatch / weatherHourMs) + 2;
    const requestedHours = Math.max(1, Math.min(weatherForecastLimitHours, hoursUntilMatch));
    const forecastHours: GoogleForecastHour[] = [];
    let pageToken: string | undefined;

    for (let page = 0; page < 10; page += 1) {
      const payload = await fetchForecastPage(apiKey, lat, lng, requestedHours, cacheSeconds, pageToken);
      forecastHours.push(...(payload.forecastHours ?? []));
      pageToken = payload.nextPageToken;

      const latestTime = forecastHours.reduce((latest, hour) => {
        const time = Date.parse(forecastTime(hour));
        return Number.isNaN(time) ? latest : Math.max(latest, time);
      }, 0);

      if (!pageToken || latestTime >= targetMs) break;
    }

    const closest = closestForecast(forecastHours, targetMs);
    if (!closest) {
      return jsonResponse({ available: false, message: "Google Weather no devolvió previsión para este campo." });
    }

    return jsonResponse(
      {
        available: true,
        forecast: {
          cloudCover: finiteNumber(closest.cloudCover),
          condition: closest.weatherCondition?.description?.text ?? closest.weatherCondition?.type ?? "Previsión disponible",
          conditionType: closest.weatherCondition?.type ?? "",
          feelsLike: finiteNumber(closest.feelsLikeTemperature?.degrees),
          forecastTime: forecastTime(closest),
          humidity: finiteNumber(closest.relativeHumidity),
          precipitationProbability: finiteNumber(closest.precipitation?.probability?.percent),
          temperature: finiteNumber(closest.temperature?.degrees),
          windKmh: windKmh(closest),
        },
      },
      200,
      publicCache(cacheSeconds),
    );
  } catch {
    return jsonResponse({ available: false, message: "No se pudo consultar Google Weather ahora mismo." }, 502);
  }
}
