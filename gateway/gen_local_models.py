#!/usr/bin/env python3
"""gateway/gen_local_models.py —— 模型自动发现 + 运行时配置生成

扫描环境变量中的 *_API_BASE（start.sh 已加载 .env 并导出），逐个探测
OpenAI 兼容的 /models 列表:
  - openrouter 同样显式展开全量目录（litellm 的 openrouter/* 通配展开
    有 100 模型上限, 截断严重; 发现失败时兜底写回通配）;
  - 无 /models 列表的端点（如 Galaxy 返回 404）跳过, 由模板里的固定别名兜底。

发现的模型以 <前缀>/<模型id> 命名并入 model_list（前缀 = 变量名去 _API_BASE
小写, 如 VLLM_API_BASE → vllm/<id>）, 与模板合并后写出 .litellm.runtime.yaml,
凭据仍走 os.environ/ 引用, 生成文件不含明文密钥。

尽力而为: 任何异常都退回「基础配置原样」, 不影响网关启动。
"""
import json
import os
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
BASE = HERE / "litellm.yaml"
OUT = HERE / ".litellm.runtime.yaml"

MAX_MODELS = 500


def discover():
    found = {}
    for k in sorted(os.environ):
        if not k.endswith("_API_BASE"):
            continue
        base = os.environ[k]
        if not base:
            continue
        stem = k[: -len("_API_BASE")]
        prefix = stem.lower()
        key = os.environ.get(stem + "_API_KEY", "")
        url = base.rstrip("/") + "/models"
        req = urllib.request.Request(url)
        if key:
            req.add_header("Authorization", f"Bearer {key}")
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                data = json.loads(r.read().decode("utf-8", "replace"))
            ids = [m.get("id") for m in (data.get("data") or []) if m.get("id")]
        except Exception as e:
            print(f"   - {prefix}: 无 /models 列表或不可达, 跳过 ({type(e).__name__})")
            continue
        found[prefix] = (stem, ids[:MAX_MODELS])
        print(f"   - {prefix}: 发现 {len(ids)} 个模型 @ {base}")
    return found


def main():
    import yaml

    cfg = yaml.safe_load(BASE.read_text(encoding="utf-8"))
    model_list = cfg.setdefault("model_list") or []
    existing = {m.get("model_name") for m in model_list}

    print("模型自动发现:")
    added = 0
    for prefix, (stem, ids) in discover().items():
        base_var = stem + "_API_BASE"
        key_var = stem + "_API_KEY"
        for mid in ids:
            name = f"{prefix}/{mid}"
            if name in existing:
                continue
            model_list.append(
                {
                    "model_name": name,
                    "litellm_params": {
                        "model": f"openai/{mid}",
                        "api_base": f"os.environ/{base_var}",
                        "api_key": f"os.environ/{key_var}",
                    },
                }
            )
            existing.add(name)
            added += 1

    # openrouter 显式展开失败时兜底写回通配（litellm 原生展开, 但有 100 模型上限）
    if os.environ.get("OPENROUTER_API_BASE") and not any(
        str(m.get("model_name", "")).startswith("openrouter/") for m in model_list
    ):
        model_list.append(
            {
                "model_name": "openrouter/*",
                "litellm_params": {
                    "model": "openrouter/*",
                    "api_base": "os.environ/OPENROUTER_API_BASE",
                    "api_key": "os.environ/OPENROUTER_API_KEY",
                },
            }
        )
        print("   - openrouter: 发现失败, 兜底写回 openrouter/* 通配（展开有 100 模型上限）")

    OUT.write_text(
        yaml.safe_dump(cfg, allow_unicode=True, sort_keys=False), encoding="utf-8"
    )
    print(f"✅ 运行时配置已生成: {OUT.name}（新增 {added} 个自动发现模型）")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001
        print(f"⚠️  自动发现失败（{e}）, 退回基础配置原样")
        try:
            OUT.write_text(BASE.read_text(encoding="utf-8"), encoding="utf-8")
        except Exception as e2:  # noqa: BLE001
            print(f"❌ 无法写出运行时配置: {e2}")
            sys.exit(1)