"""Перевірка: модель запускається тим самим onnxruntime, що вбудований у застосунок (1.15.1).

Запуск: python3.11 scripts/ai_model/check_mobile_runtime.py dist/ai
"""
import json
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort

out = Path(sys.argv[1])
manifest = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
size = manifest["image_size"]
sess = ort.InferenceSession(str(out / "bioclip2_vision_int8.onnx"), providers=["CPUExecutionProvider"])
emb = sess.run(None, {"image": np.zeros((1, 3, size, size), dtype=np.float32)})[0]
assert emb.shape == (1, manifest["dim"]), emb.shape
assert abs(float(np.linalg.norm(emb[0])) - 1) < 1e-3, "вихід має бути нормований"
print(f"onnxruntime {ort.__version__}: модель запускається, вихід {emb.shape}")
