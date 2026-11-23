# 칼퇴 (Windows)

퇴근(또는 점심)까지 남은 시간을 보여 주는, 항상 최상단에 뜨는 플로팅 위젯 + 트레이 아이콘 + 설정 창.
동작·문구·색은 모두 [`docs/spec.md`](../docs/spec.md) 가 기준이다. 맥 버전과 같은 동작을 낸다.

## 구성

| 폴더 | 내용 |
|---|---|
| `Kaltoe.Core` | 플랫폼 무관 클래스 라이브러리(`net11.0`). 설정 모델·검증, 출근 규칙, 상태 기계(`WorkdayEngine`), 스냅샷 계산, 문구, 알림 계획, 마스코트 재생 순서, 말풍선 문구·윤곽, 위젯 위치 계산. **시스템 호출 없음** — 시각·잠금 여부·기록을 인자로 받는다. |
| `Kaltoe.Core.Tests` | xUnit. 맥·윈도우 어디서나 `dotnet test` 로 돌아간다. |
| `Kaltoe.App` | WPF 실행 파일(`net11.0-windows`). 위젯 창(터미널/말풍선)·트레이(`NotifyIcon`)·설정 창·Win32 호출·이벤트 로그 조회·레지스트리. |

`Kaltoe.App/MascotData.cs`, `Assets/app.ico`, `Assets/tray.ico` 는 마스코트 생성 스크립트의 산출물이다(직접 고치지 않는다). 파일이 없어도 빌드는 되며, 실행 시 `idle` 프레임·기본 아이콘으로 대신한다.

## 빌드·테스트

.NET SDK 11 이 필요하다.

```sh
cd windows
dotnet build Kaltoe.sln
dotnet test Kaltoe.sln
```

맥·리눅스에서도 빌드·테스트는 된다(`EnableWindowsTargeting`). 앱 실행은 윈도우에서만 된다.

## 실행

윈도우에서:

```sh
dotnet run --project Kaltoe.App
```

데모 모드 — 가짜 데이터를 흘려 화면을 바로 확인한다(설정·기록 파일, 자동 실행 등록, 알림은 건드리지 않고, 실제 앱과 따로 돈다):

```sh
Kaltoe.exe --demo waiting|beforelunch|lunch|working|almost|done [--style terminal|bubble] [--font-size 8..32]
```

## 단일 exe 배포

```sh
dotnet publish windows/Kaltoe.App -c Release -r win-x64 --self-contained true \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true
```

산출물: `windows/Kaltoe.App/bin/Release/net11.0-windows/win-x64/publish/Kaltoe.exe` (런타임 포함, 약 70MB). 처음 실행할 때 네이티브 라이브러리를 임시 폴더에 풀기 때문에 첫 실행이 조금 느리다.

## 파일 위치

`%APPDATA%\Kaltoe\`

- `settings.json` — 설정, 위젯 위치(모양마다 따로)·표시 여부, 첫 실행 표시. 깨졌거나 값이 잘못됐으면 기본값으로 읽는다.
- `clockin.json` — 날짜별 출근 기록, 이미 띄운 알림(같은 날 중복 방지). 14일이 지난 기록은 지운다.
- `error.log` — 예기치 못한 오류(256KB 넘으면 비운다).

## 동작 요약

- **출근 감지**(유동 모드): 1초 타이머 + `SystemEvents.SessionSwitch`(잠금/해제/로그온) + `PowerModeChanged`(절전 해제). 타이머가 2초 이상 건너뛰면 그 시각부터 쓰기 시작한 것으로 본다. 앱이 `earliestStart` 이후에 켜졌고 오늘 기록이 없으면 System 이벤트 로그에서 절전 해제(Power-Troubleshooter 1)·부팅(Kernel-General 12)·로그온(Winlogon 7001) 중 가장 이른 시각을 찾는다(백그라운드, 10초 제한, 실패하면 `max(earliestStart, 앱 실행 시각)`).
- **시각 처리**: Core 는 시간대 변환 없이 "로컬 벽시계 시각"(`DateTime`)만 다룬다.
- **알림**: `NotifyIcon.ShowBalloonTip`. 앱이 켜져 있는 동안 시각을 지나는 순간 한 번만(지난 지 5초가 넘은 건 띄우지 않음).
- **자동 실행**: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\Kaltoe`. 첫 실행 때 한 번 켠다.
- **중복 실행 방지**: 이름 있는 뮤텍스. 이미 떠 있으면 조용히 종료.
- **위젯 모양**: 터미널(기본) / 말풍선. 글자 크기 8~32px (위젯 전체 비율 = 글자 크기 / 12).
