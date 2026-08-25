# modelhub — LLM 网关 + 静态出口代理

本地 LLM 基础设施二合一模块。**独立仓库**，可直接 push 到 GitHub；任何其他 Linux 机器 `git clone` 后按 [快速开始](#快速开始新机器) 三步即可复用。

两个组件：

| 组件 | 端口 | 作用 |
|---|---|---|
| **LiteLLM 网关** | `4000`（可配） | OpenAI 兼容统一入口，路由 本地 vLLM / Galaxy 专线 / OpenRouter |
| **静态出口代理**（mihomo） | `7891` mixed / `9091` API | 按域名把 OpenRouter 等 AI API 流量送**静态住宅 IP** 出口，绕开 API 商对数据中心 IP 的风控；本地与 Galaxy 流量直连不进代理 |

## 拓扑

```
你的程序 ── OpenAI SDK (base_url=http://127.0.0.1:4000/v1) ──▶ LiteLLM 网关
                                                                 │
              ┌──────────────────────────┬───────────────────────┤
              ▼                          ▼                       ▼
        本地 vLLM                   Galaxy 专线              openrouter/*
        (no_proxy 直连)             (no_proxy 直连)              │ 进程级
                                                                 │ http(s)_proxy
                                                                 ▼
                                             mihomo (127.0.0.1:7891, rule 分流)
                                                ┌────────────────┼──────────────┐
                                                ▼                ▼              ▼
                                             STATIC           TUNNEL        DIRECT
                                           (双层链式)        (单层隧道)     (国内 GEOIP)
                                                │
                                                ▼
                            Tunnel 10808(换海外源IP) → 静态IP节点 → 出口=静态住宅IP
```

**为什么静态出口要双层**：静态 IP 节点对来源 IP 有风控，只放行海外源 IP；国内机器直连被拒（403），必须先经 Tunnel 隧道把源 IP 换成海外，再连静态节点。

## 目录结构

```
modelhub/
├── README.md                      # 本文档
├── requirements.txt               # litellm[proxy] 版本锁定
├── .env.example                   # 密钥模板 → 复制为 .env 填真实值
├── install.sh                     # 建 .venv + 装依赖（自动挑 Python 3.11~3.13）
├── start.sh                       # 一键启动: 静态代理(幂等) + 网关 + 代理注入
├── stop.sh                        # 停网关; --all 连静态代理一起停
├── smoke.sh                       # 冒烟: 代理链路/静态出口验证/网关健康/--call 真实调用
├── gateway/
│   └── litellm.yaml               # 模型路由（全走环境变量注入凭据，可入库）
├── static_proxy/
│   ├── config.example.yaml        # mihomo 配置模板（可入库）
│   ├── config.yaml                # 真实节点配置（含凭据，不入库）
│   ├── start.sh / stop.sh         # mihomo 单独启停
│   ├── fetch_mihomo.sh            # mihomo 二进制下载
│   └── country.mmdb               # GeoIP 库（GEOIP,CN,DIRECT 规则依赖，入库）
└── logs/                          # 运行日志与 pid（不入库）
```

## 推到 GitHub（一次性设置）

```bash
cd modelhub
git remote add origin git@github.com:<你>/modelhub.git   # GitHub 上先建好空仓库
git push -u origin main
```

> 提交内容只有代码与模板；`.env` / `static_proxy/config.yaml`（机密）与 mihomo 二进制全部被 .gitignore 拦截，公开仓库也可安全推送。

## 快速开始（新机器）

前提：Linux + Python 3.11~3.13 + `curl`。

```bash
git clone <本仓库地址> modelhub && cd modelhub

# 1) 放两份机密（都不入库；从旧机器拷贝或照模板手填）
#    .env                      ← API keys（模板: .env.example）
#    static_proxy/config.yaml  ← 静态代理节点凭据（模板: static_proxy/config.example.yaml）

# 2) 获取 mihomo 二进制（二选一）
bash static_proxy/fetch_mihomo.sh        # GitHub releases 下载（国内机器可能需先 export https_proxy=...）
# 或从旧机器拷贝:  scp 旧机:modelhub/static_proxy/mihomo static_proxy/

# 3) 安装 + 启动 + 冒烟
bash install.sh
bash start.sh
bash smoke.sh --call        # 看到 "✅ 冒烟全部通过" 即可
```

验证通过后，网关常驻后台（nohup，无 systemd 依赖）。开机自启如需，自行加 crontab `@reboot`。

## 使用（客户端接入）

任何支持 OpenAI 兼容端点的程序都能直接接，**只改 base_url 和模型名**：

```python
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:4000/v1", api_key="anything")  # 网关无鉴权, key 随意

# 本地模型（免费, 有卡就行）
client.chat.completions.create(model="qwen3.8-27b", messages=[...])
# Galaxy 专线
client.chat.completions.create(model="qwen3.7-plus", messages=[...])
# OpenRouter（自动走静态 IP 出口）
client.chat.completions.create(model="openrouter/deepseek/deepseek-chat-v3-0324", messages=[...])
```

```bash
# shell 环境变量式（项目通用约定）
export LLM_BASE_URL=http://127.0.0.1:4000/v1
export LLM_MODEL=openrouter/openai/gpt-4o-mini
```

| 路由 | 模型名 | 出口 | 备注 |
|---|---|---|---|
| 本地 vLLM | `qwen3.8-27b` | 直连 localhost:8000 | 需本机先起 vLLM 服务 |
| Galaxy | `qwen3.7-plus` | 直连（no_proxy） | 现有产线同款 |
| OpenRouter | `openrouter/<org>/<model>` | **静态住宅 IP** | 通配路由, 任意 OR 模型免配置 |

## 配置说明

### `.env`（机密，不入库）

| 变量 | 默认 | 说明 |
|---|---|---|
| `OPENROUTER_API_KEY` | — | 必填 |
| `GALAXY_API_KEY` | — | 必填 |
| `VLLM_API_BASE` | `http://localhost:8000/v1` | 本地 vLLM 端点 |
| `GALAXY_API_BASE` | `https://token.ai-galaxy.com/v1` | Galaxy 端点 |
| `GATEWAY_HOST` / `GATEWAY_PORT` | `127.0.0.1` / `4000` | 网关监听（要跨机共享改 `0.0.0.0` 并自行加防火墙） |
| `PROXY_MIXED_PORT` / `PROXY_API_PORT` | `7891` / `9091` | 与 `static_proxy/config.yaml` 保持一致 |

### `gateway/litellm.yaml`（模型路由）

三条路由的凭据全部 `os.environ/` 注入。加模型 = 在 `model_list` 加一条后 `bash stop.sh && bash start.sh`。

### `static_proxy/config.yaml`（静态代理，机密不入库）

- 要让新域名走静态出口：在 `rules:` 顶部加 `- DOMAIN-SUFFIX,xxx.com,STATIC`，然后 `bash static_proxy/stop.sh && bash static_proxy/start.sh`。
- 换隧道/静态节点：改 `proxies:` 段（双层结构别拆：静态节点必须 `dialer-proxy` 挂隧道）。

## 机密与 git 策略

**入库**：代码、配置模板（`.env.example` / `config.example.yaml`）、`country.mmdb`、README。
**不入库**（`.gitignore` 强制）：`.env`、`static_proxy/config.yaml`（含节点账号密码）、mihomo 二进制、`.venv/`、`logs/`。

> ⚠️ `config.yaml` 里的静态节点凭据等价于付费订阅密钥。即使仓库私有，也建议不提交；确要提交请自行评估风险（`git add -f`）。

## 常用操作

```bash
bash smoke.sh                # 零花费体检（含静态链路命中验证）
bash smoke.sh --call         # 加真实调用
bash stop.sh                 # 停网关（保留静态代理）
bash stop.sh --all           # 全停
tail -f logs/gateway.log     # 网关日志（请求/报错）
tail -f logs/mihomo.log      # 代理分流日志（每请求命中哪条规则）
curl -s http://127.0.0.1:4000/v1/models          # 网关模型清单
curl -s http://127.0.0.1:9091/connections | jq   # mihomo 实时连接（看 chains 验证链路）
```

升级 litellm：改 `requirements.txt` 版本号后 `bash install.sh`。

## FAQ

| 现象 | 原因/处理 |
|---|---|
| `install.sh` 报无 Python 3.11~3.13 | litellm 1.98 需 3.11+（`typing.NotRequired`），3.14 依赖轮子不全；装 3.12 或 `PYTHON=/path` 指定 |
| 网关 60s 未就绪 | 看 `logs/gateway.log`；常见是 `.env` 缺 key 或端口被占 |
| smoke 第 2 步未命中 STATIC | 查 `static_proxy/config.yaml` rules 是否含该域名；隧道离线时先 `nc -z -w 3 <隧道IP> 10808` |
| OpenRouter 仍 403/风控 | 确认 smoke 链路命中 Static 组；静态 IP 订阅是否到期；换节点后重启代理 |
| 端口冲突 | 网关改 `.env` 的 `GATEWAY_PORT`；mihomo 改 config.yaml 的 mixed-port/external-controller/dns listen 并同步 `.env` |
| 其他程序想用静态代理 | 直接 `export http_proxy=http://127.0.0.1:7891 https_proxy=http://127.0.0.1:7891`，无需经过网关 |

