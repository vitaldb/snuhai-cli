# snuhai-cli — 폐쇄망에서 Codex CLI 쓰기

**한국어** · [中文](README.zh-CN.md) · [Español](README.es.md)

인터넷이 차단된 사내망(폐쇄망) PC에서 **[OpenAI Codex CLI](https://github.com/openai/codex)** 를
**사내 LLM 서버**에 연결해 쓰기 위한 도구입니다.

서울대학교병원(SNUH) 원내망을 위해 만들었지만, **OpenAI 호환 API를 제공하는
어떤 사내 LLM 서버에도** 그대로 쓸 수 있습니다.

---

## 두 단계면 끝납니다

```
① 인터넷 되는 PC에서  →  make_snuhai.bat  (한 번만)
                          └→ snuhai-cli 폴더가 만들어집니다

② 그 폴더를 통째로 폐쇄망 PC로 옮기고  →  snuhai.bat  더블클릭
                                           └→ 끝. 바로 씁니다.
```

폐쇄망 PC에는 **아무것도 미리 설치할 필요가 없습니다.** Node.js 도 필요 없습니다
(포터블 Node 가 폴더 안에 들어갑니다).

---

## ① 번들 만들기 (인터넷 되는 PC, 한 번만)

```bat
git clone https://github.com/vitaldb/snuhai-cli.git
cd snuhai-cli
make_snuhai.bat
```

```bash
./make_snuhai.sh          # Linux/macOS 에서 만들 때
```

- `make_snuhai.bat` 는 기본이 Windows 용입니다. `make_snuhai.bat linux` / `both` 로 대상 변경 가능
  (`make_snuhai.sh` 는 기본이 `both`).
- Codex CLI 는 **공개 npm 레지스트리에서 원본 그대로** 받고, **npm 이 게시한 해시와 대조**해
  무결성을 검증합니다(증빙은 `.snuhai/packages/PROVENANCE.txt` 에 남습니다).

완료되면 `snuhai-cli` 폴더가 생깁니다. **이 폴더를 통째로** USB 등으로 옮기세요.

```
snuhai-cli/
├── snuhai.bat        ← Windows: 이것만 실행하면 됩니다
├── snuhai.sh         ← Linux
├── 읽어보세요.txt
└── .snuhai/          ← 실행에 필요한 파일 (지우지 마세요)
```

## ② 폐쇄망 PC에서 쓰기

`snuhai.bat` 을 더블클릭하면 됩니다. 처음 한 번만 물어봅니다.

```
[1] 서버 주소 (Enter=기본값)   ← 서울대학교병원이면 그냥 Enter
[2] API 키                     ← 아래 방법으로 발급
[3] 사용할 모델                ← 서버에서 조회한 목록에서 선택
```

**서울대학교병원 사용자는 서버 주소를 몰라도 됩니다.** Enter 만 누르면
기본값 `https://llm.snuh.org/llm` 이 자동으로 들어갑니다.

### API 키 발급 (원내망에서)

1. 원내망 브라우저로 **<https://ai.snuh.org>** 접속 (SNUH.AI 통합 AI 플랫폼)
2. **SNUHUB 계정**으로 로그인
3. 왼쪽 메뉴에서 **MY → 나의 키 관리**
   (바로가기: `https://ai.snuh.org/setting/my-key`)
4. 오른쪽 위 **＋ 추가** 클릭
5. 구분은 **LLM**, 설명에는 `snuhai-cli` 처럼 알아볼 수 있는 이름을 입력하고 발급
6. 표에 생긴 **키 값**(`sk-` 로 시작)을 복사
7. `snuhai.bat` 실행 후 `API 키:` 에 붙여넣기
   (검은 창에서 **마우스 오른쪽 클릭**이 붙여넣기입니다)

> 발급한 키는 본인만 사용하세요. SNUH.AI 는 원내 전용 시스템이며
> 모든 활동이 감사 로그로 기록됩니다.

그 다음은 자동입니다.

- Codex CLI 를 **오프라인 설치**합니다(최초 1회, 인터넷 불필요).
- 서버가 **Responses API 를 지원하는지 스스로 확인**해서, 지원하면 직결하고
  지원하지 않으면 **게이트웨이를 자동으로 띄웁니다**(아래 참고).
- 설정은 `%USERPROFILE%\.snuhai` 에 저장되어 다음부터는 바로 실행됩니다.

인자는 그대로 codex 에 전달됩니다.

```bat
snuhai.bat                                   :: 대화형
snuhai.bat exec "이 저장소가 하는 일을 설명해줘"
```

---

## 왜 게이트웨이가 필요한가

최신 Codex CLI 는 **Responses API** 만 지원합니다(`wire_api = "chat"` 은 2026년 2월에 제거).
그런데 사내에 흔히 올리는 vLLM·litellm 은 **Chat Completions** 만 제공하는 경우가 많습니다.

`.snuhai/gateway.js` 가 이 둘을 변환합니다. 의존성 없는 Node 파일 하나이며,
**키를 저장하지 않고** `Authorization` 헤더를 그대로 상위 서버에 전달합니다.
`127.0.0.1` 에만 바인딩되고, codex 를 끄면 함께 종료됩니다.

덤으로, 일부 모델에서 나는 `System message must be at the beginning` 오류도
게이트웨이가 **system 메시지를 맨 앞으로 정규화**해서 막아줍니다.

---

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
| `400 System message must be at the beginning` | 게이트웨이가 꺼진 상태. 설정 파일에서 `GW=1` 로 바꾸고 재실행 |
| `Model metadata ... not found` | **무해**. 무시해도 됩니다 |
| 모델 목록이 안 나옴 | 서버 주소와 키가 맞는지 확인 (SNUH 기본값은 `https://llm.snuh.org/llm`) |
| `.snuhai 폴더가 없습니다` | 폴더를 통째로 복사하지 않았습니다. 다시 복사하세요 |

---

## 보안

- **API 키를 저장소에 커밋하지 마세요.** 설정은 각자 PC의 `~/.snuhai` 에만 저장됩니다.
- 게이트웨이는 `127.0.0.1` 전용입니다. 외부에 노출하지 마세요.
- 사내 데이터가 외부로 나가지 않도록 반드시 **사내 LLM 서버**를 지정하세요.

## 라이선스

- 이 저장소의 자체 코드(`gateway.js`, 스크립트, 문서): **Apache-2.0** (`LICENSE`)
- **OpenAI Codex CLI 는 이 저장소에 포함되어 있지 않습니다.** `make_snuhai` 가
  공개 npm 레지스트리에서 **원본 그대로** 내려받습니다(Apache-2.0, `NOTICE` 참조).
- Node.js 도 포함되어 있지 않으며 nodejs.org 에서 내려받습니다(MIT 등).
- "OpenAI" 와 "Codex" 는 OpenAI 의 상표입니다. 본 프로젝트는 OpenAI 와 제휴하거나
  그로부터 보증받지 않았습니다.
