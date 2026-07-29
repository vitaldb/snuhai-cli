# snuhai-cli — 在隔离内网中使用 Codex CLI

[한국어](README.md) · **中文** · [Español](README.es.md)

在**无法访问互联网的内网（气隙网络）**电脑上，把
**[OpenAI Codex CLI](https://github.com/openai/codex)** 接到**内部 LLM 服务器**上使用的工具。

最初为首尔大学医院（SNUH）内网开发，但可直接用于**任何提供 OpenAI 兼容 API 的内部 LLM 服务器**。

---

## 只有两步

```
① 在联网电脑上  →  运行 make_snuhai.bat（只需一次）
                    └→ 生成 snuhai-cli 文件夹

② 把整个文件夹拷到内网电脑  →  双击 snuhai.bat
                                └→ 完成，直接使用。
```

内网电脑上**无需预装任何东西**，连 Node.js 也不需要（便携版 Node 已放在文件夹内）。

---

## ① 生成离线包（联网电脑，只做一次）

```bat
git clone https://github.com/<账号>/snuhai-cli.git
cd snuhai-cli
make_snuhai.bat
```

```bash
./make_snuhai.sh          # 在 Linux/macOS 上生成
```

- `make_snuhai.bat` 默认生成 Windows 版。可用 `make_snuhai.bat linux` / `both` 更改目标
  （`make_snuhai.sh` 默认为 `both`）。
- Codex CLI 从**公开 npm registry 原样下载**，并与 **npm 公布的哈希值比对**校验完整性
  （凭证保存在 `.snuhai/packages/PROVENANCE.txt`）。

完成后会生成 `snuhai-cli` 文件夹。请把**整个文件夹**（例如用 U 盘）拷到目标电脑。

```
snuhai-cli/
├── snuhai.bat        ← Windows：只运行这一个
├── snuhai.sh         ← Linux
├── 읽어보세요.txt     ← 说明（韩文）
└── .snuhai/          ← 运行所需文件（请勿删除）
```

## ② 在内网电脑上使用

双击 `snuhai.bat` 即可。仅首次会询问：

```
服务器地址： https://llm.example.org/v1
API 密钥：   ****
使用的模型： （会列出从服务器查询到的模型）
```

之后全部自动完成：

- **离线安装** Codex CLI（仅首次，无需联网）。
- 自动检测服务器**是否支持 Responses API**：支持则直连，不支持则**自动启动网关**（见下文）。
- 配置保存在 `%USERPROFILE%\.snuhai`，之后直接启动。

参数会原样传给 codex：

```bat
snuhai.bat                              :: 交互式
snuhai.bat exec "解释一下这个仓库的作用"
```

---

## 为什么需要网关

新版 Codex CLI 只支持 **Responses API**（`wire_api = "chat"` 已于 2026 年 2 月移除）。
而内部常用的 vLLM / litellm 往往只提供 **Chat Completions**。

`.snuhai/gateway.js` 负责两者之间的转换。它是**零依赖**的单文件 Node 程序，
**不保存任何密钥**，只把 `Authorization` 请求头原样转发给上游服务器。
它只监听 `127.0.0.1`，并在 codex 退出时一并关闭。

此外，某些模型会报 `System message must be at the beginning`，
网关会把 system 消息**规范化到最前面**，从而避免该错误。

---

## 修改配置

| 需求 | 做法 |
|---|---|
| 重新设置服务器/密钥/模型 | 删除 `%USERPROFILE%\.snuhai\conf.bat`（Linux：`~/.snuhai/conf.sh`）后重新运行 |
| 只换模型 | 在同一文件中修改 `MODEL=` 的值 |
| 重新安装 | 删除 `.snuhai\installed.flag` 后重新运行 |

## 常见问题

| 现象 | 处理 |
|---|---|
| `401` | 密钥错误 —— 删除配置文件后重新运行 |
| `400 System message must be at the beginning` | 网关未启用。把配置文件中的 `GW=1` 后重新运行 |
| `Model metadata ... not found` | **无害**，可以忽略 |
| 查不到模型列表 | 确认服务器地址以 `/v1` 结尾，且密钥正确 |
| 提示找不到 `.snuhai` 文件夹 | 没有整个文件夹拷贝，请重新拷贝 |

---

## 安全

- **切勿把 API 密钥提交到仓库。** 配置只保存在本机的 `~/.snuhai`。
- 网关仅监听 `127.0.0.1`，请勿对外暴露。
- 为避免内部数据外流，请务必指定**内部 LLM 服务器**。

## 许可

- 本仓库的自有代码（`gateway.js`、脚本、文档）：**Apache-2.0**（见 `LICENSE`）
- **本仓库不包含 OpenAI Codex CLI。** 由 `make_snuhai` 从公开 npm registry
  **原样**下载（Apache-2.0，详见 `NOTICE`）。
- 同样不包含 Node.js，由 nodejs.org 下载（MIT 等）。
- “OpenAI” 与 “Codex” 是 OpenAI 的商标。本项目与 OpenAI 无从属关系，也未获其背书。
