# 칼퇴 공통 명세 (맥·윈도우 공통)

두 플랫폼의 앱은 이 문서대로 같은 동작·같은 문구를 낸다. 플랫폼별 구현 방법만 다르다.

## 1. 설정

| 키 | 타입 | 기본값 | 뜻 |
|---|---|---|---|
| `mode` | `flexible` \| `fixed` | `flexible` | 출근 방식 |
| `flexible.earliestStart` | `HH:mm` | `09:00` | 이 시각 이후 처음 컴퓨터를 쓴 시각이 출근. 이 시각 전부터 쓰고 있었으면 이 시각 |
| `flexible.workMinutes` | 정수(분) | `540` | 출근부터 퇴근까지(점심 포함). 허용 60~960 |
| `fixed.start` | `HH:mm` | `08:30` | 고정 출근 시각 |
| `fixed.end` | `HH:mm` | `17:30` | 고정 퇴근 시각. `fixed.start` 보다 뒤여야 함 |
| `lunch.enabled` | bool | `false` | 점심 단계 사용 |
| `lunch.start` | `HH:mm` | `11:30` | |
| `lunch.end` | `HH:mm` | `13:00` | `lunch.start` 보다 뒤여야 함 |
| `notify.lunch` | bool | `true` | 점심 시작 알림 (`lunch.enabled` 일 때만) |
| `notify.beforeEnd` | bool | `true` | 퇴근 10분 전 알림 |
| `notify.end` | bool | `true` | 퇴근 정각 알림 |

- 잘못된 값(끝이 시작보다 이름 등)은 저장하지 않고 설정 화면에 오류를 보여 준다.
- 설정이 바뀌면 즉시 화면과 알림 예약에 반영한다.
- 모든 시각은 로컬 시간대의 "오늘" 기준이다. 자정을 넘기는 근무는 지원하지 않는다.

## 2. 출근·퇴근 시각

**유동 모드 (`flexible`)**
1. 하루에 출근 기록은 하나. 정해지면 그날은 바뀌지 않는다(아래 "다시 감지" 제외). 날짜별로 저장, 14일 지난 기록은 삭제.
2. 오늘 기록이 없고, 지금 ≥ `earliestStart`, 화면이 잠겨 있지 않으면 → 출근 = max(`earliestStart`, 활성화 시각).
   활성화 시각 = 사용자가 마지막으로 컴퓨터를 쓰기 시작한 시각(잠금 해제·절전 해제·로그온·앱 실행 중 가장 최근).
3. 지금 < `earliestStart` 이면 기록하지 않는다.
4. 화면이 잠긴 동안에는 기록하지 않는다.
5. 날짜가 바뀌면 새 날이다.
6. 사후 복구: 앱이 `earliestStart` 이후에 실행됐고 오늘 기록이 없으면, 시스템 기록에서 `earliestStart`~지금 사이 가장 이른 "사용자 깨움/로그온/부팅" 시각을 찾아 출근으로 한다. 없으면 `earliestStart`. 조회 실패 시 max(`earliestStart`, 앱 실행 시각). 조회가 끝날 때까지 규칙 2 기록은 보류.
7. 퇴근 = 출근 + `workMinutes`.
8. "오늘 출근 다시 감지": 오늘 기록을 지우고 규칙 6부터 다시 수행한다.

**고정 모드 (`fixed`)**
- 출근 = 오늘 `fixed.start`, 퇴근 = 오늘 `fixed.end`. 컴퓨터 사용 여부와 무관하다. 감지·저장·복구를 하지 않는다.
- 지금 < `fixed.start` 이면 출근 전.

## 3. 단계와 스냅샷

스냅샷 필드: `now`, `clockIn?`, `clockOut?`, `lunchStart?`, `lunchEnd?`(점심이 유효할 때만), `phase`, `target?`(지금 세고 있는 목표 시각), `remaining`(target 까지 초, 없으면 0), `remainingToClockOut`(퇴근까지 초, 0 이상), `overtime`(퇴근 후 지난 초), `progress`(0~1, (now−clockIn)/(clockOut−clockIn)).

점심이 "유효"하려면: `lunch.enabled` 이고 `clockIn < lunchEnd` 이고 `lunchStart < clockOut`.

단계 결정(위에서부터 먼저 맞는 것):

| 조건 | phase | target |
|---|---|---|
| 출근 시각 없음(유동: 기록 없음 / 고정: 지금 < 출근) | `waiting` | 고정이면 출근 시각, 유동이면 없음 |
| 지금 ≥ 퇴근 | `done` | 없음 |
| 점심 유효, 지금 < lunchStart | `beforeLunch` | lunchStart |
| 점심 유효, lunchStart ≤ 지금 < lunchEnd | `lunch` | lunchEnd |
| 퇴근까지 ≤ 10분 | `almostDone` | 퇴근 |
| 그 외 | `working` | 퇴근 |

## 4. 문구

시간 표기: 남은 시간 긴 형식 `3h 12m 08s`(1시간 미만 `12m 08s`), 짧은 형식 `3h 12m`(1시간 미만 `12m`, 1분 미만 `42s`). 시각 `HH:mm` 24시간제. 진행률 바는 20칸 `[#####...............] 27%` (progress 기준).

### 위젯 (터미널)

`waiting` — 유동
```
$ whoami
아직 출근 전인 사람
# waiting for first unlock after 09:00...
```
`waiting` — 고정
```
$ whoami
아직 출근 전인 사람
# 출근 08:30 까지 12m
```
`beforeLunch`
```
$ npm install 점심
installing... 42m 08s left
[#####...............] 27%
in 08:30 → out 17:30
# 점심 11:30 · 퇴근까지 5h 42m
```
`lunch`
```
$ sleep 점심
점심 끝까지 18m 08s
[########............] 41%
in 08:30 → out 17:30
# 지금은 밥이 P0 입니다
```
`working`
```
$ sudo 퇴근 --force
Permission denied: 3h 12m 08s left
[############........] 64%
in 09:16 → out 18:16
# <주석>
```
주석(위에서부터 먼저 맞는 것): 점심 미사용이고 지금 12:00~12:59 → `# 점심: 일단 밥부터 먹고 생각하자` / progress<0.25 → `# 아직 컴파일 중...` / <0.50 → `# it works on my machine` / <0.75 → `# 반 넘었다. 나머지는 미래의 내가` / 그 외 → `# 거의 다 왔다. 금요일 배포만 하지 말자`

`almostDone`
```
$ git commit -m "퇴근 준비"
9m 05s left
[###################.] 98%
in 09:16 → out 18:16
# 지금 배포하면 안 됩니다
```
`done`
```
$ exit
Process finished with exit code 0
퇴근하세요! out 18:16
# 야근 중 +0h 12m
```
(야근 줄은 overtime ≥ 60초일 때만)

색: 프롬프트 `$` #28C840, 명령 #F2F2F7, 출력 #C7C7CC, 남은 시간 강조 #F28C5A, 주석 #6E6E73, done 의 첫 출력 줄 #28C840. 배경 #1B1B1F(불투명도 0.94), 상단 바 #2A2A30, 신호등 점 #FF5F57 #FEBC2E #28C840, 제목 `kaltoe — zsh` #8E8E93. 마지막 줄 끝에 깜빡이는 블록 커서.

### 메뉴바(맥) / 트레이 툴팁(윈도우) 한 줄

| phase | 문구 |
|---|---|
| `waiting` | `출근 전` |
| `beforeLunch` | `점심까지 42m` |
| `lunch` | `점심 끝까지 18m` |
| `working`, `almostDone` | `18:16까지 3h 12m` |
| `done` | `퇴근! +12m` (overtime 1분 미만이면 `퇴근!`) |

### 메뉴 (메뉴바/트레이 아이콘)

1. `출근 09:16` (비활성. 없으면 `출근 기록 없음`)
2. `퇴근 18:16` (비활성. 출근 없으면 생략)
3. `점심 11:30–13:00` (비활성. `lunch.enabled` 일 때만)
4. 구분선
5. `위젯 숨기기` / `위젯 보이기`
6. `설정…`
7. `오늘 출근 다시 감지` (유동 모드일 때만)
8. `로그인 시 자동 실행` (체크)
9. 구분선
10. `칼퇴 종료`

### 알림

| 시점 | 조건 | 문구 |
|---|---|---|
| lunchStart | `notify.lunch`, 점심 유효 | `점심 시간입니다 — npm install 점심` |
| 퇴근 10분 전 | `notify.beforeEnd` | `퇴근 10분 전 — 지금 배포하면 안 됩니다` |
| 퇴근 정각 | `notify.end` | `Process finished with exit code 0 — 퇴근하세요` |

이미 지난 시각은 알리지 않는다. 같은 날 같은 알림은 한 번만.

## 5. 설정 화면

창 하나, 제목 `칼퇴 설정`.
- 출근 방식: `유동 (처음 켠 시각)` / `고정 (정해진 시각)` 둘 중 선택
  - 유동: `출근 인정 시작` 시각, `근무 시간` 시간·분
  - 고정: `출근` 시각, `퇴근` 시각
- 점심: 사용 체크, 시작·끝 시각
- 알림: 점심 시작 / 퇴근 10분 전 / 퇴근 정각 체크 3개
- 로그인 시 자동 실행 체크
- 아래에 미리보기 한 줄: 현재 입력값으로 계산한 `출근 08:30 · 점심 11:30–13:00 · 퇴근 17:30` (유동 모드에서 오늘 기록이 없으면 `출근 —`)
- 값이 유효하면 바꾸는 즉시 저장·반영. 유효하지 않으면 빨간 글씨로 이유를 보여 주고 저장하지 않는다.

## 6. 마스코트

하얀 말티즈 강아지 픽셀 캐릭터. 그림 데이터의 원본은 `shared/mascot.json` 하나이고, 생성 스크립트가 플랫폼별 소스(`Sources/Kaltoe/UI/MascotData.swift`, `windows/Kaltoe.App/MascotData.cs`)를 만든다.

데이터 형식: `width`, `height`(픽셀 격자 크기), `palette`(문자 → `#RRGGBB`), `frames`(이름 → 문자열 배열, 한 문자열이 한 줄, `.` 은 투명).
프레임 이름(고정): `idle`, `blink`, `breathe`, `sleep`, `eat1`, `eat2`, `sparkle`, `hop`, `danceL`, `danceR`.

기분(mood)과 재생:

| phase | mood | 프레임 재생 |
|---|---|---|
| `waiting` | `sleep` | `sleep` 고정 + 머리 위로 떠오르는 `z` 글자 |
| `beforeLunch`, `working` | `idle` | `idle`↔`breathe` 0.6초 간격, 4초마다 `blink` 0.15초 |
| `lunch` | `eat` | `eat1`↔`eat2` 0.4초 |
| `almostDone` | `sparkle` | `sparkle`↔`hop` 0.3초 |
| `done` | `dance` | `danceL`↔`danceR` 0.4초 + 주변 색종이 픽셀 |

마스코트를 클릭하면 한 번 점프한다. 그릴 때 안티에일리어싱 없이 픽셀이 또렷해야 한다.
