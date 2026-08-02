# CAGONG

공부 시간을 재는 macOS 앱. SwiftUI 네이티브.

## 실행

### Xcode

`Package.swift`를 열면 프로젝트로 열린다. ⌘R로 실행.

> SwiftPM은 `.app` 번들이 아니라 맨 실행파일을 만든다. `Info.plist`가 없으면 macOS가
> UI 앱으로 보지 않아 창이 뜨지 않으므로, [`CagongApp.swift`](Sources/Cagong/CagongApp.swift)의
> `AppDelegate`가 실행 직후 activation policy를 `.regular`로 올린다.
> 대신 이 경로로 실행하면 앱 아이콘은 붙지 않는다 — 번들이 없기 때문이다.

### Xcode 없이

```bash
./build.sh --run
```

`build/CAGONG.app`이 만들어진다. Command Line Tools만 있으면 빌드된다.

## 하루의 흐름

```
        ┌──────────────┐
        │  TODO 작성   │  비워둬도 "공부 시작" 눌림
        │              │  고정해둔 루틴은 미리 올라와 있다
        └──────┬───────┘
               ↓  공부 시작
        ┌──────────────┐
        │    측정      │  ← 앱을 껐다 켜도 여기로 돌아온다
        │              │     날짜·목표를 이 화면에서 바로 고친다
        └──────┬───────┘
               ↓  Zzz (안 눌러도 된다)
        ┌──────────────┐
        │  먼슬리 기록  │  날짜를 누르면 그날 TODO까지 보인다
        └──────────────┘
```

## 어느 날에 쌓이나

모든 날은 `DayRecord` 하나로 **동등하다.** "진행 중인 하루"라는 별도 상태는 없다.
지금 어느 날짜를 재고 있는지는 `StudyStore.measuringKey`가 들고 있고,
**저장하지 않는다** — 앱을 다시 켜면 항상 오늘부터다.

- **날짜는 이미 오늘로 정해져 있다.** 앱을 켜고 시작만 누르면 되고, 날짜를 만질 일이 없다
- 타이머 위의 **날짜 표시가 곧 선택기다.** 새벽까지 공부해 어제에 넣어야 할 때만 누른다
- 고를 수 있는 건 **오늘과 어제뿐.** 그제부터는 목록에 없다
- **자정을 넘겨도 고른 날짜 그대로다.** 30일 밤에 시작해 31일 02시까지 하면 4시간
  전부 30일에 들어간다. 자고 일어나 앱을 다시 켜면 오늘로 돌아온다

앱이 꺼져 있던 동안의 시간은 세지 않는다. 다시 켜면 멈춘 상태로 시작한다.

### 재는 도중 자정을 넘기면

멈추지도, 묻지도 않는다. 시간은 계속 고른 날짜에 쌓인다. 화면은 이렇게 바뀐다.

| | 자정 이후 |
|---|---|
| 날짜 칩 | `7월 31일 (금)` **그대로** — 그 날짜에 쌓고 있으니까 |
| `어제 기록 중` 배지 | **저절로 뜬다** — 가만히 있어도 그 날짜가 '어제'가 됐으므로 |
| 날짜 선택지 | 오늘 = 8월 1일 / 어제 = 7월 31일(선택됨)로 굴러간다 |

배지는 `TimelineView`가 직접 시간을 봐서 띄운다. store는 초 단위로 알리지 않으므로
(→ [성능](#성능--두-가지-규율)) 거기에 기대면 자정이 지나도 안 뜬다.

### Zzz는 잠그지 않는다

기록은 그대로 남고 **언제든 다시 시작할 수 있다.** 안 눌러도 아무 문제가 없다 —
날짜가 바뀌면 새 날이 알아서 생긴다. 시작 화면으로 돌아가는 표시일 뿐이다.

### 지난 날은 어디까지 고칠 수 있나

| | 오늘 | 어제 | 그 이전 |
|---|---|---|---|
| 시간 측정 | ✅ | ✅ | ❌ |
| TODO 글자 추가·삭제 | ✅ | ❌ | ❌ |
| 루틴 고정 | ✅ | ❌ | ❌ |
| 체크박스 | ✅ | ✅ | ✅ (먼슬리에서) |

체크만 언제든 열려 있다. 어제 항목을 오늘 끝냈다면 그걸 표시할 수 있어야 한다.

## 화면

**공부** — 상태 → 시간 → 시작/일시정지가 한 카드에 쌓인다. 왼쪽에 음료, 오른쪽에
테이프로 붙인 메모지, 위에 날짜와 현재 시각. 목표 막대는 시간 표시와 **정확히 같은
폭**(252pt)이라, 막대가 자기가 설명하는 숫자만큼만 뻗는다.

**먼슬리** — 날짜 칸마다 그날 총 공부시간이 들어가고 **그날의 목표** 기준으로 칸이
아래에서 채워진다. 상단에 월 합계·공부한 날·하루 평균. **날짜를 누르면** 그날의
시간, **몇 시에 앉아 몇 시에 접었는지**, TODO 목록·체크 상태가 그대로 나온다.

**설정** (⌘,) — 음료 / 테마 2탭.

## 공부 구간

총 시간만으로는 안 보이는 게 있다 — 아침형인지 새벽형인지, 한 번에 몰아 하는지
쪼개서 하는지. 그래서 **언제 앉아 언제 접었는지**를 따로 남긴다.

시작을 누르면 구간이 열리고 멈추면 닫힌다. 먼슬리에서 날짜를 누르면 나온다.

```
시작  09:14          마무리  18:30
─────────────────────────────────
09:14 – 11:02              1시간 48분
13:20 – 15:10              1시간 50분
17:56 – 18:30                   34분
```

`Zzz`를 눌렀으면 그 시각이 마무리가 된다. 구간의 끝보다 그쪽이 더 정확하다.

> **총합(`DayRecord.seconds`)은 구간에서 계산하지 않는다.** 계산하도록 바꾸면
> 구간 기록이 없는 옛 날짜가 전부 0이 되고, 이미 정확하게 도는 저장 경로를
> 다시 만들어야 한다. 구간은 "언제"만 담고 "얼마나"는 총합이 계속 맡는다.

파일에는 **열린 구간이 남지 않는다.** 쓰기 직전에 그 시점으로 닫아서 내보내므로
(`snapshotForWrite`) 앱이 갑자기 꺼져도 다음에 열 때 고칠 게 없다.

## 하루 목표

목표는 **날마다 다르다.** 시험 기간과 주말이 같을 리 없다. 그래서 설정에 하나로
박아두지 않고, 타이머 화면의 목표 문구(`목표 4시간 중 35%`)를 눌러 그날치를 정한다.

- 정하지 않은 날은 **마지막으로 쓴 값**을 따른다
- 목표를 바꾸면 기본값으로도 옮겨간다 — 요즘 그만큼 하고 있다는 뜻이므로 내일도
  거기서 시작하는 편이 맞다
- 다른 날의 목표는 건드리지 않는다

## 루틴 (고정한 할 일)

매일 똑같이 적지 않게 하려고 있다. 메모지에서 항목에 마우스를 올리면 **압정**이 나온다.

- 켜면 **다음 날 시작 화면에 이미 올라온 채로** 나온다. 오늘 필요 없으면 그 자리에서 지운다
- 넘어올 때 **체크는 풀린 채로**, 새 항목으로 온다 (어제 체크가 오늘 남지 않는다)
- 며칠 쉬어도 살아 있다 — **가장 최근에 기록이 있는 날**에서 가져온다
- 고정을 풀면 **그날의 평범한 할 일로 남는다.** 지워지지 않는다
- 같은 내용이 이미 그날에 있으면 중복해서 넣지 않는다

## 음료

컵에 담기는 음료를 고른다. 하루를 시작하는 화면과 설정 양쪽에서 바꿀 수 있다.
기본값은 Americano.

| 메뉴 | 온도 |
|---|---|
| Espresso | 뜨거움 |
| Matcha Latte | 아이스 |
| Lemonade | 아이스 |
| Americano | 뜨거움 |
| Cafe Latte | 뜨거움 |
| Chocolate Frappuccino | 아이스 |

배경을 지운 실제 사진을 **아무 보정 없이** 쓴다. 뜨거운 음료에만 김이 오른다.

## 배경 사진

**사진 카페** 테마는 실제 사진을 배경으로 쓴다. 어두운 부분만 그림자 리프트로 살짝
들어올릴 뿐, 채도·대비는 건드리지 않는다. 사진이 밝든 어둡든 글자가 읽히도록 카드와
버튼은 유리(`GlassSurface`)로 덮고, 그 위에 옅은 틴트를 얹는다.

| 장면 |
|---|
| 파리의 여름 |
| 몽마르트 카페 |
| 도쿄 노을 |
| 센강의 밤 |

장면은 타이머 화면의 좌우 화살표나 `⌘←` `⌘→`로 넘긴다.

### 사진 추가

설정의 **사진 추가**로 고르거나, 아래 폴더에 JPEG/PNG를 넣고 앱을 다시 켜면 된다.

```
~/Library/Application Support/Cagong/Backgrounds/
```

출처와 라이선스는 [CREDITS.md](CREDITS.md)에 있다.

## 테마

설정에서 고르면 바로 적용된다. 기본값은 사진 카페.

| | |
|---|---|
| **사진 카페** | 실제 카페 사진 위에서. 좌우로 장면을 넘긴다 |
| **웜 카페** | 크래프트 종이와 에스프레소. 창가 자리의 오후 |
| **심야 스탠드** | 불 끄고 스탠드 하나만. 앰버 조명이 번지는 책상 |

## 인터랙션

모션은 하나씩 이유가 있다.

- **김** — 측정 중일 때만 음료에서 올라온다. 숫자를 읽지 않아도 상태가 보인다.
  캔버스 위쪽 여백에 겹쳐 그리므로 잔을 아래로 밀어내지 않는다
- **스프링** — 선형 easing을 쓰지 않는다. 버튼은 가볍고 빠르게(`response: 0.26`),
  카드는 질량이 있어 두 배 느리게(`0.55`) 움직인다
  ([`Motion`](Sources/Cagong/Theme/DesignSystem.swift))
- **체크** — 획이 그려지듯 나타난다 (`trim` 0→1)
- **숫자** — 바뀐 자리만 굴러간다 (`contentTransition(.numericText())`)
- **화면 전환** — 공부 ↔ 먼슬리로 넘어갈 때 음료가 헤더 자리로 이어진다
  (`matchedGeometryEffect`)

동작 줄이기(`prefers-reduced-motion`)를 켜면 앰비언트 모션이 멈춘다.

## 타이포그래피

라틴 글자와 숫자는 **American Typewriter**, 한글은 **Apple SD Gothic Neo**로 명확히
갈라 쓴다. 타이프라이터에 한글 꼴이 없으므로 폴백에 맡기지 않는다. 둘 다 macOS 기본
폰트라 별도 설치가 없다.

## 구조

```
Sources/Cagong/
├── CagongApp.swift              @main, 창 설정, activation policy
├── Model/
│   ├── Models.swift             데이터 타입, 날짜 키, 시간 표기
│   ├── Drink.swift              음료 6종 + 사진 보관소
│   ├── BundledResources.swift   실행 형태별 리소스 경로 탐색
│   └── StudyStore.swift         단일 상태 저장소 + JSON 영속화
├── Theme/
│   ├── Theme.swift              테마 3종과 팔레트
│   ├── DesignSystem.swift       모션·타이포·버튼·카드 토큰
│   ├── ThemeBackground.swift    종이·스탠드 장면, 테마 미리보기
│   └── PhotoBackground.swift    사진 보관소, 사진 배경
├── Resources/
│   ├── AppIcon.icns
│   ├── Backgrounds/             배경 사진 4장
│   └── Drinks/                  음료 누끼 6장
└── Views/
    ├── RootView.swift           셸, 상단 바, 화면 전환, 장면 넘기기
    ├── TodoSetupView.swift      하루 시작 전
    ├── TimerView.swift          측정
    ├── MonthlyView.swift        월별 기록 + 하루 상세
    ├── SettingsView.swift       설정 (2탭)
    └── Components/              시간 표시, 음료 잔, 김, 체크, 메모지, 음료 고르기
```

기록은 `~/Library/Application Support/Cagong/study-data.json`에 쌓인다.

## 성능 — 두 가지 규율

클릭이 씹히는 문제를 재서 고치며 세운 규칙이다. 새 기능을 붙일 때 이 둘을 깨면
증상이 바로 돌아온다.

### 1. 디스크를 기다리지 않는다

저장은 **백그라운드 직렬 큐**에서 한다. 메인 스레드는 `AppData`(값 타입)를 복사해
넘기기만 한다 — 0.04ms. 예전에는 클릭마다 동기로 파일 전체를 써서 9.5ms를
잡아먹었고, 기록이 3년 쌓이면 27ms로 한 프레임(16.6ms)을 넘겼다.

**미루지는 않는다.** 사용자가 한 행동은 다음 런루프 턴에 바로 쓰인다. 몇 초씩
묶어두면 딱 그만큼이 유실 구간이 되는데, 빨라지는 건 없다. 같은 턴에 몰린 변경만
`DispatchWorkItem` 취소로 하나에 합쳐진다.

측정 중 흐르는 시간만 5초에 한 번 반영한다. 그리고 아래 지점에서는 **동기로** 확실히 쓴다.

| 지점 | |
|---|---|
| 일시정지 · Zzz | `flush()` |
| 앱 종료 · 다른 앱으로 전환 | `flush()` |

### 2. 매초 `@Published`를 건드리지 않는다

`RootView`·`TimerView`·`MonthlyView`가 모두 `@EnvironmentObject store`를 본다.
그래서 store가 변경을 한 번 알리면 **트리 전체가 다시 평가된다** — 배경 사진,
메모지, 유리 표면 8곳까지.

흐르는 시간은 `data`에 넣지 않고 `runStartedAt`(시작 시각) 하나로 표현한다.
`seconds(for:at:)`는 읽기만 하는 순수 함수이고, 화면은 `TimelineView`가 자기 안쪽만
굴리며 그 값을 다시 읽어간다. `data`가 바뀌는 건 멈출 때·날짜를 바꿀 때뿐이다.

측정 중 알림 횟수는 **초당 3회에서 0회**가 됐다. `StoreTest`가 이걸 검사한다.

> 같은 값을 다시 넣어도 `@Published`는 변경을 알린다. `start()`에서 `closed = false`를
> 무조건 쓰지 않고 이미 열려 있으면 건너뛰는 이유다.

### 클릭 영역

SwiftUI는 **그려진 것**만 클릭 영역으로 잡는다. `padding`이나 `frame`으로 만든 여백은
포함되지 않고, 유리 배경은 `allowsHitTesting(false)`라 아예 빠진다. 그래서 38×38
화살표 버튼에서 실제로 눌리는 건 가운데 글리프뿐이었다 — 보이는 면적의 7%.

`PressableStyle` · `PrimaryButtonStyle` · `GhostButtonStyle` **세 곳에 `contentShape`를
걸어** 전부 해결했다. 앱의 모든 버튼이 이 셋 중 하나를 쓰므로, 새 버튼도 스타일만
붙이면 따라온다.

## 이미지 규격

사진마다 크기와 여백이 다르면 화면에서 위치가 조금씩 달라진다. 그래서 미리 맞춰둔다.

| | 규격 | 이유 |
|---|---|---|
| 음료 | 640×640 캔버스, 내용 높이 516, 하단 여백 6 | 모든 잔이 같은 바닥에 놓인다. 위쪽 18%는 김 자리 |
| 배경 | 1600×1000 (16:10) 가운데 크롭 | 장면을 넘길 때 잘리는 양이 같다. 기본 창보다 넓어 가로만 잘린다 |

### 배경은 `.background`로 넣는다

`ZStack` 형제로 두면 배경 사진이 레이아웃에 참여한다. 사진은 화면을 채우려고
제안된 크기를 넘어서 커지는데, 그러면 ZStack도 같이 부풀고 상단 바가 부푼 영역
기준으로 중앙 정렬돼 **화면 위로 밀려 올라간다.** 사진 비율마다 증상이 다르게
나타나서 원인을 찾기 어렵다. `.background`는 콘텐츠 크기에 영향을 주지 않으므로
이 경로가 막힌다. 사진 자체도 `GeometryReader`로 가둬 `clipped()`한다.

## 설정 항목 추가하기

`AppSettings`는 모든 키를 `decodeIfPresent`로 읽고, 열거형은 **원시 문자열로 읽어
fallback**시킨다. 그래서 필드를 추가하거나 목록에서 값을 빼도 기존 저장 파일이
깨지지 않는다 — 열거형을 직접 디코딩하면 없어진 값을 만났을 때 예외가 나고
기록 전체가 초기값으로 밀린다.

`DayRecord`도 마찬가지다. `goalMinutes`(날짜별 목표), `TodoItem.pinned`(루틴),
`sessions`(공부 구간)는 나중에 붙인 필드인데, 옛 파일에 그 키가 없어도 기본값으로 읽힌다.

탭을 추가하려면 `SettingsTab`에 case를 넣고 `SettingsContent`에 분기를 붙인다.
확장 지점 주석이 [`SettingsView.swift`](Sources/Cagong/Views/SettingsView.swift)에 있다.

## 도구

앱 번들에는 들어가지 않는다. 앱 소스 전체와 함께 컴파일해서 쓴다.
`@main`이 둘이 되지 않도록 `CagongApp.swift`만 뺀다.

> `find` 결과는 `$(...)` 안에 그대로 두어야 한다. zsh는 변수에 담은 값은
> 단어로 쪼개지 않으므로 `SRC=$(find ...)` 후 `$SRC`로 넘기면 경로가
> 한 덩어리로 전달돼 실패한다.

**동작 검증** (81개 — 날짜 귀속, 저장 시점, 목표, 루틴, 공부 구간, 옛 형식 이관)

```bash
swiftc -parse-as-library -target arm64-apple-macos14.0 -o /tmp/storetest $(find Sources/Cagong -name '*.swift' ! -name 'CagongApp.swift') Tools/StoreTest.swift && /tmp/storetest
```

**화면을 오프스크린으로 렌더링** — 데스크톱을 캡처하지 않고 UI를 검수한다

```bash
swiftc -parse-as-library -target arm64-apple-macos14.0 -o /tmp/snapshot $(find Sources/Cagong -name '*.swift' ! -name 'CagongApp.swift') Tools/Snapshot.swift && /tmp/snapshot ./docs
```

`ImageRenderer`는 `TextField`·`Slider`·`Toggle` 같은 AppKit 기반 컨트롤을 래스터화하지
못해 노란 막대로 그리고, `ScrollView` 내용도 그리지 않는다. 스냅샷에서 그렇게 보이는
건 렌더러 한계이고 실제 앱에서는 정상이다.

**음료 사진 규격 맞추기** — 알파 여백을 잘라 640×640 캔버스에 하단 정렬

```bash
swiftc -parse-as-library -target arm64-apple-macos14.0 -o /tmp/normalize Tools/NormalizeDrinks.swift && /tmp/normalize Sources/Cagong/Resources/Drinks
```

**배경 사진 규격 맞추기** — 가운데를 16:10으로 잘라 1600×1000으로

```bash
swiftc -parse-as-library -target arm64-apple-macos14.0 -o /tmp/normalizebg Tools/NormalizeBackgrounds.swift && /tmp/normalizebg Sources/Cagong/Resources/Backgrounds
```

**앱 아이콘 만들기** — 음료 누끼에서 `.icns` 생성 (10개 해상도)

```bash
swiftc -parse-as-library -target arm64-apple-macos14.0 -o /tmp/makeicon Tools/MakeIcon.swift && /tmp/makeicon Sources/Cagong/Resources/Drinks/matcha-latte.png Sources/Cagong/Resources
```

Dock에서 아이콘이 바로 안 바뀌면 LaunchServices 캐시 때문이다. `killall Dock`으로 갱신된다.

## 요구사항

macOS 14 이상.
