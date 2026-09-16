const pptxgen = require('pptxgenjs');
const html2pptx = require('./html2pptx');

const NAVY = "0B2545";
const ORANGE = "EE6C4D";
const STEEL = "3D5A80";
const WHITE = "FFFFFF";

function headerCell(t) {
  return { text: t, options: { fill: { color: NAVY }, color: WHITE, bold: true, valign: "middle" } };
}

async function main() {
  const pptx = new pptxgen();
  pptx.layout = 'LAYOUT_16x9';
  pptx.author = 'NCAA Data Strategy Team';
  pptx.title = 'Predicting the NCAA Champion';

  // 1. Title
  await html2pptx('slides/01-title.html', pptx);

  // 2. Team allocation + table
  {
    const { slide } = await html2pptx('slides/02-team.html', pptx);
    const rows = [
      [headerCell("Role"), headerCell("#"), headerCell("Owns")],
      ["Team Captain", "1", "Catalog discovery, project management, pitch synthesis"],
      ["Data Engineers", "2", "BigQuery schema, pipelines, table structuring"],
      ["Data Scientists", "2", "BQML training, feature selection, prediction logic"],
      ["Analytics Engineers", "2", "AI.GENERATE prompt routines, agent configuration"],
    ];
    slide.addTable(rows, {
      x: 0.55, y: 2.1, w: 9.4, colW: [2.3, 0.6, 6.5],
      rowH: [0.45, 0.55, 0.55, 0.55, 0.55],
      border: { pt: 1, color: "D6DEE8" }, align: "left", valign: "middle",
      fontFace: "Arial", fontSize: 13, color: "2D3748", fill: { color: WHITE },
    });
  }

  // 3-5 content slides
  await html2pptx('slides/03-phase1.html', pptx);
  await html2pptx('slides/04-phase2.html', pptx);
  await html2pptx('slides/05-phase3.html', pptx);

  // 6. Pitch runsheet + table
  {
    const { slide } = await html2pptx('slides/06-phase4.html', pptx);
    const rows = [
      [headerCell("Time"), headerCell("Section"), headerCell("Content")],
      ["0:00-1:00", "Hook", "The champion prediction + confidence, upfront"],
      ["1:00-3:30", "Architecture", "Diagram; why Data Agent + Gemini split; why BQML in-warehouse"],
      ["3:30-6:30", "Strategy / Findings", "Contenders, scouting cards, key drivers, backtest vs. baseline"],
      ["6:30-8:30", "Consulting (66deg)", "How the agentic pattern generalizes to client work"],
      ["8:30-10:00", "Close + Q&A", "Restate prediction, impact, next steps"],
    ];
    slide.addTable(rows, {
      x: 0.55, y: 1.95, w: 9.4, colW: [1.5, 2.4, 5.5],
      rowH: [0.42, 0.5, 0.5, 0.5, 0.5, 0.5],
      border: { pt: 1, color: "D6DEE8" }, align: "left", valign: "middle",
      fontFace: "Arial", fontSize: 12.5, color: "2D3748", fill: { color: WHITE },
    });
  }

  // 7. Consulting
  await html2pptx('slides/07-consulting.html', pptx);

  // 8. Assessment matrix + table
  {
    const { slide } = await html2pptx('slides/08-phase5.html', pptx);
    const rows = [
      [headerCell("Criterion"), headerCell("How We Satisfy It"), headerCell("Evidence"), headerCell("Owner")],
      ["Technical Execution", "BQML w/ backtests, in-warehouse AI.GENERATE, live agent flow", "ML.EVALUATE metrics, agent Q&A", "Data Scientists"],
      ["Discovery & Growth", "Rigorous Catalog scan to Data Map; documented learning", "Data Map, dataset scoring", "Captain + Data Eng"],
      ["Value & Impact", "Prediction beats seed-only baseline; quantified reuse", "Accuracy delta, business case", "Data Sci + Captain"],
      ["Storytelling", "Tight prediction-first narrative, grounded scouting cards", "Runsheet, scouting cards", "Captain + Analytics"],
    ];
    slide.addTable(rows, {
      x: 0.4, y: 1.95, w: 9.6, colW: [1.9, 3.9, 2.0, 1.8],
      rowH: [0.5, 0.7, 0.7, 0.7, 0.7],
      border: { pt: 1, color: "D6DEE8" }, align: "left", valign: "middle",
      fontFace: "Arial", fontSize: 11, color: "2D3748", fill: { color: WHITE },
    });
  }

  // 9-10
  await html2pptx('slides/09-risks.html', pptx);
  await html2pptx('slides/10-close.html', pptx);

  await pptx.writeFile({ fileName: 'NCAA_Execution_Plan.pptx' });
  console.log('Deck written: NCAA_Execution_Plan.pptx');
}

main().catch(e => { console.error(e); process.exit(1); });
