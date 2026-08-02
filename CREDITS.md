# 사진 출처

## 배경 사진

사용자가 직접 고른 Unsplash 사진 4장.
`Tools/NormalizeBackgrounds`로 가운데를 16:10으로 잘라 1600×1000으로 통일했고,
앱에서 어두운 부분만 살짝 밝혀 표시한다.

| 장면 | 파일 | 사진가 | 라이선스 |
|---|---|---|---|
| **파리의 여름** | `paris-summer.jpg` | Anaïs Lauret | Unsplash License |
| **몽마르트 카페** | `montmartre-cafe.jpg` | Marloes Hilckmann | Unsplash License |
| **도쿄 노을** | `tokyo-dusk.jpg` | Bing Hui Yau | Unsplash License |
| **센강의 밤** | `seine-night.jpg` | Fred Pixlab | Unsplash License |

## 음료 사진

배경을 지운(누끼) 상태로 쓴다. 보정은 하지 않는다.
`Tools/NormalizeDrinks`로 640×640 캔버스에 하단 정렬해 잔 위치를 통일했다.

| 메뉴 | 파일 | 사진가 | 라이선스 |
|---|---|---|---|
| **Espresso** | `espresso.png` | Nathan Dumlao | Unsplash License |
| **Matcha Latte** | `matcha-latte.png` | Olena Bohovyk | Unsplash License |
| **Lemonade** | `lemonade.png` | Svitlana | Unsplash License |
| **Americano** | `americano.png` | epSos.de | CC BY 2.0 |
| **Cafe Latte** | `cafe-latte.png` | Brigitte Tohm | CC0 |
| **Chocolate Frappuccino** | `choco-frappuccino.png` | RegionVisitor90 | CC0 |

## 라이선스 정리

- **Unsplash License** — 상업적 이용을 포함해 무료로 쓸 수 있고 허가가 필요 없다.
  저작자 표시는 의무가 아니지만 위에 남겨둔다.
- **CC0** — 조건 없이 쓰고 고치고 배포할 수 있다.
- **CC BY 2.0** — 저작자 표시가 필요하다.

## 사진 바꾸기·추가하기

빌드에 포함하려면 소스 트리에 넣고 `PhotoLibrary`(배경) 또는 `Drink.all`(음료)에 등록한다.

```
Sources/Cagong/Resources/Backgrounds/   배경
Sources/Cagong/Resources/Drinks/        음료 (알파 채널 있는 PNG)
```

빌드하지 않고 배경만 추가하려면 아래 폴더에 넣으면 앱이 바로 읽는다.

```
~/Library/Application Support/Cagong/Backgrounds/
```
