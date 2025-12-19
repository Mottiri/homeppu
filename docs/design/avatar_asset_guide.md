# アバターアセット生成ガイド

## 共通仕様

| 項目 | 値 |
|------|---|
| キャンバスサイズ | **512x512px** |
| ファイル形式 | PNG（透過背景） |
| アンカーポイント | 中央揃え |
| 顔の中心位置 | X: 256px, Y: 280px |
| 画風 | アニメ調、かわいい、パステルカラー |

---

## レイヤー順序（下から上へ）

```
7. accessory.png  ← 最前面
6. hair_front.png
5. eyebrow.png
4. eyes.png
3. nose.png
2. mouth.png
1. face.png       ← 輪郭・肌
0. hair_back.png  ← 最背面
```

---

## 共通プロンプト（ベース）

```
chibi anime style avatar part, cute, soft colors, 
simple design, white background, 
centered composition, 512x512 canvas,
facing front, no shading, flat colors
```

---

## パーツ別プロンプト

### 1. 髪型（hair）

**前髪パーツ（hair_front）**
```
chibi anime style hair bangs only, 
cute fluffy bangs covering forehead,
[COLOR] hair color,
transparent background, top of head visible,
centered at top, 512x512 canvas,
front view, no face, hair part only,
soft anime style, simple flat colors
```

**後ろ髪パーツ（hair_back）**
```
chibi anime style back hair only,
[STYLE: long/short/ponytail/twin tails/bun],
[COLOR] hair color,
transparent background,
centered, 512x512 canvas,
back hair layer, no face visible,
soft anime style, simple flat colors
```

**カラーバリエーション例**:
- brown, dark brown, blonde, pink, blue, purple, green, orange, rainbow gradient, silver

**スタイルバリエーション例**:
- long straight, short bob, ponytail, twin tails, messy, wavy, bun

---

### 2. 輪郭・肌（face）

```
chibi anime style face outline only,
[SKIN TONE] skin color,
round cute face shape, small ears visible,
no hair, no eyes, no mouth, blank face,
transparent background,
face centered at 256x280 position,
512x512 canvas, front view,
soft anime style, simple flat colors
```

**肌色バリエーション例**:
- fair skin, light skin, medium skin, tan skin, dark skin, pale white, warm beige

---

### 3. 目（eyes）

```
chibi anime style eyes only,
[STYLE] eye shape,
[COLOR] eye color,
both eyes, symmetrical, cute expression,
transparent background,
eyes positioned at upper face area,
512x512 canvas, centered,
sparkly anime eyes, simple flat colors
```

**スタイルバリエーション例**:
- round big eyes, almond shaped, droopy cute, cat eyes, sparkling eyes

**カラーバリエーション例**:
- brown, blue, green, purple, pink, red, golden, heterochromia

---

### 4. 眉毛（eyebrow）

```
chibi anime style eyebrows only,
[STYLE] eyebrow shape,
[COLOR] eyebrow color,
both eyebrows, symmetrical,
transparent background,
positioned above eyes area,
512x512 canvas, centered,
simple line art style
```

**スタイルバリエーション例**:
- thin curved, thick straight, arched, gentle, sharp, worried

---

### 5. 鼻（nose）

```
chibi anime style nose only,
simple small [STYLE] nose,
centered on face,
transparent background,
512x512 canvas,
minimal cute anime nose,
simple line or dot style
```

**スタイルバリエーション例**:
- small dot, tiny triangle, simple line, button nose

---

### 6. 口（mouth）

```
chibi anime style mouth only,
[EXPRESSION] expression,
[STYLE] mouth shape,
transparent background,
positioned at lower face area,
512x512 canvas, centered,
simple cute anime mouth
```

**表情バリエーション例**:
- smiling, open smile, small smile, neutral, surprised, happy grin

---

## 位置ガイド（512x512キャンバス）

```
┌────────────────────────────┐
│          髪（前）           │ Y: 0-150
│                            │
│    ┌──────────────────┐    │
│    │      眉毛        │    │ Y: 180-210
│    │      目          │    │ Y: 220-280
│    │      鼻          │    │ Y: 290-320
│    │      口          │    │ Y: 340-380
│    │                  │    │
│    │    輪郭（肌）     │    │ Y: 150-450
│    └──────────────────┘    │
│                            │
│          髪（後ろ）         │ Y: 100-512
└────────────────────────────┘
        X: 中央 256px
```

---

## 生成時のTips

1. **同じシード値を使う**: 一貫性のため同じseedで生成
2. **バッチ生成**: 同じプロンプトで複数生成し、良いものを選ぶ
3. **色指定は具体的に**: `pink`より`soft pastel pink`が良い
4. **ネガティブプロンプト**: `realistic, 3D, detailed shading, complex`

---

## ネガティブプロンプト（共通）

```
realistic, 3D, photorealistic, 
complex shading, detailed shadows,
multiple characters, full body,
text, watermark, signature,
blurry, low quality
```

---

## 推奨生成ツール

| ツール | 特徴 |
|--------|------|
| Midjourney | 高品質、有料 |
| DALL-E 3 | 指示に忠実 |
| Stable Diffusion | 無料、カスタマイズ可 |
| Leonardo.ai | 無料枠あり |

---

## 生成後の加工

1. **透過処理**: 背景を透明に（remove.bg等）
2. **位置調整**: 全パーツを同じ位置に揃える
3. **リサイズ**: 512x512に統一
4. **ファイル名規則**: `{パーツ}_{バリエーション番号}.png`
   - 例: `hair_front_01.png`, `eyes_03.png`
