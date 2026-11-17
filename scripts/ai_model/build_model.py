"""ШІ-розпізнавач для застосунку (ADR-006, ADR-008; рішення PO 2026-11-17).

Локальна модель BioCLIP 2 (imageomics/bioclip-2, ліцензія MIT): на телефоні працює лише кодувальник
зображень (ONNX, int8), а «відбитки» видів (текстові вектори) пораховані тут заздалегідь — розпізнавання
повністю офлайн, без сервера (ADR-006).

Що робить скрипт:
  1. Завантажує BioCLIP 2 (open_clip, hf-hub).
  2. Класи — усі 326 видів каталогу (web-guardian/public/mushroom_catalog.js) + «не гриб».
     Відбиток виду — середнє текстових векторів кількох підказок: таксономія з базою
     baza200_json_*.json (царство → вид), «a photo of <латина>», опис-підказка з бази (ai_prompts.en).
  3. Експортує кодувальник зображень у ONNX і квантує ваги до int8 (≈ 300 МБ).
  4. Перевіряє точність (top-1 / top-3) fp32 і int8 на фото довідника (по 1 фото на вид із 132)
     і пише звіт docs/AI_BENCHMARK.md (план B5.0).
  5. Кладе в --out: bioclip2_vision_int8.onnx, species_text.f16 (N×D float16), labels.json, manifest.json.

Запуск (потрібні torch, open_clip_torch, onnx, onnxruntime, pillow):
  python3 scripts/ai_model/build_model.py --out dist/ai
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
CATALOG_JS = ROOT / "web-guardian/public/mushroom_catalog.js"
BAZA = next(ROOT.glob("baza200_json_*.json"))
BENCH = ROOT / "docs/AI_BENCHMARK.md"
MODEL_ID = "hf-hub:imageomics/bioclip-2"
VERSION = time.strftime("%Y.%m.%d.%H%M")  # з часом — повторна збірка в той самий день теж нова версія

# «Не гриб»: якщо найближчий клас звідси — розпізнавання каже «Не схоже на гриб» (ADR-015 §18.4).
NOT_MUSHROOM = [
    "a photo of green tree leaves", "a photo of autumn fallen leaves on the ground", "a photo of grass",
    "a photo of tree bark", "a photo of moss", "a photo of a flower", "a photo of berries",
    "a photo of a stone", "a photo of a person", "a photo of a hand", "a photo of a dog", "a photo of a cat",
    "a photo of food on a plate", "a photo of a forest landscape", "a photo of a pine cone", "a photo of a tree",
]


B = "Fungi Basidiomycota Agaricomycetes"
A = "Fungi Ascomycota Pezizomycetes Pezizales"
# Роди довідника, яких немає в базі baza200: царство, відділ, клас, порядок, родина.
EXTRA_TAXONOMY = {
    "albatrellus": f"{B} Russulales Albatrellaceae", "anthurus": f"{B} Phallales Phallaceae",
    "armillaria": f"{B} Agaricales Physalacriaceae", "butyriboletus": f"{B} Boletales Boletaceae",
    "calocybe": f"{B} Agaricales Lyophyllaceae", "cantharellus": f"{B} Cantharellales Hydnaceae",
    "catathelasma": f"{B} Agaricales Biannulariaceae", "chalciporus": f"{B} Boletales Boletaceae",
    "clathrus": f"{B} Phallales Phallaceae", "clavariadelphus": f"{B} Gomphales Clavariadelphaceae",
    "clavulina": f"{B} Cantharellales Hydnaceae", "craterellus": f"{B} Cantharellales Hydnaceae",
    "flammulina": f"{B} Agaricales Physalacriaceae", "galerina": f"{B} Agaricales Hymenogastraceae",
    "gomphus": f"{B} Gomphales Gomphaceae", "grifola": f"{B} Polyporales Grifolaceae",
    "gyromitra": f"{A} Discinaceae", "helvella": f"{A} Helvellaceae",
    "hemileccinum": f"{B} Boletales Boletaceae", "hericium": f"{B} Russulales Hericiaceae",
    "hydnum": f"{B} Cantharellales Hydnaceae", "hygrocybe": f"{B} Agaricales Hygrophoraceae",
    "hygrophoropsis": f"{B} Boletales Hygrophoropsidaceae", "imleria": f"{B} Boletales Boletaceae",
    "kuehneromyces": f"{B} Agaricales Strophariaceae", "lactifluus": f"{B} Russulales Russulaceae",
    "laetiporus": f"{B} Polyporales Laetiporaceae", "leccinellum": f"{B} Boletales Boletaceae",
    "leccinum": f"{B} Boletales Boletaceae", "lepista": f"{B} Agaricales Tricholomataceae",
    "lycoperdon": f"{B} Agaricales Lycoperdaceae", "morchella": f"{A} Morchellaceae",
    "myriostoma": f"{B} Geastrales Geastraceae", "phaeolepiota": f"{B} Agaricales Squamanitaceae",
    "phallus": f"{B} Phallales Phallaceae", "phellorinia": f"{B} Agaricales Agaricaceae",
    "phylloporus": f"{B} Boletales Boletaceae", "polyporus": f"{B} Polyporales Polyporaceae",
    "pseudocolus": f"{B} Phallales Phallaceae", "ramaria": f"{B} Gomphales Gomphaceae",
    "rubroboletus": f"{B} Boletales Boletaceae", "sarcosoma": f"{A} Sarcosomataceae",
    "scleroderma": f"{B} Boletales Sclerodermataceae", "sparassis": f"{B} Polyporales Sparassidaceae",
    "strobilomyces": f"{B} Boletales Boletaceae", "suillus": f"{B} Boletales Suillaceae",
    "tuber": f"{A} Tuberaceae", "xerocomellus": f"{B} Boletales Boletaceae",
    "xerocomus": f"{B} Boletales Boletaceae",
}


def load_js_object(path: Path) -> dict:
    s = path.read_text(encoding="utf-8")
    return json.loads(s[s.index("{"): s.rstrip().rstrip(";").rindex("}") + 1])


def species_prompts() -> list[dict]:
    """Класи: id, латина, назва, їстівність, Червона книга + підказки для відбитка."""
    catalog = load_js_object(CATALOG_JS)["species"]
    baza, genus_tax = {}, {}
    for b in json.loads(BAZA.read_text(encoding="utf-8")):
        m = re.match(r"A photo of ([A-Z][a-z]+ [a-z\-]+)", b["ai_prompts"]["en"])
        if m:
            baza[m.group(1).lower()] = b
        t = b["taxonomy"]
        # Таксономія за родом — і для видів довідника, яких у базі немає (BioCLIP найкраще знає таксономію).
        genus_tax.setdefault(t.get("genus", "").lower(), " ".join(t.get(k, "") for k in ("kingdom", "division", "class", "order", "family")).strip())
    out = []
    for s in catalog:
        latin = s["latin"].strip()
        prompts = [f"a photo of {latin}."]
        b = baza.get(latin.lower())
        tax = genus_tax.get(latin.split()[0].lower()) or EXTRA_TAXONOMY.get(latin.split()[0].lower())
        prompts.append(f"a photo of {tax} {latin}." if tax else f"a photo of Fungi {latin}, a mushroom.")
        if b:
            prompts.append(b["ai_prompts"]["en"])
        out.append({
            "id": s["id"],
            "latin": latin,
            "name": s["name"],
            "edibility": s.get("edibility") or "",
            "red_listed": bool(s.get("red_listed")),
            "has_photo": bool(s.get("photos")),
            "photo": (s.get("photos") or [None])[0],
            "prompts": prompts,
        })
    return out


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--skip-bench", action="store_true")
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    import open_clip
    import torch
    from PIL import Image

    torch.set_grad_enabled(False)
    model, _, preprocess = open_clip.create_model_and_transforms(MODEL_ID)
    tokenizer = open_clip.get_tokenizer(MODEL_ID)
    model.eval()

    # Параметри підготовки фото — клієнт повторює їх (розмір, середнє, відхилення).
    image_size = model.visual.image_size
    image_size = int(image_size[0] if isinstance(image_size, (tuple, list)) else image_size)
    mean = list(getattr(model.visual, "image_mean", None) or open_clip.OPENAI_DATASET_MEAN)
    std = list(getattr(model.visual, "image_std", None) or open_clip.OPENAI_DATASET_STD)

    # ── Відбитки видів ───────────────────────────────────────────────────────
    classes = species_prompts()
    vecs = []
    for c in classes:
        e = model.encode_text(tokenizer(c["prompts"]))
        e = torch.nn.functional.normalize(e, dim=-1).mean(0)
        vecs.append(torch.nn.functional.normalize(e, dim=-1))
    neg = torch.nn.functional.normalize(model.encode_text(tokenizer(NOT_MUSHROOM)), dim=-1)
    labels = [{k: c[k] for k in ("id", "latin", "name", "edibility", "red_listed", "has_photo")} for c in classes]
    labels += [{"id": "not_mushroom", "latin": "", "name": "Не гриб", "edibility": "", "red_listed": False, "has_photo": False}] * len(NOT_MUSHROOM)
    text = torch.cat([torch.stack(vecs), neg]).numpy().astype(np.float16)
    (args.out / "species_text.f16").write_bytes(text.tobytes())
    (args.out / "labels.json").write_text(json.dumps(labels, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    dim = int(text.shape[1])
    print(f"  відбитки: {len(classes)} видів + {len(NOT_MUSHROOM)} «не гриб», розмірність {dim}")

    # ── Кодувальник зображень → ONNX → int8 ──────────────────────────────────
    class Vision(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, image):
            return torch.nn.functional.normalize(self.m.encode_image(image), dim=-1)

    fp32 = args.out / "vision_fp32.onnx"
    torch.onnx.export(
        Vision(model), torch.zeros(1, 3, image_size, image_size), str(fp32),
        input_names=["image"], output_names=["embedding"],
        dynamic_axes={"image": {0: "batch"}, "embedding": {0: "batch"}}, opset_version=17,
        dynamo=False,  # класичний експортер (TorchScript) — перевірений для ViT / CLIP
    )
    from onnxruntime.quantization import QuantType, quantize_dynamic

    int8 = args.out / "bioclip2_vision_int8.onnx"
    quantize_dynamic(str(fp32), str(int8), weight_type=QuantType.QUInt8)
    # На телефоні — ORT 1.15 (пакет onnxruntime для Flutter): читає моделі до IR 9.
    # Новий onnx зберігає IR 10 — знижуємо версію формату (оператори opset 17 ті самі).
    import onnx

    m = onnx.load(str(int8))
    if m.ir_version > 8:
        m.ir_version = 8
        onnx.save(m, str(int8))
    print(f"  ONNX: fp32 {fp32.stat().st_size / 1e6:.0f} МБ → int8 {int8.stat().st_size / 1e6:.0f} МБ")

    # ── Точність на фото довідника ───────────────────────────────────────────
    bench = None
    if not args.skip_bench:
        import onnxruntime as ort

        txt = text.astype(np.float32)
        sessions = {name: ort.InferenceSession(str(p), providers=["CPUExecutionProvider"]) for name, p in (("fp32", fp32), ("int8", int8))}
        stats = {k: {"top1": 0, "top3": 0, "not_mushroom": 0, "ms": 0.0} for k in sessions}
        n = 0
        for i, c in enumerate(classes):
            if not c["photo"]:
                continue
            path = ROOT / c["photo"]
            if not path.exists():
                continue
            x = preprocess(Image.open(path).convert("RGB")).unsqueeze(0).numpy()
            n += 1
            for k, sess in sessions.items():
                t0 = time.time()
                emb = sess.run(None, {"image": x})[0][0]
                stats[k]["ms"] += (time.time() - t0) * 1000
                order = np.argsort(-(txt @ emb))
                top = [labels[j]["id"] for j in order[:3]]
                stats[k]["top1"] += top[0] == c["id"]
                stats[k]["top3"] += c["id"] in top
                stats[k]["not_mushroom"] += top[0] == "not_mushroom"
        bench = {k: {"top1": v["top1"] / n, "top3": v["top3"] / n, "not_mushroom": v["not_mushroom"] / n, "ms": v["ms"] / n} for k, v in stats.items()}
        bench["photos"] = n
        lines = [
            "# Точність ШІ-розпізнавача (план B5.0)",
            "",
            f"Модель: BioCLIP 2 (`imageomics/bioclip-2`), кодувальник зображень у ONNX; версія {VERSION}.",
            f"Класи: {len(classes)} видів каталогу + «не гриб». Перевірка: {n} фото довідника (по одному на вид).",
            "Відсотки тут — лише для оцінки моделі; користувачу точність числами не показується.",
            "",
            "| Модель | Розмір | top-1 | top-3 | «не гриб» помилково | час / фото (CPU сервера) |",
            "|---|---|---|---|---|---|",
        ]
        for k, p in (("fp32", fp32), ("int8", int8)):
            b = bench[k]
            lines.append(f"| {k} | {p.stat().st_size / 1e6:.0f} МБ | {b['top1']:.0%} | {b['top3']:.0%} | {b['not_mushroom']:.0%} | {b['ms']:.0f} мс |")
        lines += ["", "Збирається заново workflow `.github/workflows/ai-model.yml` (вручну)."]
        BENCH.write_text("\n".join(lines) + "\n", encoding="utf-8")
        (args.out / "AI_BENCHMARK.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
        print("\n".join(lines))

    fp32.unlink()  # у реліз іде лише int8

    files = {}
    for name in ("bioclip2_vision_int8.onnx", "species_text.f16", "labels.json"):
        p = args.out / name
        files[name] = {"size": p.stat().st_size, "sha256": sha256(p)}
    manifest = {
        "version": VERSION,
        "model": "BioCLIP 2 (imageomics/bioclip-2), MIT",
        "image_size": image_size,
        "mean": mean,
        "std": std,
        "dim": dim,
        "classes": len(labels),
        "species": len(classes),
        "logit_scale": float(model.logit_scale.exp().item()),
        "files": files,
        "total_bytes": sum(f["size"] for f in files.values()),
        "benchmark": bench,
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"  разом {manifest['total_bytes'] / 1e6:.0f} МБ → {args.out}")


if __name__ == "__main__":
    sys.exit(main())
