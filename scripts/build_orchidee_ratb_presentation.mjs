import fs from "node:fs/promises";
import path from "node:path";
import { spawnSync } from "node:child_process";

const ROOT = process.cwd();
const SKILL_DIR = "C:/Users/franc/.codex/plugins/cache/openai-primary-runtime/presentations/26.601.10930/skills/presentations";
const THREAD_ID = process.env.CODEX_THREAD_ID || `manual-${new Date().toISOString().replace(/[-:.TZ]/g, "").slice(0, 14)}`;
const WORKSPACE = path.join(ROOT, "outputs", THREAD_ID, "presentations", "orchidee-ratb");
const SLIDES_DIR = path.join(WORKSPACE, "slides");
const PREVIEW_DIR = path.join(WORKSPACE, "preview");
const LAYOUT_DIR = path.join(WORKSPACE, "layout");
const ASSET_DIR = path.join(WORKSPACE, "assets");
const OUTPUT_DIR = path.join(WORKSPACE, "output");
const FINAL_PPTX = path.join(OUTPUT_DIR, "orchidee-ratb-surveillance-methods.pptx");

const theme = {
  bg: "#F7F5F0",
  ink: "#21302F",
  muted: "#687774",
  line: "#D7D1C5",
  accent: "#147A75",
  accent2: "#B94A48",
  gold: "#C99A45",
  pale: "#E7F0ED",
  white: "#FFFFFF",
  dark: "#132322",
  title: "Aptos Display",
  body: "Aptos",
};

const imageAssets = {
  global: path.join(ROOT, "downloads", "presentation_crops", "ratb_global_heatmap_klebsiella_pneumoniae.png"),
  byType: path.join(ROOT, "downloads", "presentation_crops", "ratb_by_type_heatmap_klebsiella_pneumoniae.png"),
  pheno: path.join(ROOT, "downloads", "presentation_crops", "ratb_global_heatmap_enterobacterales.png"),
  incidence: path.join(ROOT, "downloads", "presentation_crops", "ratb_incidence_global_heatmap_klebsiella_pneumoniae.png"),
};

function jsString(value) {
  return JSON.stringify(value);
}

function bullets(items) {
  return items.map((item) => `- ${item}`).join("\n");
}

function titleSlide({ kicker, title, subtitle }) {
  return `
  base(slide, ctx, ${jsString(kicker)});
  ctx.addText(slide, { x: 74, y: 160, w: 820, h: 168, text: ${jsString(title)}, fontSize: 56, bold: true, color: T.ink, typeface: T.title });
  ctx.addShape(slide, { x: 78, y: 350, w: 160, h: 4, fill: T.accent });
  ctx.addText(slide, { x: 74, y: 386, w: 760, h: 95, text: ${jsString(subtitle)}, fontSize: 26, color: T.muted, typeface: T.body });
  ctx.addShape(slide, { x: 958, y: 98, w: 220, h: 508, fill: T.dark, line: ctx.line("transparent", 0) });
  ctx.addText(slide, { x: 990, y: 138, w: 155, h: 60, text: "RATB", fontSize: 34, bold: true, color: T.white, typeface: T.title, align: "center" });
  ctx.addText(slide, { x: 1000, y: 440, w: 140, h: 108, text: "Méthodes\\nRésultats\\nArbitrages", fontSize: 21, color: "#DDE8E5", align: "center" });
`;
}

function textSlide({ kicker, title, body, items = [], note }) {
  const itemText = items.length ? bullets(items) : "";
  return `
  base(slide, ctx, ${jsString(kicker)});
  heading(slide, ctx, ${jsString(title)});
  ${body ? `ctx.addText(slide, { x: 82, y: 154, w: 920, h: 96, text: ${jsString(body)}, fontSize: 24, color: T.ink, typeface: T.body });` : ""}
  ${items.length ? `ctx.addText(slide, { x: 120, y: ${body ? 272 : 164}, w: 880, h: 330, text: ${jsString(itemText)}, fontSize: 23, color: T.ink, typeface: T.body });` : ""}
  ${note ? `callout(slide, ctx, 840, 472, 310, 122, ${jsString(note)});` : ""}
`;
}

function twoColumnSlide({ kicker, title, leftTitle, leftItems, rightTitle, rightItems, footer }) {
  return `
  base(slide, ctx, ${jsString(kicker)});
  heading(slide, ctx, ${jsString(title)});
  panel(slide, ctx, 78, 160, 520, 360, ${jsString(leftTitle)}, ${jsString(bullets(leftItems))});
  panel(slide, ctx, 682, 160, 520, 360, ${jsString(rightTitle)}, ${jsString(bullets(rightItems))});
  ${footer ? `ctx.addText(slide, { x: 92, y: 565, w: 1030, h: 52, text: ${jsString(footer)}, fontSize: 22, color: T.muted });` : ""}
`;
}

function imageSlide({ kicker, title, image, message, source }) {
  return `
  base(slide, ctx, ${jsString(kicker)});
  heading(slide, ctx, ${jsString(title)});
  ctx.addShape(slide, { x: 52, y: 142, w: 900, h: 500, fill: T.white, line: ctx.line(T.line, 1) });
  await ctx.addImage(slide, { x: 66, y: 156, w: 872, h: 472, path: ${jsString(image)}, fit: "contain", alt: ${jsString(title)} });
  ctx.addShape(slide, { x: 980, y: 160, w: 210, h: 360, fill: T.pale, line: ctx.line("transparent", 0) });
  ctx.addText(slide, { x: 1000, y: 188, w: 170, h: 282, text: ${jsString(message)}, fontSize: 19, color: T.ink });
  ctx.addText(slide, { x: 1000, y: 552, w: 175, h: 42, text: ${jsString(source)}, fontSize: 11, color: T.muted });
`;
}

function comparisonSlide() {
  return `
  base(slide, ctx, "RÉSULTATS");
  heading(slide, ctx, "Confronter ORCHIDEE à CONSORES");
  ctx.addText(slide, { x: 82, y: 150, w: 1040, h: 72, text: "La comparaison permet d'identifier les écarts, mais pas toujours de les attribuer immédiatement.", fontSize: 26, color: T.ink });
  const rows = [
    ["Ce qui peut différer", "Impact possible"],
    ["Périmètre hospitalier", "Dénominateur d'incidence différent"],
    ["Périmètre microbiologique", "Souches incluses ou exclues différemment"],
    ["Corrections avant dépôt", "Règles visibles seulement en aval"],
    ["Dédoublonnage", "Numérateurs et proportions modifiés"],
    ["Familles / molécules", "Définition d'indicateur non identique"]
  ];
  table(slide, ctx, 100, 258, 1080, rows);
`;
}

function finalSlide() {
  return `
  base(slide, ctx, "CONCLUSION");
  ctx.addText(slide, { x: 86, y: 132, w: 930, h: 150, text: "ORCHIDEE montre qu'une production semi-automatisée d'indicateurs RATB à partir des données hospitalières est possible.", fontSize: 40, bold: true, color: T.ink, typeface: T.title });
  ctx.addText(slide, { x: 90, y: 330, w: 900, h: 92, text: "La valeur du travail repose autant sur les résultats produits que sur la traçabilité des choix méthodologiques.", fontSize: 28, color: T.muted });
  ctx.addShape(slide, { x: 88, y: 490, w: 1020, h: 2, fill: T.line });
  ctx.addText(slide, { x: 90, y: 526, w: 900, h: 48, text: "Étape 1 : noyau annuel gelé ; les extensions doivent préserver cette base validée ou documenter explicitement tout changement de méthode.", fontSize: 23, color: T.accent, bold: true });
`;
}

const slides = [
  titleSlide({
    kicker: "INTRODUCTION",
    title: "ORCHIDEE",
    subtitle: "Surveillance de la résistance aux antibiotiques à partir des données hospitalières\nObjectifs, méthodes et premiers enseignements",
  }),
  textSlide({
    kicker: "OBJECTIFS",
    title: "ORCHIDEE rend explicites les choix qui transforment les données hospitalières en indicateurs",
    body: "ORCHIDEE vise à utiliser les entrepôts de données de santé hospitaliers pour produire des indicateurs de surveillance en routine.",
    items: [
      "produire et documenter les indicateurs attendus dans le premier périmètre RATB ;",
      "rester cohérent avec la méthodologie SPARES ;",
      "rendre traçables les choix de périmètre, de comptage et de restitution."
    ],
  }),
  textSlide({
    kicker: "CADRE NATIONAL",
    title: "La surveillance RATB existe déjà : ORCHIDEE cherche à s'y aligner",
    items: [
      "Santé publique France pilote la surveillance de l'antibiorésistance via le RéPIA.",
      "En établissement de santé, SPARES définit la méthodologie de collecte et analyse les données de résistance et de consommation.",
      "ConsoRes permet aux établissements de déposer, suivre et comparer leurs données.",
      "Les indicateurs servent au pilotage local, régional, national et à la surveillance européenne/internationale."
    ],
  }),
  textSlide({
    kicker: "PROBLÈME",
    title: "La déclaration actuelle est longue, manuelle et difficile à auditer",
    body: "La production des données de surveillance repose encore sur des extractions et retraitements locaux.",
    items: [
      "rapidité de production limitée ;",
      "reproductibilité des calculs difficile à garantir ;",
      "traçabilité des choix de périmètre et de dédoublonnage partielle ;",
      "comparaison avec les données hospitalières sources complexe."
    ],
    note: "Hypothèse ORCHIDEE : produire plus vite, de façon plus reproductible et plus auditable.",
  }),
  textSlide({
    kicker: "CADRE À REPRODUIRE",
    title: "Le premier objectif RATB est de reproduire le cadre méthodologique SPARES",
    items: [
      "couples bactérie-antibiotique ou bactérie-famille ;",
      "proportions de résistance ;",
      "densités d'incidence rapportées à l'activité hospitalière ;",
      "phénotypes d'intérêt, notamment BLSE et carbapénémase."
    ],
  }),
  textSlide({
    kicker: "PÉRIMÈTRE BIOLOGIQUE",
    title: "Les premiers travaux reprennent les micro-organismes ciblés dans l'expression de besoins",
    items: [
      "Staphylococcus aureus ;",
      "Escherichia coli ;",
      "Klebsiella pneumoniae ;",
      "Enterobacter cloacae complex ;",
      "Enterococcus faecium et Enterococcus faecalis ;",
      "Pseudomonas aeruginosa ;",
      "Acinetobacter baumannii."
    ],
  }),
  twoColumnSlide({
    kicker: "POPULATION",
    title: "Le périmètre SPARES est reconstruit à partir de la structure hospitalière locale",
    leftTitle: "Principe de surveillance",
    leftItems: [
      "pas toute l'activité hospitalière ;",
      "hospitalisation complète ou de semaine ;",
      "secteurs cliniques concernés."
    ],
    rightTitle: "Traduction ORCHIDEE",
    rightItems: [
      "unités fonctionnelles locales ;",
      "TA : type d'activité ;",
      "DE : domaine d'activité ;",
      "croisement UF locale × TA/DE."
    ],
    footer: "Le fichier structure permet d'aligner l'activité hospitalière locale sur le périmètre SPARES.",
  }),
  textSlide({
    kicker: "DONNÉES MICROBIOLOGIQUES",
    title: "Dans les données, on observe des prélèvements et des antibiogrammes, pas directement des infections",
    items: [
      "un prélèvement ;",
      "une date de prélèvement ;",
      "un site ou type de prélèvement ;",
      "une bactérie identifiée ;",
      "un antibiogramme ;",
      "parfois un phénotype de résistance."
    ],
  }),
  textSlide({
    kicker: "UNITÉ DE SURVEILLANCE",
    title: "L'infection clinique ne se superpose pas aux observations microbiologiques",
    body: "En pratique clinique, on raisonne souvent en infection : pneumonie, bactériémie, infection urinaire, infection de site opératoire.",
    items: [
      "le lien prélèvement-infection n'est pas directement codé ;",
      "le début et la fin d'un épisode infectieux sont difficiles à reconstruire automatiquement ;",
      "une même infection peut donner plusieurs prélèvements positifs ;",
      "plusieurs isolats chez un même patient peuvent être microbiologiquement différents."
    ],
  }),
  textSlide({
    kicker: "SOUCHE",
    title: "SPARES définit une unité de comptage microbiologique : la souche",
    items: [
      "un isolat bactérien d'une espèce donnée, chez un patient donné ;",
      "caractérisé par un antibiotype ;",
      "l'antibiotype correspond au profil de sensibilité aux antibiotiques testés ;",
      "deux isolats sont différents si leur antibiotype présente une différence majeure ;",
      "différence majeure : opposition S ou SFP versus R pour au moins une molécule."
    ],
  }),
  textSlide({
    kicker: "DÉDOUBLONNAGE",
    title: "Le dédoublonnage évite de compter plusieurs fois une même souche",
    items: [
      "sans différence majeure d'antibiotype, deux isolats de même espèce chez un même patient sont considérés comme doublons ;",
      "si le nombre d'antibiotiques testés est identique, SPARES retient le prélèvement le plus ancien ;",
      "si le nombre d'antibiotiques testés diffère, SPARES retient le prélèvement avec le plus grand nombre d'antibiotiques testés ;",
      "les résultats absents ne sont pas des caractères discriminants."
    ],
  }),
  `
  base(slide, ctx, "COMPTAGE");
  heading(slide, ctx, "Analyse globale et analyse par type ne sont pas deux affichages d'un même dédoublonnage");
  ctx.addText(slide, { x: 82, y: 142, w: 1090, h: 54, text: "SPARES définit deux règles de comptage selon la question posée.", fontSize: 25, color: T.ink });
  const rows = [
    ["Patient", "Prélèvement", "Antibiotype"],
    ["A", "Hémoculture", "S-S-S"],
    ["A", "Urines", "S-S-S"]
  ];
  table(slide, ctx, 116, 238, 470, rows);
  callout(slide, ctx, 660, 210, 430, 100, "Analyse globale : un seul isolat est retenu, quel que soit le type de prélèvement.");
  callout(slide, ctx, 660, 344, 430, 118, "Analyse par type : les deux isolats peuvent être retenus, l'un pour les urines, l'autre pour les hémocultures.");
  ctx.addText(slide, { x: 92, y: 610, w: 920, h: 24, text: "Source : Méthodologie SPARES 2025, p. 16/31.", fontSize: 13, color: T.muted });
`,
  textSlide({
    kicker: "STRATIFICATION",
    title: "Une stratification peut être un axe de restitution ou une règle de comptage",
    body: "L'exemple du type de prélèvement montre un point méthodologique plus général.",
    items: [
      "option 1 : dédoublonner d'abord, puis décrire les souches selon une variable ;",
      "option 2 : définir d'abord les strates, puis dédoublonner séparément dans chaque strate ;",
      "ce choix méthodologique concerne notamment le trimestre, le site de prélèvement, le service ou l'établissement ;",
      "le choix peut changer les souches retenues, les numérateurs et parfois les dénominateurs."
    ],
  }),
  textSlide({
    kicker: "INDICATEURS",
    title: "Une fois la règle de comptage définie, les indicateurs répondent à deux questions",
    items: [
      "proportion de résistance : parmi les souches retenues et testées, quelle part est résistante ?",
      "densité d'incidence : combien de souches résistantes sont observées rapportées à l'activité hospitalière surveillée ?",
      "le numérateur dépend du périmètre, du type de prélèvement, de l'antibiotype, du dédoublonnage et de la stratification ;",
      "pour l'incidence, le dénominateur d'activité hospitalière doit être construit sur le même périmètre."
    ],
  }),
  textSlide({
    kicker: "TRADUCTION",
    title: "Appliquer SPARES aux données de l'entrepôt suppose de comprendre comment les données locales sont produites",
    items: [
      "comment les prélèvements sont prescrits, réalisés et libellés ;",
      "comment les antibiogrammes sont rendus, corrigés ou complétés ;",
      "comment les unités hospitalières sont organisées ;",
      "quels choix biologiques ou organisationnels influencent les données sans être explicitement codés."
    ],
    note: "ORCHIDEE aligne pratiques réelles, données disponibles et définitions de surveillance.",
  }),
  textSlide({
    kicker: "ALIGNEMENTS",
    title: "Le travail d'alignement porte sur les objets qui déterminent les indicateurs",
    items: [
      "bactéries, antibiotiques et familles d'antibiotiques ;",
      "phénotypes d'intérêt, notamment BLSE et carbapénémase ;",
      "types de prélèvements ;",
      "unités fonctionnelles et périmètre SPARES via TA/DE ;",
      "séjours et activité hospitalière utilisée comme dénominateur ;",
      "règles de dédoublonnage et de comptage."
    ],
  }),
  textSlide({
    kicker: "RÉSULTATS",
    title: "ORCHIDEE produit déjà un noyau annuel d'indicateurs RATB",
    items: [
      "proportions annuelles de résistance ;",
      "densités d'incidence globales ;",
      "résultats globaux et par type de prélèvement pour les proportions ;",
      "indicateurs phénotypiques BLSE et carbapénémase ;",
      "numérateurs et dénominateurs associés ;",
      "choix méthodologiques documentés et sorties reproductibles."
    ],
  }),
  imageSlide({
    kicker: "RÉSULTATS",
    title: "Exemple de sortie globale : proportions de résistance",
    image: imageAssets.global,
    message: "La vue globale suit, pour une espèce donnée, les résistances par molécules ou familles après application du périmètre et du dédoublonnage global.",
    source: "Source : orchidee_ratb_indicators.html",
  }),
  imageSlide({
    kicker: "RÉSULTATS",
    title: "Exemple de sortie par type de prélèvement",
    image: imageAssets.byType,
    message: "La vue par type ne correspond pas à un simple filtre de la vue globale : elle repose sur une règle de comptage propre.",
    source: "Source : orchidee_ratb_indicators.html",
  }),
  imageSlide({
    kicker: "RÉSULTATS",
    title: "Exemple de sortie d'incidence globale",
    image: imageAssets.incidence,
    message: "L'incidence ajoute un dénominateur d'activité hospitalière construit sur le même périmètre que les souches retenues.",
    source: "Source : orchidee_ratb_indicators.html",
  }),
  imageSlide({
    kicker: "PHÉNOTYPES",
    title: "Les phénotypes nécessitent une interprétation dédiée",
    image: imageAssets.pheno,
    message: "BLSE et carbapénémase ne sont pas toujours portées comme de simples résultats S/I/R : l'information doit être rapprochée puis stabilisée avant publication.",
    source: "Source : orchidee_ratb_indicators.html",
  }),
  comparisonSlide(),
  textSlide({
    kicker: "COMPARAISON",
    title: "La comparaison avec CONSORES n'est pas un gold standard direct",
    items: [
      "les écarts peuvent venir du périmètre hospitalier ;",
      "du périmètre microbiologique ;",
      "des corrections effectuées avant dépôt ;",
      "du dédoublonnage ;",
      "des définitions de familles ou de molécules ;",
      "ou des dénominateurs utilisés."
    ],
  }),
  textSlide({
    kicker: "DISCUSSION",
    title: "Plusieurs points méthodologiques doivent encore être stabilisés",
    items: [
      "exclusion fiable des prélèvements de dépistage ;",
      "statut de la complétion des antibiogrammes ;",
      "stratifications : restitution ou maille de comptage ;",
      "définition opérationnelle de l'infection ;",
      "service, établissement et département ;",
      "règles de petits effectifs et valeurs manquantes."
    ],
  }),
  finalSlide(),
];

const shared = `
const T = ${JSON.stringify(theme, null, 2)};

function base(slide, ctx, kicker) {
  ctx.addShape(slide, { x: 0, y: 0, w: 1280, h: 720, fill: T.bg, line: ctx.line("transparent", 0) });
  ctx.addShape(slide, { x: 0, y: 0, w: 1280, h: 8, fill: T.accent, line: ctx.line("transparent", 0) });
  ctx.addText(slide, { x: 74, y: 38, w: 300, h: 24, text: kicker, fontSize: 12, bold: true, color: T.accent, typeface: T.body });
  ctx.addText(slide, { x: 1110, y: 650, w: 80, h: 20, text: String(ctx.slideNumber).padStart(2, "0"), fontSize: 12, color: T.muted, align: "right" });
}

function heading(slide, ctx, title) {
  ctx.addText(slide, { x: 74, y: 72, w: 1080, h: 70, text: title, fontSize: 34, bold: true, color: T.ink, typeface: T.title });
}

function panel(slide, ctx, x, y, w, h, title, body) {
  ctx.addShape(slide, { x, y, w, h, fill: T.white, line: ctx.line(T.line, 1) });
  ctx.addShape(slide, { x, y, w, h: 8, fill: T.accent, line: ctx.line("transparent", 0) });
  ctx.addText(slide, { x: x + 28, y: y + 28, w: w - 56, h: 38, text: title, fontSize: 24, bold: true, color: T.ink });
  ctx.addText(slide, { x: x + 42, y: y + 92, w: w - 80, h: h - 120, text: body, fontSize: 22, color: T.ink });
}

function callout(slide, ctx, x, y, w, h, text) {
  ctx.addShape(slide, { x, y, w, h, fill: T.pale, line: ctx.line("transparent", 0) });
  ctx.addText(slide, { x: x + 22, y: y + 20, w: w - 44, h: h - 34, text, fontSize: 22, color: T.ink });
}

function table(slide, ctx, x, y, w, rows) {
  const rowH = 48;
  const colW = w / rows[0].length;
  rows.forEach((row, r) => {
    row.forEach((cell, c) => {
      const fill = r === 0 ? T.dark : T.white;
      const color = r === 0 ? T.white : T.ink;
      ctx.addShape(slide, { x: x + c * colW, y: y + r * rowH, w: colW, h: rowH, fill, line: ctx.line(T.line, 1) });
      ctx.addText(slide, { x: x + c * colW + 12, y: y + r * rowH + 12, w: colW - 24, h: rowH - 12, text: cell, fontSize: 18, bold: r === 0, color });
    });
  });
}
`;

async function writeSlideModules() {
  await fs.rm(WORKSPACE, { recursive: true, force: true });
  await fs.mkdir(SLIDES_DIR, { recursive: true });
  await fs.mkdir(PREVIEW_DIR, { recursive: true });
  await fs.mkdir(LAYOUT_DIR, { recursive: true });
  await fs.mkdir(ASSET_DIR, { recursive: true });
  await fs.mkdir(OUTPUT_DIR, { recursive: true });

  await fs.writeFile(path.join(WORKSPACE, "profile-plan.txt"), [
    "task mode: create",
    "primary profile: strategy-leadership",
    "secondary gates: medical methods clarity; local report images are generated report artifacts",
    "known missing inputs: exact rendered result slide preference can be refined after first review"
  ].join("\\n"));
  await fs.writeFile(path.join(WORKSPACE, "source-notes.txt"), [
    "Narrative source: pasted outline supplied by user.",
    "Report images: local ORCHIDEE report exports under downloads/, generated by orchidee_ratb_indicators.html.",
    "External source cited in deck: Méthodologie SPARES 2025, p. 16/31, as provided by user."
  ].join("\\n"));

  for (let i = 0; i < slides.length; i += 1) {
    const n = String(i + 1).padStart(2, "0");
    const body = slides[i];
    const module = `
${shared}

export async function slide${n}(presentation, ctx) {
  const slide = presentation.slides.add();
${body}
  return slide;
}
`;
    await fs.writeFile(path.join(SLIDES_DIR, `slide-${n}.mjs`), module, "utf8");
  }
}

async function buildDeck() {
  const script = path.join(SKILL_DIR, "scripts", "build_artifact_deck.mjs");
  const result = spawnSync("node", [
    script,
    "--workspace", WORKSPACE,
    "--slides-dir", SLIDES_DIR,
    "--out", FINAL_PPTX,
    "--preview-dir", PREVIEW_DIR,
    "--layout-dir", path.join(LAYOUT_DIR, "final"),
    "--contact-sheet", path.join(PREVIEW_DIR, "contact-sheet.png"),
    "--slide-count", String(slides.length),
  ], {
    encoding: "utf8",
    stdio: "pipe",
    env: { ...process.env, HOME: process.env.HOME || "C:/Users/franc" },
  });
  if (result.status !== 0) {
    console.error(result.stdout || "");
    console.error(result.stderr || result.error?.message || "");
    process.exit(result.status || 1);
  }
  console.log(result.stdout);
  console.log(FINAL_PPTX);
}

await writeSlideModules();
if (!process.argv.includes("--write-only")) {
  await buildDeck();
}
