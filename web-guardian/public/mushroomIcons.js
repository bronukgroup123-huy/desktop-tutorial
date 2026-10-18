/**
 * mushroomIcons.js
 * Кастомні SVG-іконки для видів грибів, що мають фото (has_photo: true).
 * viewBox="0 0 64 64" для всіх іконок.
 * Експортує функцію getMushroomIconHtml(speciesId, size = 32),
 * яка повертає HTML-рядок <span>...</span> для використання у vanilla-JS коді (landing.html).
 *
 * Підхід: 20 деталізованих SVG-шаблонів з товстими чіткими контурами (stroke="#333", stroke-width="2.5"),
 * які 100% відповідають ботанічним описам з mushroom_descriptions.js.
 */

const SPECIES_WITH_PHOTO = new Set([
  "boletus_edulis","lactarius_torminosus","pleurotus_ostreatus","lactarius_resimus","lycoperdon_perlatum",
  "boletus_luridus","flammulina_velutipes","hydnum_repandum","suillus_bovinus","cantharellus_cibarius",
  "suillus_luteus","xerocomus_subtomentosus","armillaria_mellea","agaricus_campestris","leccinum_scabrum",
  "leccinum_aurantiacum","imleria_badia","lactarius_deliciosus","russula_vesca","morchella_esculenta",
  "albatrellus_confluens","albatrellus_ovinus","boletus_reticulatus","boletus_pinophilus","pleurotus_dryinus",
  "pleurotus_pulmonarius","macrolepiota_procera","macrolepiota_mastoidea","tricholoma_equestre","hydnum_rufescens",
  "hydnum_umbilicatum","clavulina_coralloides","cantharellus_amethysteus","craterellus_lutescens","craterellus_cinereus",
  "craterellus_tubaeformis","cantharellus_friesii","suillus_placidus","suillus_variegatus","suillus_granulatus",
  "suillus_grevillei","xerocomellus_chrysenteron","amanita_excelsa","amanita_rubescens","amanita_crocea",
  "kuehneromyces_mutabilis","armillaria_ostoyae","leccinellum_pseudoscabrum","leccinum_versipelle","leccinum_variicolor",
  "leccinum_duriusculum","russula_delica","leccinum_albostipitatum","amanita_fulva","amanita_vaginata",
  "ramaria_botrytis","lactarius_deterrimus","lactarius_salmonicolor","tricholoma_terreum","lepista_personata",
  "calocybe_gambosa","tricholoma_portentosum","lepista_nuda","russula_xerampelina","russula_virescens",
  "russula_cyanoxantha","russula_foetens","lactarius_vellereus","polyporus_squamosus","laetiporus_sulphureus",
  "lactarius_quietus","lactifluus_volemus","lactarius_piperatus","lactarius_subdulcis","boletus_aereus",
  "rubroboletus_lupinus","butyriboletus_appendiculatus","butyriboletus_regius","butyriboletus_subappendiculatus",
  "butyriboletus_fuscoroseus","rubroboletus_rhodoxanthus","rubroboletus_satanas","butyriboletus_fechtneri",
  "rubroboletus_rubrosanguineus","phallus_duplicatus","hemileccinum_depilatum","hericium_erinaceus","hericium_coralloides",
  "hygrocybe_calyptriformis","gomphus_clavatus","grifola_frondosa","morchella_steppicola","pseudocolus_fusiformis",
  "catathelasma_imperiale","anthurus_archeri","clavariadelphus_pistillaris","lyophyllum_favrei","helvella_monachella",
  "suillus_plorans","myriostoma_coliforme","boletus_parasiticus","amanita_caesarea","amanita_strobiliformis",
  "chalciporus_rubinus","clathrus_ruber","tricholoma_colossus","tricholoma_focale","sarcosoma_globosum",
  "russula_turci","scleroderma_geaster","sparassis_crispa","polyporus_umbellatus","tuber_aestivum",
  "phellorinia_herculeana","phaeolepiota_aurea","phylloporus_pelletieri","lactarius_lignyotus","strobilomyces_strobilaceus",
  "amanita_muscaria","amanita_pantherina","amanita_phalloides","amanita_verna","amanita_virosa",
  "clitocybe_candicans","clitocybe_dealbata","entoloma_sinuatum","galerina_marginata","gyromitra_esculenta",
  "hygrophoropsis_aurantiaca","inocybe_erubescens","inocybe_geophylla","paxillus_involutus",
]);

// Alias map: forecast sticker IDs → actual species IDs in SPECIES_WITH_PHOTO
const SPECIES_ALIASES = {
  "morchella_spp": "morchella_esculenta",
  "lycoperdon_spp": "lycoperdon_perlatum",
  "xerocomus_spp": "xerocomus_subtomentosus",
};

// ---------------------------------------------------------------------------
// 20 ДЕТАЛІЗОВАНИХ SVG-ІКОНОК (ТОК-20)
// Ключі — у дефісному форматі (як у DETAILED_SVGS)
// ---------------------------------------------------------------------------
const DETAILED_SVGS = {
  // 1. Білий гриб (Боровик) - коричнева шапка, товста біла ніжка, БЕЗ кільця
  "boletus-edulis": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="14" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M24 40 Q20 55 26 58 L38 58 Q44 55 40 40 Z" fill="#FFF8DC" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M26 46 Q32 50 38 46 M25 50 Q32 54 39 50 M27 42 Q32 45 37 42" stroke="#D2B48C" stroke-width="1.5" fill="none" />
      <path d="M10 32 C10 15 54 15 54 32 C54 38 44 42 32 42 C20 42 10 38 10 32 Z" fill="#8B4513" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M18 24 Q32 16 46 24" stroke="rgba(255,255,255,0.3)" stroke-width="3" fill="none" stroke-linecap="round"/>
    </svg>`,

  // 2. Лисичка - жовта, лійкоподібна, хвилястий край, БЕЗ кільця
  "cantharellus-cibarius": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="10" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M14 28 C10 16 54 16 50 28 C48 34 40 40 38 48 L38 56 L26 56 L26 48 C24 40 16 34 14 28 Z" fill="#FFD700" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M26 48 Q32 52 38 48" stroke="#B8860B" stroke-width="2.5" fill="none" />
      <path d="M14 28 Q18 32 22 28 Q26 32 32 28 Q38 32 42 28 Q46 32 50 28" stroke="#B8860B" stroke-width="2" fill="none" />
    </svg>`,

  // 3. Підберезник - коричнева шапка, сіра ніжка з ЧОРНИМИ ЛУСОЧКАМИ, БЕЗ кільця
  "leccinum-scabrum": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="12" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M25 40 Q22 55 26 58 L38 58 Q42 55 39 40 Z" fill="#D3D3D3" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <circle cx="28" cy="45" r="2" fill="#333" /><circle cx="35" cy="48" r="2" fill="#333" /><circle cx="27" cy="52" r="2" fill="#333" /><circle cx="36" cy="54" r="2" fill="#333" />
      <path d="M12 32 C12 20 52 20 52 32 C52 38 42 42 32 42 C22 42 12 38 12 32 Z" fill="#8B7355" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
    </svg>`,

  // 4. Підосичник - яскраво-червона шапка, біла ніжка з ЛУСОЧКАМИ
  "leccinum-aurantiacum": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="12" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M25 40 Q22 55 26 58 L38 58 Q42 55 39 40 Z" fill="#FFFFFF" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <circle cx="28" cy="45" r="2" fill="#333" /><circle cx="35" cy="48" r="2" fill="#333" /><circle cx="27" cy="52" r="2" fill="#333" /><circle cx="36" cy="54" r="2" fill="#333" />
      <path d="M10 32 C10 18 54 18 54 32 C54 38 44 42 32 42 C20 42 10 38 10 32 Z" fill="#FF4500" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
    </svg>`,

  // 5. Маслюк - коричнева слизька шапка, жовта ніжка, Є КІЛЬЦЕ
  "suillus-luteus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="10" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M26 38 Q26 55 28 58 L36 58 Q38 55 38 38 Z" fill="#FFD700" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M20 44 Q32 50 44 44 Q38 40 32 40 Q26 40 20 44 Z" fill="#FFFFFF" stroke="#333" stroke-width="2" stroke-linejoin="round"/>
      <path d="M14 32 C14 18 50 18 50 32 C50 36 42 40 32 40 C22 40 14 36 14 32 Z" fill="#8B4513" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M22 24 Q32 20 42 24" stroke="#FFFFFF" stroke-width="2.5" fill="none" opacity="0.5" stroke-linecap="round"/>
    </svg>`,

  // 6. Опеньок осінній - медова шапка, тонка ніжка, ЧІТКЕ КІЛЬЦЕ, ЛУСОЧКИ
  "armillaria-mellea": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="8" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M28 38 L26 58 L38 58 L36 38 Z" fill="#FFF8DC" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M20 44 Q32 50 44 44 Q38 40 32 40 Q26 40 20 44 Z" fill="#FFFFFF" stroke="#333" stroke-width="2" stroke-linejoin="round"/>
      <path d="M16 32 C16 20 48 20 48 32 C48 36 40 40 32 40 C24 40 16 36 16 32 Z" fill="#DAA520" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <circle cx="32" cy="26" r="2.5" fill="#8B6508" /><circle cx="26" cy="28" r="2" fill="#8B6508" /><circle cx="38" cy="28" r="2" fill="#8B6508" />
    </svg>`,

  // 7. Рижик - оранжева лійка, БЕЗ кільця
  "lactarius-deliciosus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="9" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M27 38 Q26 52 28 58 L36 58 Q38 52 37 38 Z" fill="#FF8C00" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M12 28 C12 16 52 16 52 28 C52 36 42 40 32 40 C22 40 12 36 12 28 Z" fill="#FF8C00" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <ellipse cx="32" cy="26" rx="8" ry="3" fill="#A0522D" opacity="0.6" stroke="#333" stroke-width="1.5" />
    </svg>`,

  // 8. Груздь - БІЛА шапка (лійка), БЕЗ кільця
  "lactarius-resimus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="12" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M25 38 Q22 55 26 58 L38 58 Q42 55 39 38 Z" fill="#FFFFFF" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M12 32 C12 18 52 18 52 32 C52 38 46 42 32 42 C18 42 12 38 12 32 Z" fill="#FDF5E6" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <ellipse cx="32" cy="30" rx="14" ry="6" fill="none" stroke="#D3D3D3" stroke-width="2" />
      <ellipse cx="32" cy="30" rx="8" ry="3" fill="none" stroke="#D3D3D3" stroke-width="2" />
    </svg>`,

  // 9. Сироїжка - різнобарвна (фіолетова), крихка біла ніжка, БЕЗ кільця
  "russula-spp": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="8" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M27 38 L26 58 L38 58 L37 38 Z" fill="#FFFFFF" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M14 34 C14 20 50 20 50 34 C50 38 42 40 32 40 C22 40 14 38 14 34 Z" fill="#9370DB" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M22 28 Q32 24 42 28" stroke="#FFF" stroke-width="2" fill="none" opacity="0.6" stroke-linecap="round"/>
    </svg>`,

  // 10. Печериця - біла шапка, рожеві пластинки, Є КІЛЬЦЕ
  "agaricus-campestris": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="9" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M27 38 L25 58 L39 58 L37 38 Z" fill="#FFFFFF" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M22 44 Q32 48 42 44 Q38 42 32 42 Q26 42 22 44 Z" fill="#FFFFFF" stroke="#333" stroke-width="2" stroke-linejoin="round"/>
      <path d="M18 36 L46 36" stroke="#FFB6C1" stroke-width="3" /> <!-- Рожеві пластинки -->
      <path d="M14 36 C14 20 50 20 50 36 C50 38 42 40 32 40 C22 40 14 38 14 36 Z" fill="#FFFFFF" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
    </svg>`,

  // 11. Сморчок - зморшкувата шапка (стільники)
  "morchella-spp": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="8" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M28 40 L26 58 L38 58 L36 40 Z" fill="#FFF8DC" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M22 40 C22 20 42 20 42 40 C42 42 38 44 32 44 C26 44 22 42 22 40 Z" fill="#D2B48C" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M26 36 L38 36 M24 30 L40 30 M28 24 L36 24 M30 18 L34 18" stroke="#5C4033" stroke-width="2" fill="none" />
      <path d="M32 38 L32 22 M28 34 L28 26 M36 34 L36 26" stroke="#5C4033" stroke-width="2" fill="none" />
    </svg>`,

  // 12. Дощовик - кулястий, без ніжки, з шипиками
  "lycoperdon-spp": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="10" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M22 40 C22 20 42 20 42 40 C42 52 38 58 32 58 C26 58 22 52 22 40 Z" fill="#FFFFFF" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <circle cx="28" cy="30" r="2" fill="#333" /><circle cx="36" cy="32" r="2" fill="#333" /><circle cx="32" cy="24" r="2" fill="#333" />
      <circle cx="26" cy="38" r="2" fill="#333" /><circle cx="38" cy="42" r="2" fill="#333" /><circle cx="32" cy="46" r="2" fill="#333" />
    </svg>`,

  // 13. Дубовик - оливкова шапка, червона ніжка, БЕЗ кільця
  "boletus-luridus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="11" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M26 40 Q24 55 28 58 L36 58 Q40 55 38 40 Z" fill="#FFD700" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M26 44 L38 44 M27 48 L37 48 M28 52 L36 52" stroke="#FF0000" stroke-width="2.5" stroke-linecap="round" />
      <path d="M12 34 C12 22 52 22 52 34 C52 40 42 44 32 44 C22 44 12 40 12 34 Z" fill="#808000" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
    </svg>`,

  // 14. Моховик - оксамитова шапка, БЕЗ кільця
  "xerocomus-spp": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="10" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M26 40 Q24 55 28 58 L36 58 Q40 55 38 40 Z" fill="#DAA520" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M12 34 C12 24 52 24 52 34 C52 40 42 42 32 42 C22 42 12 40 12 34 Z" fill="#A08B5C" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
    </svg>`,

  // 15. Вовнянка - рожева, волохатий край, БЕЗ кільця
  "lactarius-torminosus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="9" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M27 38 Q26 52 28 58 L36 58 Q38 52 37 38 Z" fill="#FFB6C1" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M14 30 C14 18 50 18 50 30 C50 36 42 40 32 40 C22 40 14 36 14 30 Z" fill="#FFB6C1" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M14 30 L12 32 M17 32 L16 35 M20 34 L19 37 M24 37 L24 40 M28 38 L28 41 M36 38 L36 41 M40 37 L40 40 M44 34 L45 37 M47 32 L48 35 M50 30 L52 32" stroke="#333" stroke-width="1.5" fill="none" stroke-linecap="round" />
    </svg>`,

  // 16. Глива - віялоподібна, бічна ніжка
  "pleurotus-ostreatus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="14" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M36 46 Q46 50 48 56 L40 56 Q36 52 34 46 Z" fill="#F5F5F5" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M12 36 C12 16 46 20 44 36 C42 46 28 46 22 44 C16 42 12 36 12 36 Z" fill="#A9A9A9" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
    </svg>`,

  // 17. Їжовик - жовтувата шапка, шипики знизу
  "hydnum-repandum": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="10" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M26 38 Q24 55 28 58 L36 58 Q40 55 38 38 Z" fill="#F5DEB3" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M14 32 C14 22 50 22 50 32 C50 38 42 40 32 40 C22 40 14 38 14 32 Z" fill="#F4A460" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M18 38 L18 42 M22 39 L22 43 M26 40 L26 44 M30 40 L30 44 M34 40 L34 44 M38 39 L38 43 M42 38 L42 42" stroke="#333" stroke-width="2" fill="none" stroke-linecap="round" />
    </svg>`,

  // 18. Козляк - гладенька світло-коричнева шапка, БЕЗ кільця
  "suillus-bovinus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="8" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M28 38 Q26 55 28 58 L36 58 Q38 55 36 38 Z" fill="#D2B48C" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M16 32 C16 22 48 22 48 32 C48 36 42 40 32 40 C22 40 16 36 16 32 Z" fill="#D2B48C" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
    </svg>`,

  // 19. Зимовий опеньок - оранжева шапка, темна оксамитова ніжка, БЕЗ кільця
  "flammulina-velutipes": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="8" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M28 38 Q25 50 26 58 L38 58 Q39 50 36 38 Z" fill="#5C4033" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M16 34 C16 22 48 22 48 34 C48 38 40 40 32 40 C24 40 16 38 16 34 Z" fill="#FFA500" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
    </svg>`,

  // 20. Польський гриб - темно-коричнева шапка, БЕЗ кільця
  "imleria-badia": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="10" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M26 40 Q24 55 28 58 L36 58 Q40 55 38 40 Z" fill="#8B4513" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M12 34 C12 22 52 22 52 34 C52 40 42 42 32 42 C22 42 12 40 12 34 Z" fill="#5C4033" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
    </svg>`
};

// ---------------------------------------------------------------------------
// Допоміжні функції
// ---------------------------------------------------------------------------
function escHtml(unsafe) {
  return unsafe
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

// ---------------------------------------------------------------------------
// Fallback SVG для видів без фото / невідомих (з чітким контуром)
// ---------------------------------------------------------------------------
function fallbackSvg(title) {
  const safeTitle = escHtml(title);
  return `<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
    <ellipse cx="32" cy="58" rx="10" ry="4" fill="rgba(0,0,0,0.1)" />
    <path d="M26 38 L24 58 L40 58 L38 38 Z" fill="#E0E0E0" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
    <path d="M14 34 C14 20 50 20 50 34 C50 38 42 40 32 40 C22 40 14 38 14 34 Z" fill="#A9A9A9" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
    <title>${safeTitle}</title>
  </svg>`;
}

/**
 * Повертає HTML-рядок SVG-іконки для виду, обгорнений у <span> з фіксованими розмірами.
 * @param {string} speciesId - програмне ім'я виду (id) з підкресленнями, напр. "boletus_edulis"
 * @param {number|string} size - розмір іконки (за замовчуванням 32)
 * @returns {string} HTML-рядок <span class="mushroom-icon">...</span>
 */
function getMushroomIconHtml(speciesId, size = 32) {
  if (!speciesId) {
    return `<span class="mushroom-icon" style="display:inline-flex; align-items:center; justify-content:center; width:${size}px; height:${size}px; flex-shrink:0;">${fallbackSvg("Невідомий гриб")}</span>`;
  }

  // Resolve forecast sticker aliases (e.g. morchella_spp → morchella_esculenta)
  const resolved = SPECIES_ALIASES[speciesId] || speciesId;

  if (!SPECIES_WITH_PHOTO.has(resolved)) {
    return `<span class="mushroom-icon" style="display:inline-flex; align-items:center; justify-content:center; width:${size}px; height:${size}px; flex-shrink:0;">${fallbackSvg(resolved)}</span>`;
  }

  // Перетворюємо підкреслення на дефіс для пошуку в DETAILED_SVGS (boletus_edulis → boletus-edulis)
  const dashedKey = resolved.replace(/_/g, "-");
  let svgCode = DETAILED_SVGS[dashedKey];

  // Якщо немає деталізованої іконки — дефолтна з чітким контуром
  if (!svgCode) {
    svgCode = `
      <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
        <ellipse cx="32" cy="58" rx="10" ry="4" fill="rgba(0,0,0,0.1)" />
        <path d="M26 38 L24 58 L40 58 L38 38 Z" fill="#E0E0E0" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
        <path d="M14 34 C14 20 50 20 50 34 C50 38 42 40 32 40 C22 40 14 38 14 34 Z" fill="#A9A9A9" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      </svg>`;
  }

  return `<span class="mushroom-icon" style="display:inline-flex; align-items:center; justify-content:center; width:${size}px; height:${size}px; flex-shrink:0;">${svgCode}</span>`;
}

window.getMushroomIconHtml = getMushroomIconHtml;
