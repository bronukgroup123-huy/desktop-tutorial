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
  // 1. Білий гриб (Boletus edulis)
  "boletus-edulis": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="12" ry="4" fill="rgba(0,0,0,0.1)" />
      <path id="stem" d="M24 40 Q20 55 26 58 L38 58 Q44 55 40 40 Z" fill="#FFF8DC" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M26 46 Q32 50 38 46 M25 50 Q32 54 39 50" stroke="#D2B48C" stroke-width="1.5" fill="none" />
      <path id="cap" d="M10 32 C10 15 54 15 54 32 C54 38 44 42 32 42 C20 42 10 38 10 32 Z" fill="#8B4513" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M18 24 Q32 16 46 24" stroke="rgba(255,255,255,0.3)" stroke-width="3" fill="none" stroke-linecap="round"/>
    </svg>`,

  // 2. Лисичка (Cantharellus cibarius)
  "cantharellus-cibarius": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="10" ry="4" fill="rgba(0,0,0,0.1)" />
      <path id="body" d="M12 28 C8 14 56 14 52 28 C50 36 42 42 40 50 L40 58 L24 58 L24 50 C22 42 14 36 12 28 Z" fill="#FFD700" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M24 50 Q32 54 40 50 M22 44 Q32 48 42 44 M20 38 Q32 42 44 38" stroke="#DAA520" stroke-width="2.5" fill="none" stroke-linecap="round"/>
      <path d="M12 28 Q16 32 20 28 Q24 32 28 28 Q32 32 36 28 Q40 32 44 28 Q48 32 52 28" stroke="#333" stroke-width="2" fill="none" />
    </svg>`,

  // 3. Підберезник (Leccinum scabrum)
  "leccinum-scabrum": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="12" ry="4" fill="rgba(0,0,0,0.1)" />
      <path id="stem" d="M25 40 Q22 55 26 58 L38 58 Q42 55 39 40 Z" fill="#D3D3D3" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <circle cx="28" cy="45" r="2" fill="#333" /><circle cx="35" cy="48" r="2" fill="#333" /><circle cx="27" cy="52" r="2" fill="#333" /><circle cx="36" cy="54" r="2" fill="#333" />
      <path id="cap" d="M12 32 C12 20 52 20 52 32 C52 38 42 42 32 42 C22 42 12 38 12 32 Z" fill="#8B7355" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
    </svg>`,

  // 4. Підосичник (Leccinum aurantiacum)
  "leccinum-aurantiacum": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="12" ry="4" fill="rgba(0,0,0,0.1)" />
      <path id="stem" d="M25 40 Q22 55 26 58 L38 58 Q42 55 39 40 Z" fill="#FFFFFF" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <circle cx="28" cy="45" r="2" fill="#333" /><circle cx="35" cy="48" r="2" fill="#333" /><circle cx="27" cy="52" r="2" fill="#333" /><circle cx="36" cy="54" r="2" fill="#333" />
      <path id="cap" d="M10 32 C10 18 54 18 54 32 C54 38 44 42 32 42 C20 42 10 38 10 32 Z" fill="#FF4500" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
    </svg>`,

  // 5. Маслюк (Suillus luteus)
  "suillus-luteus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="10" ry="4" fill="rgba(0,0,0,0.1)" />
      <path id="stem" d="M26 38 Q26 55 28 58 L36 58 Q38 55 38 38 Z" fill="#FFD700" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path id="ring" d="M20 44 Q32 50 44 44 Q38 40 32 40 Q26 40 20 44 Z" fill="#FFFFFF" stroke="#333" stroke-width="2" stroke-linejoin="round"/>
      <path id="cap" d="M14 32 C14 18 50 18 50 32 C50 36 42 40 32 40 C22 40 14 36 14 32 Z" fill="#8B4513" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M22 24 Q32 20 42 24" stroke="#FFFFFF" stroke-width="2.5" fill="none" opacity="0.6" stroke-linecap="round"/>
    </svg>`,

  // 6. Опеньок осінній (Armillaria mellea) - СІМЕЙСТВО
  "armillaria-mellea": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="16" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M18 56 L46 56 L42 61 L22 61 Z" fill="#5C4033" stroke="#333" stroke-width="2" />
      <g id="small-mushroom">
        <path d="M38 38 L36 56 L44 56 L42 38 Z" fill="#FFF8DC" stroke="#333" stroke-width="2" />
        <path d="M34 42 Q40 46 46 42 Q42 40 40 40 Q38 40 34 42 Z" fill="#FFF" stroke="#333" stroke-width="1.5" />
        <path id="small-cap" d="M32 34 C32 24 50 24 50 34 C50 38 42 40 40 40 C36 40 32 38 32 34 Z" fill="#DAA520" stroke="#333" stroke-width="2" />
        <circle cx="40" cy="30" r="1.5" fill="#8B6508" />
      </g>
      <g id="large-mushroom">
        <path d="M26 34 L24 56 L34 56 L32 34 Z" fill="#FFF8DC" stroke="#333" stroke-width="2.5" />
        <path d="M20 40 Q28 46 36 40 Q32 38 28 38 Q24 38 20 40 Z" fill="#FFF" stroke="#333" stroke-width="2" />
        <path id="large-cap" d="M14 28 C14 16 44 16 44 28 C44 34 36 38 28 38 C20 38 14 34 14 28 Z" fill="#DAA520" stroke="#333" stroke-width="2.5" />
        <circle cx="28" cy="24" r="2" fill="#8B6508" /><circle cx="22" cy="26" r="1.5" fill="#8B6508" /><circle cx="34" cy="26" r="1.5" fill="#8B6508" />
      </g>
    </svg>`,

  // 7. Рижик (Lactarius deliciosus)
  "lactarius-deliciosus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="9" ry="4" fill="rgba(0,0,0,0.1)" />
      <path id="stem" d="M27 38 Q26 52 28 58 L36 58 Q38 52 37 38 Z" fill="#FF8C00" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path id="cap" d="M12 28 C12 16 52 16 52 28 C52 36 42 40 32 40 C22 40 12 36 12 28 Z" fill="#FF8C00" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <ellipse cx="32" cy="26" rx="8" ry="3" fill="#A0522D" opacity="0.6" stroke="#333" stroke-width="1.5" />
    </svg>`,

  // 8. Груздь (Lactarius resimus)
  "lactarius-resimus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="12" ry="4" fill="rgba(0,0,0,0.1)" />
      <path id="stem" d="M25 38 Q22 55 26 58 L38 58 Q42 55 39 38 Z" fill="#FFFFFF" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path id="cap" d="M12 32 C12 18 52 18 52 32 C52 38 46 42 32 42 C18 42 12 38 12 32 Z" fill="#FDF5E6" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <ellipse cx="32" cy="30" rx="14" ry="6" fill="none" stroke="#D3D3D3" stroke-width="2" />
      <ellipse cx="32" cy="30" rx="8" ry="3" fill="none" stroke="#D3D3D3" stroke-width="2" />
    </svg>`,

  // 9. Сироїжка (Russula spp.)
  "russula-spp": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="8" ry="4" fill="rgba(0,0,0,0.1)" />
      <path id="stem" d="M27 38 L26 58 L38 58 L37 38 Z" fill="#FFFFFF" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path id="cap" d="M14 34 C14 20 50 20 50 34 C50 38 42 40 32 40 C22 40 14 38 14 34 Z" fill="#9370DB" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
    </svg>`,

  // 10. Печериця (Agaricus campestris)
  "agaricus-campestris": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="9" ry="4" fill="rgba(0,0,0,0.1)" />
      <path id="stem" d="M27 38 L25 58 L39 58 L37 38 Z" fill="#FFFFFF" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path id="ring" d="M22 44 Q32 48 42 44 Q38 42 32 42 Q26 42 22 44 Z" fill="#FFFFFF" stroke="#333" stroke-width="2" stroke-linejoin="round"/>
      <path d="M18 36 L46 36" stroke="#FFB6C1" stroke-width="3" />
      <path id="cap" d="M14 36 C14 20 50 20 50 36 C50 38 42 40 32 40 C22 40 14 38 14 36 Z" fill="#FFFFFF" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
    </svg>`,

  // 11. Сморчок (Morchella spp.)
  "morchella-spp": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="8" ry="4" fill="rgba(0,0,0,0.1)" />
      <path id="stem" d="M28 40 L26 58 L38 58 L36 40 Z" fill="#FFF8DC" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path id="cap" d="M22 40 C22 20 42 20 42 40 C42 42 38 44 32 44 C26 44 22 42 22 40 Z" fill="#D2B48C" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M26 36 L32 32 L38 36 L32 40 Z M24 30 L30 26 L36 30 L30 34 Z M28 24 L32 20 L36 24 L32 28 Z" stroke="#5C4033" stroke-width="2" fill="none" stroke-linejoin="round"/>
    </svg>`,

  // 12. Дощовик (Lycoperdon spp.)
  "lycoperdon-spp": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="10" ry="4" fill="rgba(0,0,0,0.1)" />
      <path id="body" d="M22 40 C22 18 42 18 42 40 C42 52 38 58 32 58 C26 58 22 52 22 40 Z" fill="#FFFFFF" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <circle cx="28" cy="28" r="2" fill="#A9A9A9" /><circle cx="36" cy="30" r="2" fill="#A9A9A9" /><circle cx="32" cy="22" r="2" fill="#A9A9A9" />
      <circle cx="24" cy="36" r="2" fill="#A9A9A9" /><circle cx="40" cy="38" r="2" fill="#A9A9A9" /><circle cx="28" cy="44" r="2" fill="#A9A9A9" />
      <circle cx="36" cy="46" r="2" fill="#A9A9A9" /><circle cx="32" cy="52" r="2" fill="#A9A9A9" />
    </svg>`,

  // 13. Дубовик (Boletus luridus)
  "boletus-luridus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="11" ry="4" fill="rgba(0,0,0,0.1)" />
      <path id="stem" d="M26 40 Q24 55 28 58 L36 58 Q40 55 38 40 Z" fill="#FFD700" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M26 44 L38 44 M27 48 L37 48 M28 52 L36 52 M28 46 L32 42 M36 46 L32 42 M28 50 L32 46 M36 50 L32 46" stroke="#FF0000" stroke-width="2" stroke-linecap="round" />
      <path id="cap" d="M12 34 C12 22 52 22 52 34 C52 40 42 44 32 44 C22 44 12 40 12 34 Z" fill="#808000" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M16 36 L48 36" stroke="#FF0000" stroke-width="2" opacity="0.5" />
    </svg>`,

  // 14. Моховик зелений (Xerocomus subtomentosus)
  "xerocomus-spp": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="10" ry="4" fill="rgba(0,0,0,0.1)" />
      <path id="stem" d="M26 40 Q24 55 28 58 L36 58 Q40 55 38 40 Z" fill="#DAA520" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <circle cx="29" cy="46" r="1.5" fill="#8B4513" /><circle cx="35" cy="50" r="1.5" fill="#8B4513" /><circle cx="30" cy="54" r="1.5" fill="#8B4513" />
      <path id="cap" d="M12 34 C12 24 52 24 52 34 C52 40 42 42 32 42 C22 42 12 40 12 34 Z" fill="#6B8E23" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M20 28 Q32 26 44 28" stroke="#556B2F" stroke-width="1.5" fill="none" opacity="0.6" />
      <path d="M18 32 Q32 30 46 32" stroke="#556B2F" stroke-width="1.5" fill="none" opacity="0.6" />
    </svg>`,

  // 15. Вовнянка рожева (Lactarius torminosus)
  "lactarius-torminosus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="10" ry="3" fill="rgba(0,0,0,0.1)" />
      <path id="stem" d="M26 40 Q24 55 28 58 L36 58 Q40 55 38 40 Z" fill="#FFB6C1" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path id="cap" d="M12 28 C12 16 52 16 52 28 C52 36 42 42 32 42 C22 42 12 36 12 28 Z" fill="#FFC0CB" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <ellipse cx="32" cy="28" rx="14" ry="6" fill="none" stroke="#FF69B4" stroke-width="1.5" opacity="0.6"/>
      <ellipse cx="32" cy="28" rx="8" ry="3" fill="none" stroke="#FF69B4" stroke-width="1.5" opacity="0.6"/>
      <path d="M14 28 L12 30 M18 30 L16 33 M22 33 L20 36 M26 35 L25 38 M38 35 L39 38 M42 33 L44 36 M46 30 L48 33 M50 28 L52 30" stroke="#FF69B4" stroke-width="1.5" fill="none" stroke-linecap="round" />
    </svg>`,

  // 16. Глива (Pleurotus ostreatus) - СІМЕЙСТВО
  "pleurotus-ostreatus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="16" ry="4" fill="rgba(0,0,0,0.1)" />
      <rect x="8" y="50" width="48" height="10" rx="4" fill="#5C4033" stroke="#333" stroke-width="2.5" />
      <path id="cap1" d="M8 38 C 8 18, 42 20, 40 38 C 38 46, 24 46, 18 44 C 12 42, 8 38, 8 38 Z" fill="#9E9E9E" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M14 40 Q22 46 30 42 M16 36 Q24 42 32 38" stroke="#696969" stroke-width="2" fill="none" stroke-linecap="round"/>
      <path id="cap2" d="M32 46 C 32 36, 52 36, 52 46 C 52 50, 44 52, 40 50 C 36 48, 32 46, 32 46 Z" fill="#BDBDBD" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M36 48 Q42 50 46 48" stroke="#696969" stroke-width="2" fill="none" stroke-linecap="round"/>
    </svg>`,

  // 17. Їжовик (Hydnum repandum)
  "hydnum-repandum": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="10" ry="3" fill="rgba(0,0,0,0.1)" />
      <path id="stem" d="M28 40 Q26 55 30 58 L38 58 Q42 55 38 40 Z" fill="#F5DEB3" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path id="cap" d="M10 34 C12 22 24 18 32 22 C40 18 52 22 54 34 C54 42 44 44 32 44 C20 44 10 42 10 34 Z" fill="#F4A460" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M16 38 L16 46 M20 40 L20 48 M24 41 L24 49 M28 42 L28 50 M32 42 L32 50 M36 42 L36 50 M40 41 L40 49 M44 40 L44 48 M48 38 L48 46" stroke="#D2691E" stroke-width="2" stroke-linecap="round" />
    </svg>`,

  // 18. Козляк (Suillus bovinus)
  "suillus-bovinus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="8" ry="4" fill="rgba(0,0,0,0.1)" />
      <path id="stem" d="M28 38 Q26 55 28 58 L36 58 Q38 55 36 38 Z" fill="#D2B48C" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path id="cap" d="M16 32 C16 22 48 22 48 32 C48 36 42 40 32 40 C22 40 16 36 16 32 Z" fill="#D2B48C" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
    </svg>`,

  // 19. Зимовий опеньок (Flammulina velutipes) - СІМЕЙСТВО
  "flammulina-velutipes": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="16" ry="4" fill="rgba(0,0,0,0.1)" />
      <path d="M20 56 L44 56 L40 61 L24 61 Z" fill="#5C4033" stroke="#333" stroke-width="2" />
      <g id="small-mushroom">
        <path d="M40 40 L38 56 L44 56 L42 40 Z" fill="#4A2F24" stroke="#333" stroke-width="1.5" />
        <path id="small-cap" d="M32 36 C32 26 54 26 54 36 C54 40 44 42 40 40 C36 38 32 38 32 36 Z" fill="#FFA500" stroke="#333" stroke-width="2" />
      </g>
      <g id="large-mushroom">
        <path d="M28 36 L26 56 L34 56 L32 36 Z" fill="#4A2F24" stroke="#333" stroke-width="2" />
        <path id="large-cap" d="M14 32 C14 20 46 20 46 32 C46 36 36 40 30 38 C24 36 14 36 14 32 Z" fill="#FFA500" stroke="#333" stroke-width="2.5" />
        <path d="M22 26 Q30 22 38 26" stroke="#FFF" stroke-width="2" fill="none" opacity="0.4" stroke-linecap="round"/>
      </g>
    </svg>`,

  // 20. Польський гриб (Imleria badia)
  "imleria-badia": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="58" rx="10" ry="4" fill="rgba(0,0,0,0.1)" />
      <path id="stem" d="M26 40 Q24 55 28 58 L36 58 Q40 55 38 40 Z" fill="#8B4513" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
      <path id="cap" d="M12 34 C12 22 52 22 52 34 C52 40 42 42 32 42 C22 42 12 40 12 34 Z" fill="#5C4033" stroke="#333" stroke-width="2.5" stroke-linejoin="round"/>
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
