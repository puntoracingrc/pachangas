import assert from "node:assert/strict";
import test from "node:test";
import { readFile } from "node:fs/promises";
import { buildTeamRanking, rankingSeason, teamRankingSeasons } from "../app/equipo/team-ranking-model";

const players = [{ id: "alberto", name: "Alberto", rating: 3.8, position: "Delantero / punta" }, { id: "jordi", name: "Jordi", rating: 5 }, { id: "reserve", name: "Reserva", rating: 6 }];
const match = { date: "2026-09-10", scoreA: 2, scoreB: 1, targetPlayers: 2, teamA: ["alberto"], teamB: ["jordi"], players: [{playerId:"alberto",status:"voy"},{playerId:"jordi",status:"voy"},{playerId:"reserve",status:"voy"}], scorers:[{playerId:"alberto",goals:2},{playerId:"jordi",goals:1}] };

test("team standings count only completed games in the selected season and exclude reserves from appearances", () => {
 const payload={players,matches:[match,{...match,date:"2025-10-10"},{...match,scoreA:undefined,scoreB:undefined}]};
 const rows=buildTeamRanking(payload,"2026-2027","goles");
 assert.deepEqual(rows.map(({name,goals,appearances,wins})=>({name,goals,appearances,wins})),[{name:"Alberto",goals:2,appearances:1,wins:1},{name:"Jordi",goals:1,appearances:1,wins:0},{name:"Reserva",goals:0,appearances:0,wins:0}]);
 assert.equal(buildTeamRanking(payload,"2026-2027","media")[0].name,"Reserva");
 assert.equal(rows[0].media,38);
 assert.equal(rows[0].position,"DEL");
});
test("season boundary is September and tied games award no wins",()=>{
 assert.equal(rankingSeason("2026-08-31T12:00:00"),"2025-2026");
 assert.equal(rankingSeason("2026-09-01T12:00:00"),"2026-2027");
 assert.deepEqual(teamRankingSeasons({matches:[match]},new Date("2026-09-06")),["2026-2027"]);
 assert.equal(buildTeamRanking({players,matches:[{...match,scoreA:1}]},"2026-2027","ganados").reduce((sum,row)=>sum+row.wins,0),0);
});
test("cards retain bounded peer ratings and keep goalkeeper evaluations separate",()=>{
 const facets={ritmo:10,tiro:10,pase:10,regate:10,defensa:10,fisico:10};
 const result=buildTeamRanking({players:[{id:"keeper",name:"Portero",goalkeeperOnly:true,rating:5,ratingVotes:[{ratingRole:"field",facets},{ratingRole:"goalkeeper",facets,matchCount:1}]}]},"2026-2027","media");
 assert.equal(result[0].media,60);
 assert.equal(result[0].facets[0].label,"SAL");
 assert.deepEqual(buildTeamRanking({players:[],matches:[match]},"2026-2027","media"),[]);
});
test("group ranking has one product home and cannot embed the provincial/global ranking",async()=>{
 const source=async(path:string)=>readFile(new URL(`../${path}`,import.meta.url),"utf8");
 const [home,team,ranking]=await Promise.all([source("app/page.tsx"),source("app/equipo/social-team-client.tsx"),source("app/equipo/team-ranking.tsx")]);
 assert.doesNotMatch(home,/id="ranking"|renderRankingMiniCard/);
 assert.doesNotMatch(team,/ProvincialRankingProduct|from "..\/ranking\//);
 assert.match(team,/surface === "home" \? <TeamRanking/);
 assert.doesNotMatch(team,/homePane|>Portada<|<TeamHome/);
 assert.match(ranking,/\.eq\("id", groupId\)/);
 assert.match(home,/rankingPlayer/);
});
