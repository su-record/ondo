# ondo — SPEC (2026-11-26 확정)

> 가칭 **Ondo**(온도). 토리랩스(Tory Labs)의 무료 오픈소스 macOS 메뉴바 앱. MIT 라이선스.
> 2026-11-26 사용자가 15절 결정을 모두 승인했다("전부 예, 구현 시작해"). 시간 설정은 분 단위(사용자 요구).

## 1. 목적

맥북 뚜껑을 닫아도 잠들지 않게 하되, 온도와 전원을 감시해 위험하면 스스로 깨어있기를 풀고 재운다.
Amphetamine·KeepingYouAwake와 다른 점은 과열 보호다.

## 2. 기능

| # | 기능 | 동작 |
|---|---|---|
| 1 | 닫아도 깨어있기 | 메뉴 토글로 `pmset -a disablesleep 1/0`. 메뉴바 아이콘이 상태에 따라 바뀐다. |
| 2 | 꺼지는 시간 *(추가 요청)* | 켤 때 언제 끌지 **분 단위**로 정한다: 무제한 / 지속 시간 직접 입력(시간·분, 1분~24시간) / 특정 시각까지(시:분). 30분·1·2·4·8시간은 빠른 선택으로 둔다. 시간이 되면 깨어있기를 끈다. 메뉴에 남은 시간을 분까지 보인다. |
| 3 | 온도 표시 | CPU(SoC) 온도를 메뉴에 실시간 표시. 못 읽으면 「온도 측정 불가」로 표시하고 다른 기능은 계속 동작한다. |
| 4 | 과열 자동 해제 | 5절의 규칙대로 알림 → CPU 상위 프로세스 3개 표시 → 계속 뜨거우면 해제하고 재운다. |
| 5 | 전원 안전장치 | 깨어있기 중 충전기가 빠지거나 배터리가 하한(기본 20%) 아래로 내려가면 해제하고 재운다. |
| 6 | 화면만 끄기 | 메뉴 항목 → `pmset displaysleepnow` (root 불필요). |
| 7 | 항상 원복 | 앱 종료·충돌·재부팅 어느 경우에도 `disablesleep 0`으로 돌아간다. 6절 참고. |
| 8 | 잠든 뒤 다시 깨우기 *(추가 요청, 실험 후 확정)* | 9절. 헬퍼 권한 확장이 필요해 승인 대상이다. |
| 9 | 외부·AI 제어 *(추가 요청)* | `ondo` CLI, MCP 서버(`ondo mcp`), URL 스킴(`ondo://`). 8절. |

공통 규칙
- 앱은 항상 「꺼짐」으로 시작한다. 켜진 상태를 저장했다가 되살리지 않는다.
- 「해제 후 재우기」는 뚜껑이 닫혀 있을 때만 즉시 잠재운다. 뚜껑이 열려 있으면 깨어있기만 끄고 알림을 보낸다(사용 중인 화면을 갑자기 재우지 않는다). 뚜껑 상태는 IORegistry `AppleClamshellState`로 읽는다(root 불필요, 이 맥에서 읽힘 확인).
- 잠재우기는 `disablesleep 0`을 먼저 적용한 뒤 앱이 `IOPMSleepSystem`을 호출한다. 애플 문서상 콘솔 사용자는 root 없이 호출할 수 있다(실기기 확인 예정). 헬퍼 권한은 늘리지 않는다.
- 과열 상태이거나 배터리 하한 아래이면 켜기를 거절하고 이유를 보인다(메뉴·CLI 모두).

## 3. 구조

```
┌──────────── Ondo.app (사용자 권한) ─────────────┐        ┌─ OndoHelper (root, LaunchDaemon) ─┐
│ 메뉴바 UI · 보호 규칙 · 센서 읽기 · 전원 감시     │──XPC──▶│ setSleepDisabled(Bool) 만 받는다     │
│ 제어 소켓 서버 · URL 스킴 처리                   │        │ (승인 시 예약 깨우기 등록·취소 추가)    │
└──────────▲───────────────────────────────────┘        └──────────────────────────────────┘
           │ Unix 소켓 (JSON, 같은 사용자만)
   ondo CLI ── ondo mcp (AI 에이전트용 MCP stdio 서버)
```

- **Ondo.app**: SwiftUI `MenuBarExtra`(macOS 13+), Dock 아이콘 없음(`LSUIElement`). App Sandbox는 쓰지 않는다(SMC·센서·프로세스 목록 접근 때문). Hardened Runtime은 켠다(공증 필수 조건).
- **OndoHelper**: `SMAppService.daemon`으로 등록하는 root 데몬. 처음 한 번 시스템 설정 › 일반 › 로그인 항목에서 「백그라운드 허용」을 켜면 이후 비밀번호를 묻지 않는다. sudoers는 건드리지 않는다.
- **ondo CLI**: 앱 번들 안 `Contents/Helpers/ondo`. 앱 실행 파일 `Ondo`와 같은 폴더에 두면 대소문자 무시 파일 시스템에서 이름이 겹치므로 폴더를 나눈다.
- 번들 ID: 앱 `dev.torylabs.ondo`, 헬퍼 `dev.torylabs.ondo.helper`(XPC 서비스 이름 동일).

## 4. 온도 센서 모듈 (`OndoSensors`)

별도 모듈로 분리한다. 앱·CLI(`ondo sensors`)·디버그 메뉴가 같은 모듈을 쓴다.

**공급원(순서대로 시도)**
1. HID 센서 (`IOHIDEventSystemClient`, 비공개 API): 이름이 `PMU tdie*`인 센서. 애플 실리콘.
2. SMC (`AppleSMC`): 칩별 알려진 키 표(M1~M4: 오픈소스 Stats 등 공개 자료 기준, 출처 표기) → 표에 없는 칩이면 `Tp*`·`Te*` 키를 열거해서 찾는다. 인텔은 `TC0P`·`TC0D`·`TC0E`·`TC0F`(sp78 형식).
3. 모두 실패 → 「온도 측정 불가」. 과열 보호가 꺼졌다는 경고를 메뉴에 띄우고, 나머지 기능은 그대로 동작한다.

**판정값**: 선택된 CPU 센서들의 최댓값. 0~150°C 밖의 값은 버린다(아래 실측의 `PMU tdev*` −9201 같은 쓰레기 값).
**읽기 주기**: 깨어있기 중 2초. 꺼져 있으면 메뉴가 열려 있을 때만 읽는다.

**이 맥(M5 Pro, macOS 27.0.1)에서 실측 — 2026-11-26, root 없이 읽힘**
- HID: 센서 77개. `PMU tdie1`~`tdie14` 55~64°C, `PMU tdev*`는 −9201(쓸 수 없음), `gas gauge battery` 33~35°C, `NAND CH0 temp` 38°C.
- SMC: 키 3626개. `Tp**` 23개(flt) 51~60°C, 배터리 `TB0T`·`TB1T`·`TB2T` 33.5~35°C.
- 아직 확인 못 함: M1~M4, 인텔 맥(가진 기기가 없음). 디버그 메뉴의 「센서 값 복사」로 사용자 보고를 받아 표를 보완한다.

**디버그 메뉴**
- 센서 값 보기: 공급원별 전체 센서 이름·값과 판정에 쓰인 센서 표시, 「복사」 버튼(이슈 보고용 텍스트).
- 온도 시뮬레이션: 판정값을 임의 값으로 바꿔 과열 규칙을 실제 앱에서 시험한다. 10분 뒤 자동으로 꺼지고, 켜진 동안 메뉴에 「시뮬레이션 중」이 보인다.
- 상태 로그: 최근 규칙 판단(경고·해제·거절)과 헬퍼 응답 50줄.

## 5. 보호 규칙

```
정상 ──(판정 온도 ≥ 기준, N초 연속)──▶ 경고: 알림 + CPU 상위 프로세스 3개
경고 ──(기준 −3°C 아래로 내려감)────▶ 정상
경고 ──(기준 이상 상태로 N초 더)──────▶ 해제: disablesleep 0 → 뚜껑 닫힘이면 즉시 잠자기
```
- 기준과 −3°C 사이에서는 상태를 유지하고 해제 타이머만 멈춘다(경계에서 알림이 반복되지 않게).
- 상위 프로세스: `ps -Aceo pid,pcpu,comm -r`의 상위 3개(ps 자신 제외). 알림 본문과 메뉴에 이름·CPU%를 보인다.
- 전원: `IOPSNotificationCreateRunLoopSource`로 충전기 분리·배터리 잔량 변화를 받는다. 깨어있기 중 충전기 분리(설정으로 끌 수 있음) 또는 하한 미만 → 즉시 해제.
- 타이머 만료 → 해제.
- 규칙 판단은 시계를 주입받는 순수 로직(`OndoCore`)으로 만들어 단위 테스트한다.

## 6. 원복 보장 (`disablesleep 0`)

| 상황 | 원복 방법 |
|---|---|
| 메뉴 「종료」·⌘Q | 앱이 헬퍼에 0을 요청하고 응답을 최대 2초 기다린 뒤 끝난다. |
| 앱 충돌·강제 종료(`kill -9`) | 헬퍼가 XPC 연결 끊김을 감지하면 0. |
| 헬퍼가 종료 신호를 받음(로그인 항목에서 끔, 종료·재부팅) | 헬퍼의 SIGTERM 처리에서 0. |
| 헬퍼가 `kill -9`로 죽음 | 헬퍼는 시작할 때마다 먼저 0을 적용한다. 앱은 연결이 끊기면 다시 연결하고, 켜져 있어야 하면 다시 요청한다. |
| 재부팅·로그아웃 | 앱의 전원 끄기 알림에서 0, 헬퍼의 SIGTERM에서 0, 부팅 시 헬퍼 `RunAtLoad`에서 0. |
| 앱 시작 시 `SleepDisabled`가 이미 1 | 0으로 돌린다(앱은 항상 꺼짐으로 시작). |

- 알려진 충돌: Amphetamine의 「Closed-Display Mode」 등 다른 앱도 같은 `disablesleep` 값을 쓴다. Ondo는 시작·종료 때 0으로 돌리므로 함께 쓰면 서로 덮어쓴다. README에 적는다.

## 7. 권한 헬퍼

- XPC 프로토콜은 하나뿐이다: `setSleepDisabled(_ on: Bool, reply:)`. 문자열 명령을 받지 않으므로 다른 명령을 실행할 경로가 없다.
- 실행: `/usr/bin/pmset -a disablesleep 1` 또는 `0`. 셸을 거치지 않고 고정 인자로 실행한다.
- 호출자 검증: 들어오는 연결에 `setCodeSigningRequirement`(macOS 13+)로 「같은 팀 ID로 서명된 `dev.torylabs.ondo`」만 허용한다. 앱도 헬퍼의 서명을 같은 방식으로 확인한다.
- 승인 흐름: 처음 켤 때 헬퍼가 승인 전이면 「시스템 설정에서 허용이 필요합니다」 안내와 함께 해당 설정 화면을 연다(`SMAppService.openSystemSettingsLoginItems()`).
- 설정에 「헬퍼 제거」 버튼(`unregister`)을 둔다. 앱을 지우기 전에 쓰도록 README에 적는다.
- 9절(다시 깨우기)이 승인되면 `scheduleWake(at:)`·`cancelWake()` 두 개만 추가한다. `IOPMSchedulePowerEvent`를 Ondo 전용 ID로만 등록하고, 24시간 이내 미래 시각만 받는다.

## 8. 외부·AI 제어

앱이 `~/Library/Application Support/dev.torylabs.ondo/control.sock`(권한 0600, 같은 사용자만)에서 JSON 요청을 받는다. CLI와 MCP는 이 소켓을 통해 앱에 요청하고, 헬퍼에는 직접 닿지 않는다. 앱이 꺼져 있으면 CLI가 앱을 백그라운드로 실행하고 최대 5초 기다린다.

**CLI**
```
ondo status [--json]              깨어있기·남은 시간·온도·전원·경고 상태
ondo on [--for 90m|1h30m|2h] [--until 07:30]      분 단위
ondo off
ondo temp [--json]                판정 온도(+ 배터리 온도)
ondo sensors [--json]             센서 전체 덤프(디버그)
ondo display-off                  화면만 끄기
ondo wake --in 30m | --at 07:00 | --cancel     (9절 승인 시)
ondo mcp                          MCP stdio 서버
```
종료 코드: 0 성공, 1 오류, 2 앱에 연결 못 함, 3 보호 규칙이 거절(과열·배터리 부족 등, 이유를 함께 출력).

**MCP** (`ondo mcp`): Claude Code·Claude 데스크톱·Codex 같은 AI 앱이 쓰는 표준 도구 연결 방식. 도구: `ondo_status`, `ondo_on`(`minutes` 또는 `until` "HH:mm"), `ondo_off`, `ondo_temperature`, `ondo_display_off`, (승인 시) `ondo_schedule_wake`. 외부 라이브러리 없이 JSON-RPC 몇 가지 메서드만 직접 구현한다. 등록 예: `claude mcp add ondo -- ondo mcp`.

**URL 스킴**: `ondo://on?for=2h`, `ondo://off`, `ondo://display-off`. 단축어·Raycast·Alfred에서 「URL 열기」로 쓴다(응답이 필요 없는 명령만).

**범위 제한**: 외부 호출은 켜기·끄기·조회·화면 끄기까지만 한다. 임계 온도 같은 보호 설정 변경은 앱 설정 화면에서만 한다. AI가 보호 기준을 낮춰 과열을 허용하는 일을 막기 위해서다.

## 9. 잠든 뒤 다시 깨우기 (실험 후 확정)

요청을 두 가지로 해석했다.
- **예약 깨우기**: 「N분 뒤」 또는 「시:분에」 맥을 깨운다. 분 단위로 정한다.
- **과열 후 재개**: 과열로 잠든 뒤 설정한 시간(분 단위, 기본 30분, 1~240분)이 지나면 깨워서, 온도가 기준 −10°C 아래면 깨어있기를 다시 켜고 아니면 다시 재운다. 최대 3번까지.

미확인: 뚜껑이 닫힌 애플 실리콘 맥북에서 예약 깨우기가 앱이 다시 `disablesleep 1`을 걸 만큼 깨어나는지 모른다(화면 없이 잠깐 깨는 DarkWake 뒤 바로 다시 잠들 수 있음). 구현 전에 실기기에서 `pmset schedule wake`로 실험하고, 안 되면 「뚜껑이 열려 있거나 외부 모니터가 있을 때만」으로 범위를 줄이거나 뺀다. 실험에는 사용자가 뚜껑을 닫아 주어야 한다.

## 10. 화면

**메뉴(창 스타일 `MenuBarExtra`)** — 메뉴가 열린 동안에도 온도가 갱신되도록 기본 메뉴 대신 작은 창 스타일을 쓴다.

```
┌───────────────────────────────────────┐
│ 닫아도 깨어있기                  [ ●  ] │
│ 끄는 시점  ( ) 무제한                     │
│           (●) [ 1 ]시간 [ 30 ]분 뒤       │
│           ( ) [ 07 ]:[ 30 ]에             │
│           빠른 선택: 30분 1h 2h 4h 8h     │
│ 남은 1시간 12분 (03:30에 꺼짐)             │
├───────────────────────────────────────┤
│ CPU 62°C    배터리 34°C                 │
│ 과열 기준 85°C · 배터리 82% 충전 중        │
├───────────────────────────────────────┤
│ ⚠ 85°C 넘은 지 48초 — 40초 뒤 해제        │   ← 경고 중에만
│   swift-frontend 312% · node 140% ·     │
│   WindowServer 22%                      │
├───────────────────────────────────────┤
│ 화면만 끄기                               │
│ 디버그 ▸                                  │
│ 설정…                              ⌘,   │
│ 종료                               ⌘Q   │
└───────────────────────────────────────┘
```
메뉴바 아이콘(SF Symbols): 꺼짐 `moon.zzz` · 켜짐 `sun.max.fill` · 과열 경고 `thermometer.sun.fill` · 온도 측정 불가 상태로 켜짐 `sun.max.trianglebadge.exclamationmark`(없으면 `sun.max` + 느낌표 합성).

**설정 창** — 탭 4개
- 일반: 로그인 시 자동 실행(`SMAppService.mainApp`), 헬퍼 상태(허용됨/허용 필요 → 시스템 설정 열기, 헬퍼 제거), 기본 끄는 시점
- 보호: 임계 온도, 지속 시간 N, 배터리 하한, 충전기 분리 시 해제, (승인 시) 과열 후 재개
- 외부 제어: CLI 경로와 설치 명령 복사, MCP 등록 명령 복사
- 정보: 버전, 「Made by Tory Labs」, https://torylabs.dev 링크, MIT 라이선스

**설정값**

| 항목 | 기본 | 범위 |
|---|---|---|
| 임계 온도 | 85°C | 60~105°C |
| 지속 시간 N | 60초 | 10~600초 |
| 배터리 하한 | 20% | 5~80% |
| 충전기 분리 시 해제 | 켬 | |
| 기본 끄는 시점 | 무제한 | 무제한 / 1분~24시간(분 단위) |
| 과열 후 재개 대기 (9절 승인 시) | 30분 | 1~240분 |
| 로그인 시 자동 실행 | 끔 | |

## 11. 빌드·배포

- Xcode 프로젝트 대신 Swift Package(`Package.swift`) + 셸 스크립트로 `.app`을 조립한다. 이 맥에 xcodegen·Homebrew가 없고, 손으로 쓴 `.xcodeproj`는 깨지기 쉽기 때문이다. Xcode에서 `Package.swift`를 열어 편집·디버그할 수 있다. 외부 의존성은 없다.
- `scripts/build-app.sh`: `swift build -c release --arch arm64 --arch x86_64`(유니버설) → 번들 조립 → 안쪽 실행 파일부터 Developer ID 서명(Hardened Runtime, 타임스탬프).
- `scripts/make-dmg.sh`: `hdiutil`로 DMG(Applications 바로가기 포함) → 서명 → `xcrun notarytool submit --wait` → `stapler staple` → `spctl`로 확인. 서명 인증서와 공증 프로필은 환경 변수(`SIGN_IDENTITY`, `NOTARY_PROFILE`)로 받는다. 같은 개발자 계정이면 voin에서 만든 공증 프로필을 그대로 쓸 수 있다.
- 버전: 첫 공개 0.1.0. 이후 버전은 올리기 전에 확인받는다.
- Homebrew: `packaging/homebrew/ondo.rb` 초안. 공식 homebrew/cask는 본인이 올릴 때 GitHub 저장소가 별 225개·포크 90개·지켜보기 90개 중 하나 이상이고 30일 이상 지나야 받아준다(docs.brew.sh 「Package Acceptance Policy」). 그래서 먼저 자체 tap(`su-record/homebrew-tap`, 설치: `brew install --cask su-record/tap/ondo`)에 올리고, 조건을 채우면 같은 파일로 공식에 낸다. cask에는 `binary`(CLI 연결), `uninstall launchctl:`, `zap`을 넣는다.
- README.md(영어)·README.ko.md(한국어): 설치, 동작 원리, 과열 보호 설명, 헬퍼 허용 방법, 외부·AI 제어, 삭제 방법, 다른 앱과의 충돌, MIT.

## 12. 폴더 구조

```
ondo/
├── SPEC.md
├── README.md · README.ko.md · LICENSE
├── Package.swift
├── Sources/
│   ├── OndoApp/                 메뉴바 앱
│   │   ├── OndoApp.swift        @main, MenuBarExtra, 설정 창
│   │   ├── MenuView.swift
│   │   ├── SettingsView.swift
│   │   ├── DebugView.swift      센서 값 · 시뮬레이션 · 상태 로그
│   │   ├── AppController.swift  상태 보관, 규칙 실행, 알림
│   │   ├── HelperClient.swift   SMAppService 등록, XPC 호출
│   │   ├── ControlServer.swift  CLI·MCP용 소켓, URL 스킴
│   │   ├── PowerMonitor.swift   충전기·배터리·뚜껑 상태
│   │   └── TopProcesses.swift
│   ├── OndoCore/                순수 로직: 보호 규칙, 설정, 타이머, 제어 메시지 형식
│   ├── OndoSensors/             온도 센서 모듈(Swift)
│   ├── CSensors/                SMC 구조체 · HID 비공개 함수 선언(C)
│   ├── OndoHelperShared/        XPC 프로토콜, 서명 요구 문자열
│   ├── OndoHelper/              root 데몬
│   └── OndoCLI/                 ondo CLI + ondo mcp
├── Tests/
│   ├── OndoCoreTests/           규칙 상태 기계, 타이머, 설정 범위
│   └── OndoSensorsTests/        값 해석(flt·sp78), 이상값 제외, 공급원 선택
├── Resources/
│   ├── Info.plist · Ondo.entitlements · AppIcon.icns
│   └── dev.torylabs.ondo.helper.plist   (Contents/Library/LaunchDaemons로 복사)
├── scripts/
│   ├── build-app.sh
│   └── make-dmg.sh
├── packaging/homebrew/ondo.rb
└── docs/manual-tests.md         기능별 수동 테스트 체크리스트
```

## 13. 구현 순서

각 단계 끝에 `docs/manual-tests.md`의 해당 체크리스트를 이 맥에서 실제로 돌려 본다.

1. 센서 모듈 + `ondo sensors` + 디버그 「센서 값 보기」
2. 헬퍼 + 깨어있기 토글 + 원복 보장(6절 표의 모든 경우를 실제로 시험)
3. 보호 규칙: 과열·전원·타이머(시뮬레이션으로 시험)
4. 화면만 끄기, 설정 창, 로그인 시 실행, 정보
5. 외부 제어: 제어 소켓, CLI, MCP, URL 스킴
6. 다시 깨우기 실험 → 결과에 따라 구현 또는 제외
7. 배포: 서명·공증 DMG, cask, README

## 14. 위험과 미확인

- 기본 임계 85°C: 애플 실리콘은 빌드 같은 무거운 작업에서 90°C를 넘기는 일이 흔하다. 기본값으로는 무거운 작업 중 자주 해제될 수 있어서, 2단계 후 실제 작업 온도를 재고 기본값을 다시 제안한다.
- 비공개 API: HID 센서 함수와 SMC 키는 애플이 문서화하지 않았다. macOS 업데이트로 바뀔 수 있어 공급원을 둘 두고, 못 읽어도 앱이 멈추지 않게 한다.
- `disablesleep`은 시스템 전체 설정이다. 다른 앱과 충돌할 수 있다(6절).
- `IOPMSleepSystem`을 root 없이 부를 수 있는지는 실기기에서 확인한다. 안 되면 사용자 권한 `pmset sleepnow`로 바꾸고, 둘 다 안 되면 헬퍼에 「잠재우기」 하나를 더하는 안을 다시 묻는다.
- 인텔·M1~M4 미시험. 유니버설 빌드는 만들지만 실기기 확인은 사용자 보고에 기댄다.

## 15. 결정 (2026-11-26 모두 승인)

1. 앱 이름 **ondo**(CLI `ondo`, 번들 ID `dev.torylabs.ondo`). 사용자가 「ondo 페이지」를 요청해 이름은 ondo로 진행한다(2026-11-26). 표기는 토리랩스 관례(vica·voin)를 따라 소문자 `ondo`로 하고, 이 문서의 `Ondo.app`·`OndoHelper` 같은 이름은 구현 때 `ondo.app`으로 맞춘다. homebrew/cask에 `ondo`는 아직 없다(2026-11-26 확인).
2. 「꺼지는 시간」 = 깨어있기 지속 시간·종료 시각, 분 단위(2절 기능 2). 직접 입력 지속 시간은 최대 24시간, 그보다 길면 무제한을 쓴다.
3. 「다시 깨우기」 = 예약 깨우기 + 과열 후 재개. 실험 후 확정. 헬퍼에 `scheduleWake`·`cancelWake` 추가 허용.
4. 외부 제어 = CLI + MCP + URL 스킴. 보호 설정 변경은 앱에서만.
5. 배터리 온도: 표시하고 판정에도 쓴다(기본 45°C, 넘으면 CPU와 같은 규칙). 이 맥에서 `TB0T`~`TB2T`로 읽힌다.
6. GitHub 계정은 기존 관례대로 `su-record`(토리랩스 사이트의 GitHub 링크, `vica-releases`·`voin-releases`가 여기 있다), Homebrew는 자체 tap(`su-record/homebrew-tap`) 먼저.

## 16. 구현 중 결정과 변경 (2026-11-26)

- **표기·이름**: 소문자 `ondo`, 앱 번들 `ondo.app`, 실행 파일 `ondo`, 도우미 `ondo-helper`. CLI는 이름이 같아 `Contents/Helpers/ondo`에 둔다.
- **디자인**: Astryx(meta/astryx, MIT)의 규칙을 SwiftUI로 옮겼다. 4 pt 간격, 역할별 모서리(항목 6 · 컨트롤 10 · 카드 12), 컨트롤 높이 28/32, 간격으로 묶기, 의미별 색. Astryx의 Swift 패키지는 실험 단계라 의존성으로 넣지 않았다. 승인한 시안: `design/mockups/astryx-direction.html`.
- **메뉴 높이**: 모든 상태에서 같다. 끄는 시점 묶음과 과열 경고가 같은 높이의 칸을 나눠 쓰고, 안내·오류는 머리글의 상태 줄 한 줄에 보인다.
- **아이콘**: 시안 C(덮인 노트북 위 온도계). 메뉴바 아이콘의 수은은 늘 CPU 온도를 보여 준다. 40°C까지 파랑, 뜨거워질수록 초록·노랑·주황을 거쳐 기준에서 빨강(사용자 결정 「쿨링상태는 40도」). 수은 높이도 세 단계로 오른다. 깨어있기가 켜지면 노트북이 진해진다.
- **온도 읽기 주기**: 깨어 있거나 메뉴가 열려 있으면 2초, 아니면 10초(메뉴바 아이콘 갱신).
- **메뉴바에서 아이콘이 가려질 때**: 실행 중인 ondo를 다시 열면 같은 메뉴가 창으로 뜬다.
- **도우미 수명**: 연결이 없고 잠자기가 허용된 상태로 10초가 지나면 스스로 끝난다. 앱은 깨어있기가 켜진 동안에만 연결을 유지한다. 앱을 업데이트한 뒤 새 도우미가 쓰이게 하기 위해서다.
- **센서 선택**: 칩별 키 표 대신 이름 규칙을 쓴다. HID `PMU tdie*` → SMC `Tp*`·`Te*` → Intel `TC0D/E/F/P`·`TCXC` 순서다.
- **공증**: keychain 프로필 또는 App Store Connect API 키(`APPLE_API_KEY*`).
- **깨우기 판정 여유**: 예약 시각 5초 전부터 도래로 본다. 처음 60초로 두었다가, 1분 대기에서 곧바로 도래로 처리되는 결함이 시험에서 나와 줄였다.
