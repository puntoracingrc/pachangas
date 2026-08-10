import type { Territory } from "./types";

type CommunityDefinition = {
  code: string;
  name: string;
  provinces: Array<[string, string]>;
};

const communities: CommunityDefinition[] = [
  { code: "01", name: "Andalucía", provinces: [["04", "Almería"], ["11", "Cádiz"], ["14", "Córdoba"], ["18", "Granada"], ["21", "Huelva"], ["23", "Jaén"], ["29", "Málaga"], ["41", "Sevilla"]] },
  { code: "02", name: "Aragón", provinces: [["22", "Huesca"], ["44", "Teruel"], ["50", "Zaragoza"]] },
  { code: "03", name: "Principado de Asturias", provinces: [["33", "Asturias"]] },
  { code: "04", name: "Illes Balears", provinces: [["07", "Illes Balears"]] },
  { code: "05", name: "Canarias", provinces: [["35", "Las Palmas"], ["38", "Santa Cruz de Tenerife"]] },
  { code: "06", name: "Cantabria", provinces: [["39", "Cantabria"]] },
  { code: "07", name: "Castilla y León", provinces: [["05", "Ávila"], ["09", "Burgos"], ["24", "León"], ["34", "Palencia"], ["37", "Salamanca"], ["40", "Segovia"], ["42", "Soria"], ["47", "Valladolid"], ["49", "Zamora"]] },
  { code: "08", name: "Castilla-La Mancha", provinces: [["02", "Albacete"], ["13", "Ciudad Real"], ["16", "Cuenca"], ["19", "Guadalajara"], ["45", "Toledo"]] },
  { code: "09", name: "Cataluña", provinces: [["08", "Barcelona"], ["17", "Girona"], ["25", "Lleida"], ["43", "Tarragona"]] },
  { code: "10", name: "Comunitat Valenciana", provinces: [["03", "Alicante/Alacant"], ["12", "Castellón/Castelló"], ["46", "Valencia/València"]] },
  { code: "11", name: "Extremadura", provinces: [["06", "Badajoz"], ["10", "Cáceres"]] },
  { code: "12", name: "Galicia", provinces: [["15", "A Coruña"], ["27", "Lugo"], ["32", "Ourense"], ["36", "Pontevedra"]] },
  { code: "13", name: "Comunidad de Madrid", provinces: [["28", "Madrid"]] },
  { code: "14", name: "Región de Murcia", provinces: [["30", "Murcia"]] },
  { code: "15", name: "Comunidad Foral de Navarra", provinces: [["31", "Navarra"]] },
  { code: "16", name: "País Vasco", provinces: [["01", "Araba/Álava"], ["20", "Gipuzkoa"], ["48", "Bizkaia"]] },
  { code: "17", name: "La Rioja", provinces: [["26", "La Rioja"]] },
];

const denseProvinceCodes = new Set(["03", "08", "11", "28", "29", "30", "35", "41", "46", "48"]);
const smallProvinceCodes = new Set(["05", "09", "16", "19", "22", "34", "40", "42", "44", "49", "51", "52"]);

export const TERRITORIES: Territory[] = [
  ...communities.flatMap((community) => community.provinces.map(([provinceCode, provinceName]) => ({
    autonomousCommunityCode: community.code,
    autonomousCommunityName: community.name,
    density: denseProvinceCodes.has(provinceCode) ? "dense" as const
      : smallProvinceCodes.has(provinceCode) ? "small" as const : "medium" as const,
    provinceCode,
    provinceName,
    territorialDuplicate: community.provinces.length === 1,
    type: "province" as const,
  }))),
  {
    autonomousCommunityCode: null,
    autonomousCommunityName: null,
    density: "small",
    provinceCode: "51",
    provinceName: "Ceuta",
    territorialDuplicate: false,
    type: "autonomous_city",
  } as Territory,
  {
    autonomousCommunityCode: null,
    autonomousCommunityName: null,
    density: "small",
    provinceCode: "52",
    provinceName: "Melilla",
    territorialDuplicate: false,
    type: "autonomous_city",
  } as Territory,
].sort((left, right) => left.provinceCode.localeCompare(right.provinceCode));

export const TERRITORY_BY_PROVINCE = new Map(TERRITORIES.map((territory) => [territory.provinceCode, territory]));

export const AUTONOMOUS_COMMUNITIES = communities.map(({ code, name, provinces }) => ({
  code,
  name,
  provinceCodes: provinces.map(([provinceCode]) => provinceCode),
  territorialDuplicate: provinces.length === 1,
}));

export function assertCanonicalTerritories() {
  if (TERRITORIES.length !== 52) throw new Error(`Expected 52 base territories, received ${TERRITORIES.length}`);
  if (AUTONOMOUS_COMMUNITIES.length !== 17) throw new Error("Expected 17 autonomous communities");
  if (new Set(TERRITORIES.map(({ provinceCode }) => provinceCode)).size !== 52) {
    throw new Error("Province codes must be unique");
  }
}
