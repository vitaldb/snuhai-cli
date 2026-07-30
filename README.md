# SNUHAI CLI

**인터넷이 차단된 사내망(폐쇄망) PC에서
[OpenAI Codex CLI](https://github.com/openai/codex) 를 사내 LLM 서버로 쓰게 해 줍니다.**

**한국어** · [English](README.en.md) · [中文](README.zh-CN.md) · [Español](README.es.md)

서울대학교병원(SNUH) 원내망을 위해 만들었지만, **OpenAI 호환 API를 제공하는
어떤 사내 LLM 서버에도** 그대로 쓸 수 있습니다.

---

## 빠른 시작

**① 인터넷 되는 PC에서 한 번** — 배포 파일을 만듭니다.

```bat
git clone https://github.com/vitaldb/snuhai-cli.git
cd snuhai-cli
make_snuhai.bat
```

`snuhai-cli.zip` (약 180MB) 하나가 만들어집니다.

**② 그 ZIP 을 폐쇄망 PC로 옮기고** — 압축을 푼 뒤 `snuhai.bat` 을 더블클릭합니다.

```
snuhai-cli/
├── snuhai.bat        ← 이것만 실행하면 됩니다
├── snuhai.sh         ← Linux
└── .snuhai/          ← 실행에 필요한 파일 (지우지 마세요)
```

폐쇄망 PC에는 **아무것도 미리 설치할 필요가 없습니다.** Node.js 도 필요 없습니다.

---

## 처음 실행하면

세 가지만 물어보고, 그 뒤로는 바로 실행됩니다.

![최초 실행 화면](docs/first-run.png)

```console
============================================================
  snuhai first-time setup
============================================================

 [1] Internal LLM server URL
     Press Enter to use the Seoul National University Hospital default.
     default: https://llm.snuh.org/llm
Server URL (Enter = default):

 [2] How to get an API key (from the intranet)
     1. Open  https://ai.snuh.org  in your browser
     2. Sign in with your SNUHUB account
     3. Left menu:  MY > My Key Management  [나의 키 관리]
        (direct link: ai.snuh.org/setting/my-key)
     4. Click  + Add  [추가]  at the top right
     5. Type = LLM, description e.g. snuhai-cli, then issue it
     6. Copy the key value (starts with sk-) and paste it below
        (right-click in this window = paste)

API key:

 Fetching available models...
Model name:
```

> 도구 화면은 **영어**입니다(외국인 사용자 고려). 대괄호 안 한글은 SNUH.AI 사이트의 실제 메뉴 이름입니다.

**서울대학교병원 사용자는 서버 주소를 몰라도 됩니다** — `[1]` 에서 그냥 Enter 를 누르세요.
설정은 `%USERPROFILE%\.snuhai` 에 저장되어 다음부터는 바로 실행됩니다.

## 사용

인자는 그대로 codex 에 전달됩니다.

```bat
snuhai.bat                                    :: 대화형
snuhai.bat exec "이 저장소가 하는 일을 설명해줘"
```

---

## 어떻게 동작하나

최신 Codex CLI 는 **Responses API** 만 지원합니다(`wire_api = "chat"` 은 2026년 2월 제거).
그런데 사내에 흔히 올리는 vLLM·litellm 은 **Chat Completions** 만 제공하는 경우가 많습니다.

`snuhai.bat` 은 실행할 때 **서버가 Responses API 를 지원하는지 스스로 확인**해서

- 지원하면 → **직결**
- 지원하지 않으면 → **게이트웨이를 자동으로 띄웁니다**

게이트웨이(`.snuhai/gateway.js`)는 의존성 없는 Node 파일 하나입니다.
**키를 저장하지 않고** `Authorization` 헤더를 그대로 상위 서버에 전달하며,
`127.0.0.1` 에만 바인딩되고 codex 를 끄면 함께 종료됩니다.
덤으로 일부 모델에서 나는 `System message must be at the beginning` 오류도
**system 메시지를 맨 앞으로 정규화**해서 막아줍니다.

## 설정 바꾸기

| 하고 싶은 것 | 방법 |
|---|---|
| 서버·키·모델 다시 설정 | `%USERPROFILE%\.snuhai\conf.bat` (Linux: `~/.snuhai/conf.sh`) 삭제 후 재실행 |
| 모델만 변경 | 같은 파일에서 `MODEL=` 값만 수정 |
| 재설치 | `.snuhai\installed.flag` 삭제 후 재실행 |

## 문제 해결

| 증상 | 조치 |
|---|---|
| `401` | 키 오류 — 설정 파일 삭제 후 재실행 |
| `400 System message must be at the beginning` | 설정 파일에서 `GW=1` 로 바꾸고 재실행 |
| `Model metadata ... not found` | **무해**. 무시해도 됩니다 |
| 모델 목록이 안 나옴 | 서버 주소와 키 확인 (SNUH 기본값 `https://llm.snuh.org/llm`) |
| `.snuhai 폴더가 없습니다` | 폴더를 통째로 복사하지 않았습니다 |
| Linux 에서 `Permission denied` | `bash snuhai.sh` 로 실행 (이후 권한이 자동 복구됩니다) |
| 입력을 자동화하면 프롬프트가 안 읽힘 | `set SNUHAI_NO_UTF8=1` 후 실행 — UTF-8 콘솔에서 `set /p` 가 리다이렉트 입력을 못 읽는 cmd 결함 |

## 보안

- **API 키를 저장소에 커밋하지 마세요.** 설정은 각자 PC의 `~/.snuhai` 에만 저장됩니다.
- 게이트웨이는 `127.0.0.1` 전용입니다. 외부에 노출하지 마세요.
- 사내 데이터가 외부로 나가지 않도록 반드시 **사내 LLM 서버**를 지정하세요.

## 무엇이 들어가나 · 라이선스

`make_snuhai` 는 **공개 배포처에서 원본 그대로** 내려받아 묶습니다.
npm 이 게시한 해시와 대조해 무결성을 검증하고 증빙을 `.snuhai/packages/PROVENANCE.txt` 에 남깁니다.

- 이 저장소의 자체 코드(`gateway.js`, 스크립트, 문서): **Apache-2.0** (`LICENSE`)
- **OpenAI Codex CLI 는 이 저장소에 포함되어 있지 않습니다** — Apache-2.0, `NOTICE` 참조
- Node.js 도 포함되어 있지 않으며 nodejs.org 에서 내려받습니다(MIT 등)
- "OpenAI" 와 "Codex" 는 OpenAI 의 상표입니다. 본 프로젝트는 OpenAI 와 제휴하거나
  그로부터 보증받지 않았습니다.
