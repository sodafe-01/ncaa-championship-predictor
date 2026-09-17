// 5-minute executive briefing: 6 core slides + Q&A appendix.
// Usage (from deck/): node build-5min.js  ->  NCAA_Briefing_5min.pptx
//
// Fill DATA from the sim_/eval_/m_ tables, set final: true, and rebuild.
// While final is false, data-driven slides carry an "ILLUSTRATIVE" badge.
const path = require('path');
const pptxgen = require('pptxgenjs');
const React = require('react');
const ReactDOMServer = require('react-dom/server');
const sharp = require('sharp');
const fa = require('react-icons/fa6');

// Values from da-hackathon-2026.texas_longhorns, pulled 2026-09-16, re-verified after the 2026-09-17 mart rebuild:
//   pick/contenders  mart_title_odds     scenario = 'proj_2018', ORDER BY odds_rank, p_champion
//   backtest         mart_backtest       is_chosen_model AND is_core_season (logistic_reg; AVG over 3 seasons)
//   drivers          m_explain_topk      proj_2018, explain_level = 'team_profile', the pick's team_id
//   champions        mart_title_odds     is_actual_champion, strength_rank (pre-tournament adjusted-margin rank)
//   agentH2H         p_matchup           proj_2018 (rating_only), asked through agent texas-longhorns-front-office-analyst 2026-09-17
//   league           mart_conference_season (season = 2017), mart_league_season (avg_tempo, avg_three_point_rate, ncaa_upset_rate)
//   quality          README_COMPLETED.md: dbt test run 2026-09-16; m_next_season held-out check 2016-17 -> 2017-18
const DATA = {
  final: true,
  pick: { team: 'Villanova', pct: 38.6, seed: 'Projected #1 seed, East', margin: 32.8, bandLow: 24.5, bandHigh: 41.2 },
  contenders: [['Villanova', 38.6], ['Duke', 14.5], ['Michigan State', 8.9], ['Virginia', 7.4], ['Kentucky', 4.3]],
  // average log loss over the 2015-2017 tournaments (67 games each, First Four included); lower is better
  // model = full-feature logistic regression (chosen); forecast = rating-only logistic model used for 2018-19
  backtest: { games: 201, model: 0.524, forecastModel: 0.526, boostedTree: 0.538, seed: 0.574, record: 0.703, accuracy: 0.716 },
  // [season, champion, pre-tournament strength rank among 351 D-I teams]
  champions: [['2014-15', 'Duke', 4], ['2015-16', 'Villanova', 8], ['2016-17', 'UNC', 3], ['2017-18', 'Villanova', 1]],
  // explains the pick's 2017-18 measured profile: [label, attribution (log-odds), value vs. field average]
  drivers: [['Adjusted offense', 0.459, '+14.8 pts / 100 poss.'], ['Adjusted scoring margin', 0.443, '+18.4 pts / 100 poss.'], ['Strength of schedule', 0.391, '+5.3']],
  league: {
    conferences: [['Big 12', 17.0], ['Big East', 15.8], ['ACC', 15.7], ['Big Ten', 14.7], ['SEC', 14.4]],
    pace: { from: 66.5, to: 70.9, fromLabel: '2014-15', toLabel: '2017-18' },
    threes: { from: 34.3, to: 37.4 },
    upsetRates: [19.0, 31.7, 22.2], // worse seed wins, round of 64 on, 2015-2017
  },
  quality: { tests: 322, projRmse: 6.49, carryRmse: 7.63 },
  // head-to-head odds from the BigQuery ML win model, as answered by the live Data Agent
  agentH2H: {
    q: 'Villanova vs Duke on a neutral court?',
    a: 'Villanova wins 66.0% of single games against Duke, and Duke wins 34.0%. That is one game, not title odds.',
  },
};

// Palette: arena-night ink + Longhorn burnt orange
const C = {
  ink: '13161C', ink2: '1F242D', ink3: '2A303B',
  orange: 'BF5700', orangeHi: 'F07F2A',
  white: 'FFFFFF', tint: 'F3F4F6', line: 'DDE0E5',
  text: '222731', muted: '6B7280', mutedDark: '9AA3B2', slate: '8C96A6',
};
const FONT = 'Arial';
const SERIF = 'Georgia';
const DIAGRAMS = path.join(__dirname, '..', 'docs', 'diagrams', 'hi');

const shadow = () => ({ type: 'outer', color: '000000', opacity: 0.1, blur: 8, offset: 2, angle: 90 });

async function icon(name, color, size = 256) {
  const svg = ReactDOMServer.renderToStaticMarkup(
    React.createElement(fa[name], { color: '#' + color, size: String(size) })
  );
  const buf = await sharp(Buffer.from(svg)).png().toBuffer();
  return 'image/png;base64,' + buf.toString('base64');
}

async function main() {
  const pres = new pptxgen();
  pres.layout = 'LAYOUT_16x9';
  pres.author = 'Team texas_longhorns';
  pres.title = 'NCAA Championship Predictor — 5-Minute Executive Briefing';

  const S = pres.shapes;
  let pageNo = 0;

  // ---------- helpers ----------
  const card = (slide, x, y, w, h, fill = C.white, opts = {}) =>
    slide.addShape(S.ROUNDED_RECTANGLE, {
      x, y, w, h, rectRadius: 0.08, fill: { color: fill },
      line: opts.line ? { color: opts.line, width: opts.lineWidth || 1, dashType: opts.dash || 'solid' } : { type: 'none' },
      shadow: opts.shadow ? shadow() : undefined,
    });

  const iconCircle = async (slide, name, x, y, d, fill = C.orange, fg = C.white) => {
    slide.addShape(S.OVAL, { x, y, w: d, h: d, fill: { color: fill }, line: { type: 'none' } });
    const pad = d * 0.26;
    slide.addImage({ data: await icon(name, fg), x: x + pad, y: y + pad, w: d - 2 * pad, h: d - 2 * pad });
  };

  const eyebrow = (slide, text, x, y, w, color = C.orange) =>
    slide.addText(text, { x, y, w, h: 0.28, fontFace: FONT, fontSize: 10, bold: true, color, charSpacing: 2, margin: 0 });

  const header = (slide, kicker, title, dark = false) => {
    eyebrow(slide, kicker, 0.6, 0.38, 8.8, dark ? C.orangeHi : C.orange);
    slide.addText(title, {
      x: 0.6, y: 0.64, w: 8.8, h: 0.62, fontFace: FONT, fontSize: 28, bold: true,
      color: dark ? C.white : C.ink, margin: 0, valign: 'top',
    });
  };

  const subtitle = (slide, text, y = 1.22, dark = false) =>
    slide.addText(text, { x: 0.6, y, w: 8.8, h: 0.34, fontFace: FONT, fontSize: 14, color: dark ? C.mutedDark : C.muted, margin: 0 });

  const footer = (slide, dark = false) => {
    pageNo += 1;
    slide.addText(String(pageNo), {
      x: 9.0, y: 5.25, w: 0.5, h: 0.25, fontFace: FONT, fontSize: 9, align: 'right',
      color: dark ? C.slate : C.muted, margin: 0,
    });
  };

  const illustrative = (slide, x, y, w = 3.3, dark = false) => {
    if (DATA.final) return;
    slide.addShape(S.ROUNDED_RECTANGLE, {
      x, y, w, h: 0.28, rectRadius: 0.14, fill: { color: dark ? C.ink2 : C.white },
      line: { color: dark ? C.orangeHi : C.orange, width: 1 },
    });
    slide.addText('ILLUSTRATIVE — replace with sim_/eval_ results', {
      x, y, w, h: 0.28, fontFace: FONT, fontSize: 8, bold: true, align: 'center', valign: 'middle',
      color: dark ? C.orangeHi : C.orange, charSpacing: 1, margin: 0,
    });
  };

  const arrow = (slide, x, y, w, color = C.slate) =>
    slide.addShape(S.LINE, { x, y, w, h: 0, line: { color, width: 1.5, endArrowType: 'triangle' } });

  const bulletList = (items, size = 12, color = C.text) =>
    items.map((t, i) => ({
      text: t,
      options: { bullet: { indent: 12 }, fontSize: size, color, breakLine: i < items.length - 1, paraSpaceAfter: 5 },
    }));

  // =====================================================================
  // 1. THE PICK (dark)
  // =====================================================================
  {
    const s = pres.addSlide();
    s.background = { color: C.ink };
    eyebrow(s, 'TEAM TEXAS_LONGHORNS', 0.6, 0.5, 4.6, C.orangeHi);
    s.addText('Who wins the 2019 national title?', {
      x: 0.6, y: 0.95, w: 4.6, h: 0.4, fontFace: FONT, fontSize: 18, color: C.mutedDark, margin: 0,
    });
    s.addText(DATA.pick.team, {
      x: 0.6, y: 1.35, w: 4.6, h: 0.75, fontFace: FONT, fontSize: 44, bold: true, color: C.white, margin: 0,
    });
    s.addText(DATA.pick.seed, {
      x: 0.6, y: 2.1, w: 4.3, h: 0.28, fontFace: FONT, fontSize: 12, color: C.mutedDark, margin: 0,
    });
    s.addText(`${DATA.pick.pct}%`, {
      x: 0.6, y: 2.38, w: 4.6, h: 1.3, fontFace: FONT, fontSize: 96, bold: true, color: C.orangeHi, margin: 0,
    });
    s.addText('chance to win it all, across 10,000 simulated tournaments', {
      x: 0.6, y: 3.72, w: 4.3, h: 0.6, fontFace: FONT, fontSize: 15, color: C.white, margin: 0, valign: 'top',
    });
    const pk = DATA.pick;
    s.addText(`Projected margin +${pk.margin} pts / 100 poss. (80% band +${pk.bandLow} to +${pk.bandHigh})`, {
      x: 0.6, y: 4.3, w: 4.5, h: 0.28, fontFace: FONT, fontSize: 11, color: C.mutedDark, margin: 0,
    });
    s.addText('A forecast, not a guess.', {
      x: 0.6, y: 4.62, w: 4.3, h: 0.4, fontFace: SERIF, fontSize: 16, italic: true, color: C.mutedDark, margin: 0,
    });

    card(s, 5.3, 0.5, 4.2, 4.6, C.ink2);
    s.addText('Title odds, top 5 contenders', {
      x: 5.55, y: 0.72, w: 3.7, h: 0.3, fontFace: FONT, fontSize: 13, bold: true, color: C.white, margin: 0,
    });
    // Bars are native shapes (not addChart) so they render in PowerPoint, Keynote and Google Slides.
    const maxPct = Math.max(...DATA.contenders.map((c) => c[1]));
    DATA.contenders.forEach(([team, pct], i) => {
      const y = 1.3 + i * 0.62;
      const pick = i === 0;
      s.addText(team, {
        x: 5.55, y, w: 1.5, h: 0.4, fontFace: FONT, fontSize: 13, bold: pick, color: pick ? C.white : C.mutedDark, valign: 'middle', margin: 0,
      });
      s.addShape(S.ROUNDED_RECTANGLE, { x: 7.1, y: y + 0.08, w: 2.2, h: 0.24, rectRadius: 0.12, fill: { color: C.ink3 }, line: { type: 'none' } });
      const bw = Math.max(0.24, 1.5 * (pct / maxPct));
      s.addShape(S.ROUNDED_RECTANGLE, { x: 7.1, y: y + 0.08, w: bw, h: 0.24, rectRadius: 0.12, fill: { color: pick ? C.orangeHi : '5A6475' }, line: { type: 'none' } });
      s.addText(`${pct}%`, {
        x: 7.1 + bw + 0.08, y, w: 0.65, h: 0.4, fontFace: FONT, fontSize: 13, bold: true, color: pick ? C.orangeHi : C.white, valign: 'middle', margin: 0,
      });
    });
    illustrative(s, 5.75, 4.6, 3.3, true);
    footer(s, true);
    s.addNotes(
      'OPEN WITH THE ANSWER (30s). The NCAA hired us as its new data team and asked one question: who wins the next title? ' +
      `Our system's answer: ${DATA.pick.team}, with a ${DATA.pick.pct} percent chance to win the 2019 championship, well ahead of Duke at 14.5. ` +
      'That number is not a hunch. It comes from projecting every team\'s strength into next season, building a likely field of 68, and playing that tournament ten thousand times inside BigQuery. ' +
      `It is a forecast with honest uncertainty: ${DATA.pick.team}'s projected margin has an 80 percent band of plus ${DATA.pick.bandLow} to plus ${DATA.pick.bandHigh}, and the projection cannot see early NBA departures or transfers.`
    );
  }

  // =====================================================================
  // 2. THE LEAGUE + A NOISY MARCH (light)
  // =====================================================================
  {
    const s = pres.addSlide();
    s.background = { color: C.white };
    const L = DATA.league;
    header(s, 'THE LEAGUE', 'A strong, changing league with a noisy March');

    // Conference strength
    card(s, 0.6, 1.4, 3.75, 1.95, C.tint);
    s.addText('Strongest conferences, 2017-18', { x: 0.8, y: 1.52, w: 3.4, h: 0.26, fontFace: FONT, fontSize: 12, bold: true, color: C.text, margin: 0 });
    const maxConf = Math.max(...L.conferences.map((c) => c[1]));
    L.conferences.forEach(([conf, m], i) => {
      const y = 1.84 + i * 0.25;
      s.addText(conf, { x: 0.8, y, w: 0.85, h: 0.22, fontFace: FONT, fontSize: 10.5, bold: i === 0, color: C.text, valign: 'middle', margin: 0 });
      const bw = 2.0 * (m / maxConf);
      s.addShape(S.ROUNDED_RECTANGLE, { x: 1.7, y: y + 0.04, w: bw, h: 0.15, rectRadius: 0.07, fill: { color: i === 0 ? C.orange : C.slate }, line: { type: 'none' } });
      s.addText(`+${m.toFixed(1)}`, { x: 1.7 + bw + 0.06, y, w: 0.5, h: 0.22, fontFace: FONT, fontSize: 10, bold: true, color: C.text, valign: 'middle', margin: 0 });
    });
    s.addText('Average adjusted margin, pts / 100 poss.', { x: 0.8, y: 3.1, w: 3.4, h: 0.2, fontFace: FONT, fontSize: 8.5, italic: true, color: C.muted, margin: 0 });

    // Trend stats
    const trends = [
      ['FaBolt', 'A faster game', `${L.pace.from} → ${L.pace.to}`, `possessions per game, ${L.pace.fromLabel} to ${L.pace.toLabel}`],
      ['FaBullseye', 'More threes', `${L.threes.from}% → ${L.threes.to}%`, 'share of shots from three, up every season'],
    ];
    for (let i = 0; i < trends.length; i++) {
      const [ic, h, big, d] = trends[i];
      const x = 4.55 + i * 2.5;
      card(s, x, 1.4, 2.35, 1.95, C.tint);
      await iconCircle(s, ic, x + 0.2, 1.55, 0.42);
      s.addText(h, { x: x + 0.72, y: 1.6, w: 1.55, h: 0.32, fontFace: FONT, fontSize: 12, bold: true, color: C.text, valign: 'middle', margin: 0 });
      s.addText(big, { x: x + 0.2, y: 2.1, w: 2.1, h: 0.55, fontFace: FONT, fontSize: 20, bold: true, color: C.orange, margin: 0 });
      s.addText(d, { x: x + 0.2, y: 2.68, w: 2.0, h: 0.55, fontFace: FONT, fontSize: 10, color: C.muted, margin: 0, valign: 'top' });
    }

    // Noisy March band
    card(s, 0.6, 3.55, 8.8, 1.55, C.ink);
    const avgUpset = L.upsetRates.reduce((x, y) => x + y, 0) / L.upsetRates.length;
    s.addText(`${Math.round(avgUpset)}%`, { x: 0.85, y: 3.68, w: 1.7, h: 0.75, fontFace: FONT, fontSize: 40, bold: true, color: C.orangeHi, margin: 0 });
    s.addText('of NCAA tournament games went to the worse seed, 2015–2017', {
      x: 0.85, y: 4.42, w: 2.4, h: 0.55, fontFace: FONT, fontSize: 10.5, color: C.white, margin: 0, valign: 'top',
    });
    s.addText("CHAMPION'S STRENGTH RANK GOING IN", { x: 3.45, y: 3.7, w: 3.3, h: 0.22, fontFace: FONT, fontSize: 8.5, bold: true, color: C.orangeHi, charSpacing: 1.2, margin: 0 });
    DATA.champions.forEach(([season, team, rank], i) => {
      const cx = 3.45 + i * 0.82;
      const d = 0.52;
      s.addShape(S.OVAL, { x: cx + 0.12, y: 4.0, w: d, h: d, fill: { color: rank > 1 ? C.orange : C.ink3 }, line: { type: 'none' } });
      s.addText(`#${rank}`, { x: cx + 0.12, y: 4.0, w: d, h: d, fontFace: FONT, fontSize: 13, bold: true, color: C.white, align: 'center', valign: 'middle', margin: 0 });
      s.addText([
        { text: team, options: { bold: true, color: C.white, breakLine: true } },
        { text: season, options: { color: C.mutedDark } },
      ], { x: cx - 0.05, y: 4.55, w: 0.86, h: 0.42, fontFace: FONT, fontSize: 8.5, align: 'center', margin: 0 });
    });
    s.addText([
      { text: "So we don't pick a team.", options: { bold: true, color: C.white, breakLine: true } },
      { text: 'We play the tournament 10,000 times and count champions.', options: { color: C.mutedDark } },
    ], { x: 6.95, y: 3.7, w: 2.3, h: 1.25, fontFace: FONT, fontSize: 12, valign: 'middle', margin: 0 });
    footer(s);
    s.addNotes(
      'THE LEAGUE (30s). First, what the league looks like. The Big 12 was the strongest conference in 2017-18, just ahead of the Big East and ACC. ' +
      `The game is changing: pace rose from ${L.pace.from} to about 71 possessions per game, and the share of shots from three went up every season, from ${L.threes.from} to ${L.threes.to} percent. ` +
      `And March is noisy: about one tournament game in four went to the worse seed. Three of the last four champions were not the strongest team going in. ` +
      'So we do not pick a team. We play the tournament ten thousand times and count champions.'
    );
  }

  // =====================================================================
  // 3. ARCHITECTURE (light)
  // =====================================================================
  {
    const s = pres.addSlide();
    s.background = { color: C.white };
    header(s, 'ARCHITECTURE', 'One governed engine, from raw data to answer');

    const lanes = [
      { title: 'SOURCES', boxes: [['ncaa_basketball', 'raw tables, read-only'], ['Knowledge Catalog', 'scans + 151-term glossary']] },
      { title: 'dbt ON BIGQUERY', boxes: [['stg_ · dq_', 'clean + quality gate'], ['f_ report cards', 'every team, every season'], ['mart_ tables', 'what the agent reads']] },
      { title: 'INTELLIGENCE', boxes: [['BQML win model', 'P(A beats B), any matchup'], ['2018-19 projection', 'field of 68 + bracket'], ['10,000× simulation', 'pure SQL, seeded'], ['AI.GENERATE', 'anonymized scouting']], hot: 2 },
      { title: 'DELIVERY', boxes: [['BigQuery Data Agent', 'Agents Hub · live', 'live'], ['Looker Studio', 'report · in progress', 'building'], ['Gemini Enterprise', 'target state', 'target']] },
    ];
    const laneW = 2.0, gap = 0.27, top = 1.4, laneH = 2.55;
    lanes.forEach((lane, li) => {
      const x = 0.6 + li * (laneW + gap);
      card(s, x, top, laneW, laneH, C.tint);
      s.addText(lane.title, {
        x: x + 0.14, y: top + 0.1, w: laneW - 0.28, h: 0.24, fontFace: FONT, fontSize: 9, bold: true, color: C.orange, charSpacing: 1.5, margin: 0,
      });
      const n = lane.boxes.length;
      const areaTop = top + 0.42, areaH = laneH - 0.54, bGap = 0.1;
      const bh = (areaH - bGap * (n - 1)) / n;
      lane.boxes.forEach(([h, d, status], bi) => {
        const y = areaTop + bi * (bh + bGap);
        const isTarget = status === 'target';
        const isBuilding = status === 'building';
        const isLive = status === 'live';
        const isHot = lane.hot === bi;
        const fill = isTarget ? C.tint : isHot ? C.orange : isLive ? C.ink : C.white;
        const border = isTarget ? { line: C.slate, dash: 'dash' } : isBuilding ? { line: C.orange, dash: 'dash', lineWidth: 1.25 } : { line: isHot || isLive ? undefined : C.line };
        card(s, x + 0.12, y, laneW - 0.24, bh, fill, border);
        const fg = isTarget ? C.muted : isHot || isLive ? C.white : C.ink;
        const fg2 = isTarget ? C.muted : isHot ? 'FBE3CF' : isLive ? C.orangeHi : isBuilding ? C.orange : C.muted;
        s.addText([
          { text: h, options: { fontSize: 11, bold: true, color: fg, breakLine: true } },
          { text: d, options: { fontSize: 9, color: fg2 } },
        ], { x: x + 0.2, y, w: laneW - 0.4, h: bh, fontFace: FONT, valign: 'middle', margin: 0 });
      });
      if (li < lanes.length - 1) arrow(s, x + laneW + 0.03, top + laneH / 2, gap - 0.06, C.orange);
    });

    const whys = [
      ['FaWarehouse', 'Compute stays in BigQuery', 'Models, simulation and Gemini run where the data lives.'],
      ['FaShieldHalved', 'Every claim traces to SQL', 'Answers come from governed tables; Gemini never sees a team name.'],
      ['FaArrowsRotate', 'Rebuilt from code', `Two commands, raw data to marts; ${DATA.quality.tests} dbt tests pass.`],
    ];
    for (let i = 0; i < whys.length; i++) {
      const [ic, h, d] = whys[i];
      const x = 0.6 + i * 3.0;
      await iconCircle(s, ic, x, 4.28, 0.52);
      s.addText(h, { x: x + 0.64, y: 4.22, w: 2.3, h: 0.28, fontFace: FONT, fontSize: 12, bold: true, color: C.ink, margin: 0 });
      s.addText(d, { x: x + 0.64, y: 4.51, w: 2.25, h: 0.55, fontFace: FONT, fontSize: 10.5, color: C.muted, margin: 0, valign: 'top' });
    }
    footer(s);
    s.addNotes(
      'ARCHITECTURE (1 min 15s). Read left to right. Raw NCAA tables and Knowledge Catalog scans come in; one dbt project cleans them, tests them, and builds a report card for every team and season. ' +
      'The intelligence layer is all in BigQuery: a BQML model predicts any single matchup, we project every team into next season and build a likely field of 68, a pure-SQL simulation plays that bracket ten thousand times, and AI.GENERATE writes scouting reports. ' +
      'On top, the Data Agent is live on these marts and on the BigQuery ML model\'s head-to-head odds; the Looker report is being built, and Gemini Enterprise is the target front door. ' +
      'Three choices, and why: compute stays next to the data, so governance holds. Every answer traces to SQL, and Gemini sees numbers, never names, so it cannot lean on what it knows about 2019. ' +
      `And everything rebuilds from code: one command for the pipeline, one for the Gemini outputs, and ${DATA.quality.tests} dbt tests pass.`
    );
  }

  // =====================================================================
  // 4. WHY WE TRUST IT (light)
  // =====================================================================
  {
    const s = pres.addSlide();
    s.background = { color: C.white };
    header(s, 'STRATEGY', 'Why we trust the pick');
    s.addText(`Tested on unseen tournaments · next-season projection RMSE ${DATA.quality.projRmse} vs ${DATA.quality.carryRmse} carrying ratings forward`, {
      x: 0.6, y: 1.22, w: 8.8, h: 0.34, fontFace: FONT, fontSize: 12.5, color: C.muted, margin: 0,
    });

    // Backtest chart
    card(s, 0.6, 1.75, 4.55, 3.4, C.tint);
    s.addText('Prediction error, lower is better (log loss)', {
      x: 0.82, y: 1.9, w: 4.1, h: 0.3, fontFace: FONT, fontSize: 12, bold: true, color: C.text, margin: 0, valign: 'top',
    });
    s.addText(`${DATA.backtest.games} games, 2015–2017 NCAA tournaments`, {
      x: 0.82, y: 2.18, w: 4.1, h: 0.24, fontFace: FONT, fontSize: 10, color: C.muted, margin: 0,
    });
    const b = DATA.backtest;
    const cols = [['Our model', b.model, C.orange], ['Better seed wins', b.seed, 'A3ABB8'], ['Better record wins', b.record, 'A3ABB8']];
    const baseY = 4.2, maxH = 1.45;
    cols.forEach(([label, v, color], i) => {
      const x = 1.0 + i * 1.33;
      const h = maxH * (v / Math.max(b.model, b.seed, b.record));
      s.addShape(S.RECTANGLE, { x, y: baseY - h, w: 0.95, h, fill: { color }, line: { type: 'none' } });
      s.addText([
        { text: v.toFixed(3), options: { fontSize: 18, bold: true, color: i === 0 ? C.orange : C.text } },
      ], { x: x - 0.25, y: baseY - h - 0.4, w: 1.45, h: 0.36, fontFace: FONT, align: 'center', valign: 'bottom', margin: 0 });
      s.addText(label, { x: x - 0.2, y: baseY + 0.06, w: 1.35, h: 0.26, fontFace: FONT, fontSize: 10, bold: i === 0, color: C.text, align: 'center', margin: 0 });
    });
    s.addShape(S.LINE, { x: 0.82, y: baseY, w: 4.1, h: 0, line: { color: C.slate, width: 1 } });
    s.addText(`${Math.round(100 * (1 - b.model / b.seed))}% less error than seeds · beat both baselines every year`, {
      x: 0.82, y: 4.7, w: 4.1, h: 0.3, fontFace: FONT, fontSize: 9.5, italic: true, color: C.muted, margin: 0,
    });

    // Drivers
    s.addText(`What the model sees in ${DATA.pick.team}`, {
      x: 5.45, y: 1.75, w: 3.95, h: 0.3, fontFace: FONT, fontSize: 13, bold: true, color: C.ink, margin: 0,
    });
    const maxAttr = Math.max(...DATA.drivers.map((d) => d[1]));
    DATA.drivers.forEach(([label, attr, detail], i) => {
      const y = 2.12 + i * 0.47;
      const v = attr / maxAttr;
      s.addText(label, { x: 5.45, y, w: 2.3, h: 0.22, fontFace: FONT, fontSize: 10.5, bold: i === 0, color: C.text, margin: 0 });
      s.addText(`${detail} vs. field`, { x: 7.6, y, w: 1.8, h: 0.22, fontFace: FONT, fontSize: 9.5, color: C.muted, align: 'right', margin: 0 });
      s.addShape(S.ROUNDED_RECTANGLE, { x: 5.45, y: y + 0.24, w: 3.95, h: 0.12, rectRadius: 0.06, fill: { color: C.tint }, line: { type: 'none' } });
      s.addShape(S.ROUNDED_RECTANGLE, { x: 5.45, y: y + 0.24, w: Math.max(0.15, 3.95 * v), h: 0.12, rectRadius: 0.06, fill: { color: i === 0 ? C.orange : C.slate }, line: { type: 'none' } });
    });

    // Agent Q&A mock
    card(s, 5.45, 3.6, 3.95, 1.55, C.ink);
    s.addText('ASK THE FRONT OFFICE ANALYST · LIVE', {
      x: 5.65, y: 3.72, w: 3.65, h: 0.22, fontFace: FONT, fontSize: 8.5, bold: true, color: C.orangeHi, charSpacing: 1.5, margin: 0,
    });
    s.addShape(S.ROUNDED_RECTANGLE, { x: 6.5, y: 3.98, w: 2.75, h: 0.3, rectRadius: 0.15, fill: { color: C.ink3 }, line: { type: 'none' } });
    s.addText(DATA.agentH2H.q, { x: 6.5, y: 3.98, w: 2.75, h: 0.3, fontFace: FONT, fontSize: 10, color: C.white, align: 'center', valign: 'middle', margin: 0 });
    s.addText(DATA.agentH2H.a, {
      x: 5.65, y: 4.34, w: 3.6, h: 0.5, fontFace: FONT, fontSize: 10.5, color: C.white, margin: 0, valign: 'top',
    });
    s.addText('↳ BigQuery ML head-to-head odds (p_matchup), via SQL', {
      x: 5.65, y: 4.84, w: 3.6, h: 0.24, fontFace: FONT, fontSize: 9, italic: true, color: C.mutedDark, margin: 0,
    });

    illustrative(s, 6.1, 0.36, 3.3);
    footer(s);
    s.addNotes(
      'WHY TRUST IT (1 min). A forecast is only worth something if it beats the simple answers. ' +
      `We replayed the 2015, 2016 and 2017 tournaments, ${b.games} games, using only games played before each one. ` +
      `Our model's error was ${b.model}, against ${b.seed} for "the better seed always wins" and ${b.record} for "the better record always wins". It beat both baselines in all three years. ` +
      `The forecast uses the ratings-only version, which scored ${b.forecastModel}. ` +
      `In ${DATA.pick.team}'s 2017-18 profile, the model weighs adjusted offense, adjusted scoring margin, and strength of schedule most. ` +
      `The next-season projection also beat simply carrying ratings forward, RMSE ${DATA.quality.projRmse} against ${DATA.quality.carryRmse}. ` +
      `And the live agent answers head-to-head questions straight from the BigQuery ML model: ${DATA.pick.team} beats Duke 66 percent of the time in a single game on a neutral court.`
    );
  }

  // =====================================================================
  // 5. WHAT WE LEARNED (light)
  // =====================================================================
  {
    const s = pres.addSlide();
    s.background = { color: C.white };
    header(s, 'DISCOVERY & GROWTH', 'Three walls, three workarounds');

    s.addText('THE WALL', { x: 1.25, y: 1.38, w: 3, h: 0.24, fontFace: FONT, fontSize: 9, bold: true, color: C.muted, charSpacing: 1.5, margin: 0 });
    s.addText('HOW WE GOT PAST IT', { x: 5.55, y: 1.38, w: 3, h: 0.24, fontFace: FONT, fontSize: 9, bold: true, color: C.orange, charSpacing: 1.5, margin: 0 });
    const rows = [
      ['No permission to create Dataform repositories', 'dbt on BigQuery', 'runs from laptops and CI, tests built in'],
      ["AI.GENERATE_TABLE needs a connection we can't create", 'AI.GENERATE with output_schema', 'the same structured scouting output'],
      ['Gemini already knows who won in 2019', 'Anonymized prompts', 'numbers only: no team name, conference or seed'],
    ];
    for (let i = 0; i < rows.length; i++) {
      const [wall, fix, fixD] = rows[i];
      const y = 1.7 + i * 0.78;
      card(s, 0.6, y, 4.2, 0.64, C.tint);
      await iconCircle(s, 'FaBan', 0.75, y + 0.14, 0.36, 'A3ABB8');
      s.addText(wall, { x: 1.25, y, w: 3.45, h: 0.64, fontFace: FONT, fontSize: 11.5, color: C.text, valign: 'middle', margin: 0 });
      arrow(s, 4.9, y + 0.32, 0.45, C.orange);
      card(s, 5.45, y, 3.95, 0.64, C.white, { line: C.line, shadow: true });
      await iconCircle(s, 'FaKey', 5.6, y + 0.14, 0.36);
      s.addText([
        { text: fix, options: { fontSize: 12, bold: true, color: C.ink, breakLine: true } },
        { text: fixD, options: { fontSize: 10, color: C.muted } },
      ], { x: 6.1, y, w: 3.2, h: 0.64, fontFace: FONT, valign: 'middle', margin: 0 });
    }

    card(s, 0.6, 4.18, 8.8, 0.95, C.ink);
    await iconCircle(s, 'FaLightbulb', 0.85, 4.38, 0.55, C.orangeHi);
    s.addText('KEY TAKEAWAY', { x: 1.6, y: 4.3, w: 3, h: 0.22, fontFace: FONT, fontSize: 8.5, bold: true, color: C.orangeHi, charSpacing: 1.5, margin: 0 });
    s.addText('Keep compute next to the data. Ground every AI claim in a query.', {
      x: 1.6, y: 4.52, w: 7.6, h: 0.45, fontFace: SERIF, fontSize: 16, italic: true, color: C.white, margin: 0,
    });
    footer(s);
    s.addNotes(
      'WHAT WE LEARNED (45s). The judges asked what we explored and what we overcame. We hit three walls. ' +
      'No permission for Dataform, so we moved to dbt, which gave us tests and CI for free. ' +
      'AI.GENERATE_TABLE needs a connection we could not create, so we used AI.GENERATE with an output schema and got the same structured scouting reports. ' +
      'And Gemini already knows real results after 2018, so our prompts give it only a team\'s numbers, with no name, conference or seed, and it cannot peek. ' +
      'The lesson we would take to any client: keep compute next to the data, and ground every AI claim in a query.'
    );
  }

  // =====================================================================
  // 6. THE 66DEGREES ACCELERATOR (dark close)
  // =====================================================================
  {
    const s = pres.addSlide();
    s.background = { color: C.ink };
    header(s, 'CONSULTING  ·  66DEGREES', 'Same engine, any client', true);

    const chain = [['Discover', 'Knowledge Catalog'], ['Govern', 'dbt semantic layer'], ['Predict', 'BQML + simulation'], ['Explain', 'grounded Data Agent']];
    chain.forEach(([verb, what], i) => {
      const x = 0.6 + i * 2.25;
      card(s, x, 1.45, 1.95, 0.62, C.ink2);
      s.addText([
        { text: verb, options: { fontSize: 13, bold: true, color: C.orangeHi, breakLine: true } },
        { text: what, options: { fontSize: 10, color: C.mutedDark } },
      ], { x: x + 0.15, y: 1.45, w: 1.7, h: 0.62, fontFace: FONT, valign: 'middle', margin: 0 });
      if (i < chain.length - 1) arrow(s, x + 1.99, 1.76, 0.22, C.orangeHi);
    });

    const uses = [
      ['FaCartShopping', 'Retail', 'Which products sell out next season'],
      ['FaBuildingColumns', 'Banking', 'Which loans are likely to default'],
      ['FaUserMinus', 'Subscriptions', 'Which customers are about to churn'],
      ['FaHandshake', 'B2B sales', 'Which deals close this quarter'],
    ];
    for (let i = 0; i < uses.length; i++) {
      const [ic, h, d] = uses[i];
      const x = 0.6 + i * 2.25;
      card(s, x, 2.3, 2.05, 1.55, C.ink2);
      await iconCircle(s, ic, x + 0.18, 2.47, 0.48, C.orange);
      s.addText(h, { x: x + 0.18, y: 3.03, w: 1.75, h: 0.28, fontFace: FONT, fontSize: 13, bold: true, color: C.white, margin: 0 });
      s.addText(d, { x: x + 0.18, y: 3.3, w: 1.75, h: 0.48, fontFace: FONT, fontSize: 10.5, color: C.mutedDark, margin: 0, valign: 'top' });
    }

    s.addText('Grounded. Reproducible. Reusable.', {
      x: 0.6, y: 4.05, w: 8.8, h: 0.55, fontFace: FONT, fontSize: 24, bold: true, color: C.white, margin: 0,
    });
    s.addText([
      { text: 'Packaged as a ', options: { color: C.mutedDark } },
      { text: '2-week discovery-to-agent', options: { color: C.orangeHi, bold: true } },
      { text: ' engagement for clients already on GCP', options: { color: C.mutedDark } },
    ], { x: 0.6, y: 4.62, w: 8.8, h: 0.32, fontFace: FONT, fontSize: 12, margin: 0, valign: 'middle' });
    footer(s, true);
    s.addNotes(
      'CONSULTING REUSE AND CLOSE (1 min). Nothing here is really about basketball. The pattern is: discover the data with Knowledge Catalog, govern it in a dbt semantic layer, predict with BQML and simulation, and explain through a grounded agent. ' +
      'Swap the dataset and it is a retailer asking which products sell out, a bank asking which loans default, a subscription business asking who churns, or a sales team asking which deals close. ' +
      'For clients already on Google Cloud, we can package it as a two-week engagement, from discovery to a working agent. ' +
      `So: ${DATA.pick.team}, ${DATA.pick.pct} percent. Grounded, reproducible, reusable. Thank you.`
    );
  }

  // =====================================================================
  // APPENDIX
  // =====================================================================
  {
    const s = pres.addSlide();
    s.background = { color: C.ink };
    eyebrow(s, 'APPENDIX', 0.6, 1.35, 5, C.orangeHi);
    s.addText('Backup for Q&A', { x: 0.6, y: 1.65, w: 8, h: 0.9, fontFace: FONT, fontSize: 44, bold: true, color: C.white, margin: 0 });
    const items = ['A1  Team: six-station assembly line', 'A2  Forecast mechanics', 'A3  Architecture detail', 'A4  The grounding chain',
      'A5  Agent runtime', 'A6  Engineering backbone', 'A7  Learning journey, in full', 'A8  Assessment matrix'];
    [items.slice(0, 4), items.slice(4)].forEach((col, ci) => {
      s.addText(col.map((t, i) => ({ text: t, options: { breakLine: i < col.length - 1, paraSpaceAfter: 6 } })), {
        x: 0.6 + ci * 4.2, y: 2.85, w: 4.0, h: 1.6, fontFace: FONT, fontSize: 13, color: C.mutedDark, margin: 0, valign: 'top',
      });
    });
    footer(s, true);
  }

  // A1 Team
  {
    const s = pres.addSlide();
    s.background = { color: C.white };
    header(s, 'A1  ·  TEAM', 'A six-station assembly line');
    subtitle(s, 'Each station hands finished BigQuery tables to the next. A hand-off is a pass; the table is the ball.');
    const hc = (t) => ({ text: t, options: { bold: true, color: C.white, fill: { color: C.ink } } });
    const rows = [
      [hc('Station'), hc('Role'), hc('Produces')],
      ['1 · Clean', 'Data Engineer 1', 'Staging views + data-quality checks (stg_, dq_)'],
      ['2 · Grade', 'Data Engineer 2', 'Team report cards + mart tables (f_, mart_)'],
      ['3 · Predict', 'Data Scientist 1', 'BQML matchup model + matchup odds (m_, p_)'],
      ['4 · Simulate', 'Data Scientist 2', '10,000-run simulation, backtests, projection (sim_, eval_)'],
      ['5 · Narrate', 'Analytics Engineer', 'AI.GENERATE scouting + Looker dashboard (ai_)'],
      ['6 · Answer', 'Team Captain', 'Front Office Analyst agent + the pitch'],
    ];
    s.addTable(rows, {
      x: 0.6, y: 1.75, w: 8.8, colW: [1.6, 2.0, 5.2], rowH: 0.44,
      fontFace: FONT, fontSize: 11.5, color: C.text, valign: 'middle',
      border: { type: 'solid', pt: 0.75, color: C.line }, fill: { color: C.white },
    });
    footer(s);
  }

  // A2 Forecast mechanics
  {
    const s = pres.addSlide();
    s.background = { color: C.white };
    header(s, 'A2  ·  FORECAST MECHANICS', 'Matchup model → simulation → backtest');
    const cols = [
      ['FaBrain', 'Predict one game', 'BQML · STATION 3', ['Walk-forward: P(A beats B) on a neutral court; seeds never enter', `Logistic regression chosen over boosted tree (log loss ${DATA.backtest.model} vs ${DATA.backtest.boostedTree})`, `The 2018-19 forecast uses the ratings-only version (${DATA.backtest.forecastModel})`, 'ML.EXPLAIN_PREDICT gives each team\'s top 3 drivers']],
      ['FaDice', 'Play it 10,000×', 'PROJECTION + SIMULATION', [`Projected ratings beat carry-forward (RMSE ${DATA.quality.projRmse} vs ${DATA.quality.carryRmse})`, 'Build a projected field of 68 and its bracket', 'One SQL model: 10,000 brackets × 67 games, seeded', 'Count how often each team wins each round']],
      ['FaChartColumn', 'Prove it works', 'BACKTEST · STATION 4', ['Replay March 2015–2018; train only on earlier games', 'Beat seed + record baselines all 3 core years', 'Seed baseline 2015–2017 only (no 2018 seeds)', 'Boosted tree won 2018, but the choice uses core years only']],
    ];
    for (let i = 0; i < cols.length; i++) {
      const [ic, h, k, items] = cols[i];
      const x = 0.6 + i * 3.0;
      card(s, x, 1.5, 2.8, 3.5, C.tint);
      await iconCircle(s, ic, x + 0.2, 1.7, 0.5);
      s.addText(h, { x: x + 0.2, y: 2.3, w: 2.4, h: 0.32, fontFace: FONT, fontSize: 15, bold: true, color: C.ink, margin: 0 });
      s.addText(k, { x: x + 0.2, y: 2.62, w: 2.4, h: 0.24, fontFace: FONT, fontSize: 9, bold: true, color: C.orange, charSpacing: 1, margin: 0 });
      s.addText(bulletList(items, 11), { x: x + 0.2, y: 2.95, w: 2.45, h: 1.95, fontFace: FONT, margin: 0, valign: 'top' });
    }
    footer(s);
  }

  // A3 Architecture detail (diagram + step callouts)
  {
    const s = pres.addSlide();
    s.background = { color: C.white };
    header(s, 'A3  ·  ARCHITECTURE DETAIL', 'End-to-end agentic solution (target state)');
    const h = 4.0, w = h * (2763 / 1929);
    s.addImage({ path: path.join(DIAGRAMS, '1-end-to-end-architecture.png'), x: 0.5, y: 1.35, w, h });
    const steps = [
      ['User query', 'prompt submitted to Gemini'],
      ['Agent handoff', 'delegated to the BigQuery Data Agent'],
      ['NL → SQL', 'natural language becomes SQL'],
      ['Semantic grounding', 'curated tables, BQML, AI.GENERATE'],
      ['Read-only query', 'runs over immutable sources'],
      ['Insight delivery', 'synthesized answer with evidence'],
    ];
    steps.forEach(([t, d], i) => {
      const y = 1.4 + i * 0.64;
      s.addShape(S.OVAL, { x: 6.35, y, w: 0.34, h: 0.34, fill: { color: C.orange }, line: { type: 'none' } });
      s.addText(String(i + 1), { x: 6.35, y, w: 0.34, h: 0.34, fontFace: FONT, fontSize: 11, bold: true, color: C.white, align: 'center', valign: 'middle', margin: 0 });
      s.addText([
        { text: t, options: { bold: true, color: C.ink, fontSize: 11, breakLine: true } },
        { text: d, options: { color: C.muted, fontSize: 9.5 } },
      ], { x: 6.82, y: y - 0.05, w: 2.6, h: 0.5, fontFace: FONT, margin: 0, valign: 'top' });
    });
    footer(s);
  }

  // A4 Grounding chain
  {
    const s = pres.addSlide();
    s.background = { color: C.white };
    header(s, 'A4  ·  TRUST BY DESIGN', 'The grounding chain');
    subtitle(s, 'Every LLM claim traces to a query result. No ungrounded predictions.');
    const w = 8.8, h = w * (1089 / 2559);
    s.addImage({ path: path.join(DIAGRAMS, '2-grounding-chain.png'), x: 0.6, y: 1.75, w, h });
    footer(s);
  }

  // A5 Agent runtime
  {
    const s = pres.addSlide();
    s.background = { color: C.white };
    header(s, 'A5  ·  THE AI LAYER', 'Front Office Analyst: target runtime');
    const h = 3.7, w = h * (2829 / 1542);
    s.addImage({ path: path.join(DIAGRAMS, '3-runtime-sequence.png'), x: 0.5, y: 1.45, w, h });
    const pts = ['AI.GENERATE with gemini-2.5-flash, temperature 0, output_schema', 'Prompts carry numbers only: no team name, conference or seed', 'Agent live: 9 tables incl. BQML head-to-head odds; 10 verified examples'];
    s.addText(bulletList(pts, 10.5), { x: 7.45, y: 1.6, w: 2.05, h: 3.4, fontFace: FONT, margin: 0, valign: 'top' });
    footer(s);
  }

  // A6 Engineering backbone
  {
    const s = pres.addSlide();
    s.background = { color: C.white };
    header(s, 'A6  ·  ENGINEERING BACKBONE', 'One dbt project, gated by CI');
    card(s, 0.6, 1.45, 4.3, 3.65, C.tint);
    s.addText('Seven layers, one prefix each', { x: 0.8, y: 1.58, w: 3.9, h: 0.3, fontFace: FONT, fontSize: 13, bold: true, color: C.ink, margin: 0 });
    const layers = [['00_stg', 'stg_', 'staging views, brackets'], ['01_dq', 'dq_', 'quality gate from Catalog scans'], ['02_features', 'f_', 'report cards, matchup rows'],
      ['03_models', 'm_ p_', 'BQML training + predictions'], ['04_sim', 'sim_ eval_', 'simulation, backtests'], ['05_ai', 'ai_', 'AI.GENERATE (tag: ai)'], ['06_marts', 'mart_', 'what dashboard + agent read']];
    layers.forEach(([folder, prefix, d], i) => {
      const y = 1.98 + i * 0.44;
      s.addShape(S.ROUNDED_RECTANGLE, { x: 0.8, y, w: 1.0, h: 0.32, rectRadius: 0.16, fill: { color: i === 3 || i === 4 ? C.orange : C.ink }, line: { type: 'none' } });
      s.addText(prefix, { x: 0.8, y, w: 1.0, h: 0.32, fontFace: FONT, fontSize: 9.5, bold: true, color: C.white, align: 'center', valign: 'middle', margin: 0 });
      s.addText([
        { text: folder + '  ', options: { bold: true, color: C.ink } },
        { text: d, options: { color: C.muted } },
      ], { x: 1.92, y, w: 2.9, h: 0.32, fontFace: FONT, fontSize: 10, valign: 'middle', margin: 0 });
    });

    const jobs = [
      ['FaCodeBranch', 'validate · every PR', 'ruff + dbt parse. Required check, passing on main.', 'LIVE'],
      ['FaDatabase', 'e2e · pull requests', 'Full build into an ephemeral dataset, 100 sims.', 'NOT ENABLED'],
      ['FaServer', 'deploy · main', 'Full build + tests into texas_longhorns.', 'NOT ENABLED'],
    ];
    for (let i = 0; i < jobs.length; i++) {
      const [ic, h, d, status] = jobs[i];
      const y = 1.45 + i * 0.95;
      card(s, 5.15, y, 4.25, 0.8, C.white, { line: C.line, shadow: true });
      await iconCircle(s, ic, 5.32, y + 0.17, 0.46);
      s.addText([
        { text: h, options: { bold: true, color: C.ink, fontSize: 12 } },
        { text: `  ${status}`, options: { bold: true, color: status === 'LIVE' ? '2E7D32' : C.orange, fontSize: 8, breakLine: true } },
        { text: d, options: { color: C.muted, fontSize: 10 } },
      ], { x: 5.95, y, w: 3.35, h: 0.8, fontFace: FONT, valign: 'middle', margin: 0 });
    }
    s.addText(`${DATA.quality.tests} dbt tests pass on the deployed dataset. Before enabling: e2e must build the AI table its mart needs, and deploy shouldn't retrain 17 models per push.`, {
      x: 5.15, y: 4.33, w: 4.25, h: 0.77, fontFace: FONT, fontSize: 10, italic: true, color: C.muted, margin: 0, valign: 'top',
    });
    footer(s);
  }

  // A7 Learning journey
  {
    const s = pres.addSlide();
    s.background = { color: C.white };
    header(s, 'A7  ·  DISCOVERY & GROWTH', 'The learning journey, in full');
    const cols = [
      ['FaCompass', 'New capabilities', ['BigQuery Data Agents (Agents Hub) for governed NL → SQL', 'AI.GENERATE with output_schema for structured scouting', 'BQML training + ML.PREDICT entirely in-warehouse', 'Knowledge Catalog as the grounding source']],
      ['FaRoute', 'Challenges overcome', ['No Dataform permission → dbt on BigQuery', 'AI.GENERATE_TABLE needs a connection → AI.GENERATE', 'dbt OAuth blocked → gcloud access-token target', 'Gemini knows post-2018 results → anonymized prompts']],
      ['FaLightbulb', 'Key takeaways', ['Keep compute next to the data: no movement, governed, fast', 'Ground every claim in a query result to stop hallucination', 'Pick models on core years only; never tune to the extension', 'Let data quality decide: 2013-14 dropped (65% of box scores missing)']],
    ];
    for (let i = 0; i < cols.length; i++) {
      const [ic, h, items] = cols[i];
      const x = 0.6 + i * 3.0;
      card(s, x, 1.45, 2.8, 3.65, C.tint);
      await iconCircle(s, ic, x + 0.2, 1.65, 0.5);
      s.addText(h, { x: x + 0.82, y: 1.72, w: 1.9, h: 0.36, fontFace: FONT, fontSize: 13, bold: true, color: C.ink, margin: 0, valign: 'middle' });
      s.addText(bulletList(items, 11), { x: x + 0.2, y: 2.35, w: 2.45, h: 2.6, fontFace: FONT, margin: 0, valign: 'top' });
    }
    footer(s);
  }

  // A8 Assessment matrix
  {
    const s = pres.addSlide();
    s.background = { color: C.white };
    header(s, 'A8  ·  HOW WE MAP TO THE CRITERIA', 'Assessment matrix');
    const hc = (t) => ({ text: t, options: { bold: true, color: C.white, fill: { color: C.ink } } });
    const rows = [
      [hc('Criterion'), hc('How we satisfy it'), hc('Evidence'), hc('Owner')],
      ['Technical Execution', 'BQML with backtests, in-warehouse AI.GENERATE, live agent on BQML outputs', 'Backtest scorecard, head-to-head Q&A', 'Data + ML Eng'],
      ['Discovery & Growth', 'Catalog scan to data map; dbt + CI; documented learnings', 'Learnings log, CI history', 'Captain + DE'],
      ['Value & Impact', 'Beats seed and record baselines; reusable client pattern', 'Log-loss delta, use cases', 'ML Eng + Captain'],
      ['Storytelling', 'Prediction-first narrative, grounded scouting cards', 'This briefing', 'Captain + Analytics'],
    ];
    s.addTable(rows, {
      x: 0.6, y: 1.5, w: 8.8, colW: [1.8, 3.35, 2.0, 1.65], rowH: 0.62,
      fontFace: FONT, fontSize: 11, color: C.text, valign: 'middle',
      border: { type: 'solid', pt: 0.75, color: C.line }, fill: { color: C.white },
    });
    footer(s);
  }

  const out = path.join(__dirname, 'NCAA_Briefing_5min.pptx');
  await pres.writeFile({ fileName: out });
  console.log('Deck written: ' + out);
}

main().catch((e) => { console.error(e); process.exit(1); });
