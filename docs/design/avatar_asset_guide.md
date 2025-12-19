# アバターアセット生成ガイド（確定版）

## 作成方式

**髪型と輪郭はセットで生成**（位置ズレ防止のため）

```
パーツ構成:
・髪型+輪郭（セット） ← 1枚の画像
・目
・眉毛
・鼻
・口
```

---

## 共通仕様

| 項目 | 値 |
|------|---|
| キャンバスサイズ | **512x512px** |
| ファイル形式 | PNG（透過背景） |
| 顔の中心位置 | X: 256px, Y: 280px |

---

## STEP 1: 髪型+輪郭（セット）を作成

**髪型と顔の輪郭を一緒に生成します。これがベースになります。**

### プロンプト

```
chibi anime style character head,
[STYLE] hairstyle, [COLOR] hair color,
round cute face shape, small cute ears,
[SKIN] skin tone,

completely blank face,
no eyes, no eyebrows, no nose, no mouth,
face area left empty for layering,

512x512 canvas,
transparent background,
front view facing camera,
soft flat colors, no shading,
simple clean anime style
```

### ネガティブプロンプト
```
eyes, eyebrows, nose, mouth, expression,
realistic, 3D, detailed shading, complex
```

### バリエーション例

#### ロングストレート（黒髪）
```
chibi anime style character head,
long straight hairstyle, black hair color,
round cute face shape, small cute ears,
fair skin tone,
blank face, no eyes no nose no mouth,
512x512, transparent background, soft flat colors
```

#### ショートボブ（茶髪）
```
chibi anime style character head,
short bob hairstyle, brown hair color,
round cute face shape, small cute ears,
fair skin tone,
blank face, no eyes no nose no mouth,
512x512, transparent background, soft flat colors
```

#### ツインテール（ピンク）
```
chibi anime style character head,
twin tails hairstyle, pink hair color,
round cute face shape, small cute ears,
fair skin tone,
blank face, no eyes no nose no mouth,
512x512, transparent background, soft flat colors
```

#### レインボー（課金限定）
```
chibi anime style character head,
long wavy hairstyle, rainbow gradient hair color,
round cute face shape, small cute ears,
fair skin tone,
blank face, no eyes no nose no mouth,
512x512, transparent background, soft flat colors
```

### 髪型リスト
- short bob（ショートボブ）
- long straight（ロングストレート）
- twin tails（ツインテール）
- ponytail（ポニーテール）
- messy short（くせ毛ショート）
- wavy long（ウェーブロング）
- bun（お団子）
- side ponytail（サイドポニー）

### 髪色リスト
- 無料: black, brown, dark brown, blonde
- 課金: pink, blue, purple, green, silver, rainbow gradient

### 肌色リスト
- fair skin（明るい肌）
- light skin（普通肌）
- tan skin（日焼け肌）
- dark skin（褐色肌）

---

## STEP 2: 目を作成

**髪型+輪郭の画像を参照して、同じ位置に目を配置**

### プロンプト

```
chibi anime style eyes only,
cute big round eyes, [COLOR] eye color,
sparkling anime eyes with small highlights,
both eyes symmetrical,

match this face position: [髪型+輪郭画像を参照]
eyes positioned on the face area,

transparent background,
512x512 canvas,
no face, no skin, eyes part only,
soft flat colors, no shading
```

### カラーバリエーション
- 無料: brown, black, dark blue
- 課金: pink, purple, red, golden, heterochromia（オッドアイ）

### スタイルバリエーション
- round big（丸くて大きい）
- almond shaped（アーモンド型）
- droopy cute（たれ目）
- cat eyes（つり目）

---

## STEP 3: 眉毛を作成

### プロンプト

```
chibi anime style eyebrows only,
[STYLE] eyebrow shape,
[COLOR] eyebrow color,
both eyebrows symmetrical,

match this face: [髪型+輪郭画像を参照]

transparent background,
512x512 canvas,
simple thin line style
```

### スタイルバリエーション
- thin curved（細いアーチ）
- straight（まっすぐ）
- gentle（やさしい）
- surprised（驚き）

---

## STEP 4: 鼻を作成

### プロンプト

```
chibi anime style nose only,
simple small [STYLE] nose,
centered on face,

match this face: [髪型+輪郭画像を参照]

transparent background,
512x512 canvas,
minimal cute anime nose
```

### スタイルバリエーション
- small dot（小さな点）
- tiny triangle（小さな三角）
- simple line（シンプルな線）

---

## STEP 5: 口を作成

### プロンプト

```
chibi anime style mouth only,
[EXPRESSION] expression,
cute small mouth,

match this face: [髪型+輪郭画像を参照]

transparent background,
512x512 canvas,
simple anime style mouth
```

### 表情バリエーション
- small smile（小さな笑顔）
- big smile（大きな笑顔）
- open happy（口を開けて笑う）
- neutral（無表情）
- surprised（驚き）
- cat mouth :3（猫口）

---

## レイヤー順序（Flutterでの重ね順）

```dart
Stack(
  children: [
    Image.asset('hair_face_01.png'),  // 髪型+輪郭（最背面）
    Image.asset('eyebrow_01.png'),    // 眉毛
    Image.asset('eyes_01.png'),       // 目
    Image.asset('nose_01.png'),       // 鼻
    Image.asset('mouth_01.png'),      // 口（最前面）
  ],
)
```

---

## ファイル命名規則

```
髪型+輪郭: hair_face_{スタイル}_{カラー}_{肌色}.png
  例: hair_face_long_black_fair.png
      hair_face_twintails_pink_fair.png

目:      eyes_{スタイル}_{カラー}.png
  例: eyes_round_brown.png

眉毛:    eyebrow_{スタイル}.png
  例: eyebrow_gentle.png

鼻:      nose_{スタイル}.png
  例: nose_dot.png

口:      mouth_{表情}.png
  例: mouth_smile.png
```

---

## チェックリスト

### 髪型+輪郭
- [ ] ロングストレート × 4色 × 4肌色
- [ ] ショートボブ × 4色 × 4肌色
- [ ] ツインテール × 4色 × 4肌色
- [ ] ポニーテール × 4色 × 4肌色
- [ ] 課金限定（レインボー等）× 4肌色

### 顔パーツ
- [ ] 目 × 4スタイル × 6色
- [ ] 眉毛 × 4スタイル
- [ ] 鼻 × 3スタイル
- [ ] 口 × 6表情

---

## 生成のコツ

1. **同じseed値を使う**: 一貫性のため
2. **参照画像を活用**: 目などは髪型+輪郭を参照させる
3. **背景を透過に変換**: remove.bg等を使用
4. **512x512に統一**: リサイズが必要な場合は中央配置
