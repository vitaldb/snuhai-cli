# SNUHAI CLI

**在无法访问互联网的内网（气隙网络）电脑上，把
[OpenAI Codex CLI](https://github.com/openai/codex) 接到内部 LLM 服务器上使用。**

[한국어](README.md) · [English](README.en.md) · **中文** · [Español](README.es.md)

最初为首尔大学医院（SNUH）内网开发，但可用于**任何提供 OpenAI 兼容 API 的内部 LLM 服务器**。

---

## 快速开始

**① 在联网电脑上执行一次** —— 生成离线包。

```bat
git clone https://github.com/vitaldb/snuhai-cli.git
cd snuhai-cli
make_snuhai.bat
```

```bash
./make_snuhai.sh          # 在 Linux/macOS 上生成
```

只会生成一个 `snuhai-cli.zip`（约 180 MB）。

**② 把该 ZIP 拷到内网电脑**，解压后双击 `snuhai.bat`。

```
snuhai-cli/
├── snuhai.bat        ← 只运行这一个（Windows）
├── snuhai.sh         ← Linux
└── .snuhai/          ← 运行所需文件（请勿删除）
```

目标电脑上**无需预装任何东西**，连 Node.js 也不需要。

---

## 首次运行

只询问三项，之后每次都直接启动。

![首次运行界面](docs/first-run.png)

```console
============================================================
  snuhai 최초 설정      (首次设置)
============================================================

 [1] 内部 LLM 服务器地址
     直接回车即使用首尔大学医院默认值。
     默认值: https://llm.snuh.org/llm
服务器地址（回车＝默认值）:

 [2] API 密钥申请方法（在内网中）
     1. 用浏览器打开  https://ai.snuh.org
     2. 使用 SNUHUB 账号登录
     3. 左侧菜单  MY > 나의 키 관리（我的密钥管理）
        （直达 ai.snuh.org/setting/my-key）
     4. 点击右上角  + 추가（添加）
     5. 类别选 LLM，说明填 snuhai-cli 之类的名称后签发
     6. 复制生成的密钥值（以 sk- 开头）并粘贴到下面
        （在此窗口中单击鼠标右键即为粘贴）

API 密钥:

 正在查询可用模型...
使用的模型名称:
```

*（离线包界面为韩文，流程完全相同。）*

配置保存在 `%USERPROFILE%\.snuhai`（Linux：`~/.snuhai`）。

## 使用

参数会原样传给 codex。

```bat
snuhai.bat                            :: 交互式
snuhai.bat exec "解释一下这个仓库的作用"
```

---

## 工作原理

新版 Codex CLI 只支持 **Responses API**（`wire_api = "chat"` 已于 2026 年 2 月移除）。
而内部常见的 vLLM / litellm 往往只提供 **Chat Completions**。

`snuhai` 启动时会**自动检测服务器是否支持 Responses API**：

- 支持 → **直连**
- 不支持 → **自动启动网关**

网关（`.snuhai/gateway.js`）是**零依赖**的单文件 Node 程序：**不保存任何密钥**，
只把 `Authorization` 请求头原样转发给上游；仅监听 `127.0.0.1`，并随 codex 一起退出。
它还会把 **system 消息规范化到最前面**，从而避免某些模型返回的
`System message must be at the beginning` 错误。

## 修改配置

| 需求 | 做法 |
|---|---|
| 重新设置服务器 / 密钥 / 模型 | 删除 `%USERPROFILE%\.snuhai\conf.bat`（Linux：`~/.snuhai/conf.sh`）后重新运行 |
| 只更换模型 | 在同一文件中修改 `MODEL=` |
| 重新安装 | 删除 `.snuhai\installed.flag` 后重新运行 |

## 常见问题

| 现象 | 处理 |
|---|---|
| `401` | 密钥错误 —— 删除配置文件后重新运行 |
| `400 System message must be at the beginning` | 在配置文件中设置 `GW=1` 后重新运行 |
| `Model metadata ... not found` | **无害**，可忽略 |
| 查不到模型列表 | 确认服务器地址与密钥 |
| 提示缺少 `.snuhai` 文件夹 | 没有整体拷贝文件夹 |
| Linux 上 `Permission denied` | 用 `bash snuhai.sh` 运行（之后权限会自动修复） |
| 脚本化输入时跳过提示 | 使用 `set SNUHAI_NO_UTF8=1` —— UTF-8 控制台下 `set /p` 无法读取重定向输入（cmd 缺陷） |

## 安全

- **切勿把 API 密钥提交到仓库。** 配置只保存在本机 `~/.snuhai`。
- 网关仅监听 `127.0.0.1`，请勿对外暴露。
- 请指定**内部** LLM 服务器，避免内部数据外流。

## 打包内容与许可

`make_snuhai` 从**公开来源原样下载**所有组件，并与 npm 公布的哈希值比对校验，
凭证写入 `.snuhai/packages/PROVENANCE.txt`。

- 本仓库的自有代码（`gateway.js`、脚本、文档）：**Apache-2.0**（见 `LICENSE`）
- **本仓库不包含 OpenAI Codex CLI** —— Apache-2.0，详见 `NOTICE`
- 也不包含 Node.js，由 nodejs.org 下载（MIT 等）
- “OpenAI” 与 “Codex” 是 OpenAI 的商标。本项目与 OpenAI 无从属关系，也未获其背书。
