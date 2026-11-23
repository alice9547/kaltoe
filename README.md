<p align="center"><img src="Resources/AppIcon-1024.png" width="128" alt="칼퇴 아이콘"></p>

# 칼퇴 (Kaltoe)

출근 시각이 매일 달라도 퇴근 시각을 알아서 계산해 주는 macOS 위젯입니다.
9시 이후 맥을 처음 깨운 시각을 출근으로 보고, 9시간 뒤를 퇴근으로 잡아 남은 시간을 보여 줍니다.

```
● ● ●            kaltoe — zsh
$ sudo 퇴근 --force
Permission denied: 3h 12m 08s left
[############........] 64%
in 09:16 → out 18:16
# 반 넘었다. 나머지는 미래의 내가▋
```

## 기능

- **출근 자동 감지**: 9시 이후 첫 잠금 해제(깨우기) 시각을 그날 출근으로 기록합니다. 9시 전부터 쓰고 있었으면 09:00으로 처리합니다.
- **사후 복구**: 앱이 꺼져 있던 날은 시스템 깨우기 기록(`pmset -g log`)에서 출근 시각을 찾아 채웁니다.
- **플로팅 위젯**: 항상 최상단에 뜨는 터미널 모양 창입니다. 드래그로 옮길 수 있고 위치를 기억합니다. 빨간 점을 누르면 숨겨집니다.
- **메뉴바**: `18:16까지 3h 12m` 한 줄과 위젯 보이기/숨기기, 자동 실행 토글, 종료 메뉴가 있습니다.
- **마스코트**: 주황색 픽셀 캐릭터가 남은 시간에 따라 졸고, 깜빡이고, 뛰고, 춤춥니다.
- **알림**: 퇴근 10분 전과 정각에 알려 줍니다.
- **로그인 시 자동 실행**: 처음 실행할 때 켜지고, 메뉴에서 끌 수 있습니다.

## 설치

macOS 14 이상과 Xcode(또는 Swift 툴체인)가 필요합니다.

```sh
git clone https://github.com/alice9547/kaltoe.git
cd kaltoe
Scripts/build-app.sh --install
```

`/Applications/Kaltoe.app`으로 설치되고 바로 실행됩니다. 처음 실행하면 알림 권한을 묻습니다.
`--install` 없이 실행하면 `dist/Kaltoe.app`만 만듭니다.

## 개발

```sh
swift build
swift test
swift run Kaltoe --demo working   # waiting | working | almost | done
```

`--demo`는 가짜 데이터로 각 단계의 화면을 확인하는 모드입니다.
`swift run`으로 띄우면 앱 번들이 아니라서 알림과 자동 실행은 동작하지 않습니다.

## 구조

| 경로 | 내용 |
|---|---|
| `Sources/Kaltoe/Contracts.swift` | 코어와 UI가 공유하는 상태(`WorkdaySnapshot`)와 규칙 상수 |
| `Sources/Kaltoe/Core/` | 출근 감지, 기록 저장, 깨우기 기록 해석, 알림, 로그인 항목 |
| `Sources/Kaltoe/UI/` | 플로팅 창, 터미널 뷰, 마스코트, 메뉴바 |
| `Scripts/` | 앱 번들 빌드, 아이콘 생성 |

근무 시간(9시간)과 출근 인정 시작 시각(9시)은 `Contracts.swift`의 `WorkRules`에서 바꿀 수 있습니다.

## 알아둘 점

- 화면이 잠긴 동안의 깨어남은 출근으로 잡지 않습니다.
- 하루 출근 기록은 한 번 정해지면 그날은 바뀌지 않습니다. 기록은 이 맥의 앱 설정에만 저장됩니다.
