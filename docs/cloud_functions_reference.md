# Cloud Functions 繝ｪ繝輔ぃ繝ｬ繝ｳ繧ｹ

AI謾ｯ謠ｴ髢狗匱逕ｨ縺ｮ繧ｯ繧､繝・け繝ｪ繝輔ぃ繝ｬ繝ｳ繧ｹ縲よｩ溯・謾ｹ菫ｮ繝ｻ霑ｽ蜉譎ゅ↓縺薙・繝峨く繝･繝｡繝ｳ繝医ｒ蜿ら・縺励※縺上□縺輔＞縲・

---

## 刀 繝・ぅ繝ｬ繧ｯ繝医Μ讒区・

```
functions/src/
笏懌楳笏 index.ts           # 繧ｨ繝ｳ繝医Μ繝ｼ繝昴う繝ｳ繝茨ｼ亥・繧ｨ繧ｯ繧ｹ繝昴・繝茨ｼ・
笏懌楳笏 config/            # 險ｭ螳壹・螳壽焚
笏懌楳笏 callable/          # 繝ｦ繝ｼ繧ｶ繝ｼ蜻ｼ縺ｳ蜃ｺ縺鈴未謨ｰ
笏懌楳笏 scheduled/         # 螳壽悄螳溯｡碁未謨ｰ
笏懌楳笏 triggers/          # Firestore繝医Μ繧ｬ繝ｼ
笏懌楳笏 circle-ai/         # 繧ｵ繝ｼ繧ｯ繝ｫAI蟆ら畑
笏懌楳笏 ai/                # AI髢｢騾｣・医・繝ｭ繝ｳ繝励ヨ繝ｻ繝励Ο繝舌う繝繝ｼ・・
笏懌楳笏 helpers/           # 繝倥Ν繝代・髢｢謨ｰ
笏披楳笏 types/             # 蝙句ｮ夂ｾｩ
```

---

## 識 讖溯・蛻･繝輔ぃ繧､繝ｫ荳隕ｧ

### callable/ - 繝ｦ繝ｼ繧ｶ繝ｼ蜻ｼ縺ｳ蜃ｺ縺鈴未謨ｰ

| 繝輔ぃ繧､繝ｫ | 讖溯・ | 荳ｻ縺ｪ髢｢謨ｰ |
|---------|------|---------|
| `admin.ts` | 邂｡逅・・ｩ溯・ | `setAdminRole`, `removeAdminRole`, `banUser`, `permanentBanUser`, `unbanUser`, `deleteAllAIUsers`, `cleanupOrphanedCircleAIs` |
| `users.ts` | 繝ｦ繝ｼ繧ｶ繝ｼ讖溯・ | `followUser`, `unfollowUser`, `getFollowStatus`, `getVirtueHistory`, `getVirtueStatus` |
| `posts.ts` | 謚慕ｨｿ菴懈・ | `createPostWithRateLimit`, `createPostWithModeration` |
| `circles.ts` | 繧ｵ繝ｼ繧ｯ繝ｫ邂｡逅・| `deleteCircle`, `approveJoinRequest`, `rejectJoinRequest`, `sendJoinRequest` |
| `tasks.ts` | 繧ｿ繧ｹ繧ｯ邂｡逅・| `createTask`, `getTasks` |
| `reports.ts` | 騾壼ｱ讖溯・ | `reportContent` |
| `names.ts` | 蜷榊燕邂｡逅・| `initializeNameParts`, `getNameParts`, `updateUserName` |
| `inquiries.ts` | 蝠上＞蜷医ｏ縺・| `createInquiry`, `sendInquiryMessage`, `sendInquiryReply`, `updateInquiryStatus` |
| `ai.ts` | AI邂｡逅・| `initializeAIAccounts`, `generateAIPosts` |

### scheduled/ - 螳壽悄螳溯｡碁未謨ｰ

| 繝輔ぃ繧､繝ｫ | 讖溯・ | 繧ｹ繧ｱ繧ｸ繝･繝ｼ繝ｫ |
|---------|------|-------------|
| `circles.ts` | 繧ｵ繝ｼ繧ｯ繝ｫ邂｡逅・| 繧ｴ繝ｼ繧ｹ繝域､懷・・域ｯ取律3:30・峨、I謌宣聞・域ｯ取怦1譌･・・|
| `cleanup.ts` | 繧ｯ繝ｪ繝ｼ繝ｳ繧｢繝・・ | 蟄､遶九Γ繝・ぅ繧｢繝ｻ蝠上＞蜷医ｏ縺帙・繝ｬ繝昴・繝亥炎髯､・域ｯ取律豺ｱ螟懶ｼ・|
| `reminders.ts` | 繧ｿ繧ｹ繧ｯ/逶ｮ讓吶Μ繝槭う繝ｳ繝繝ｼ騾夂衍 | Cloud Tasks・・TTP・・|
| `ai-posts.ts` | AI謚慕ｨｿ | AI閾ｪ蜍墓兜遞ｿ繧ｹ繧ｱ繧ｸ繝･繝ｼ繝ｫ |

### triggers/ - Firestore繝医Μ繧ｬ繝ｼ

| 繝輔ぃ繧､繝ｫ | 讖溯・ | 繝医Μ繧ｬ繝ｼ蟇ｾ雎｡ |
|---------|------|-------------|
| `circles.ts` | 繧ｵ繝ｼ繧ｯ繝ｫ | 菴懈・譎・I逕滓・縲∵峩譁ｰ譎ゅΓ繝ｳ繝舌・騾夂衍 |
| `posts.ts` | 謚慕ｨｿ | 菴懈・譎・I繧ｳ繝｡繝ｳ繝医せ繧ｱ繧ｸ繝･繝ｼ繝ｫ |
| `notifications.ts` | 騾夂衍 | 騾夂衍繝峨く繝･繝｡繝ｳ繝井ｽ懈・譎ゅ・閾ｪ蜍輔・繝・す繝･騾∽ｿ｡ + 繧ｳ繝｡繝ｳ繝・繝ｪ繧｢繧ｯ繧ｷ繝ｧ繝ｳ騾夂衍菴懈・ |
| `tasks.ts` | 繧ｿ繧ｹ繧ｯ | 譖ｴ譁ｰ譎ゅΜ繝槭う繝ｳ繝繝ｼ繧ｹ繧ｱ繧ｸ繝･繝ｼ繝ｫ |
| `goals.ts` | 逶ｮ讓・| 菴懈・/譖ｴ譁ｰ譎ゅΜ繝槭う繝ｳ繝繝ｼ繧ｹ繧ｱ繧ｸ繝･繝ｼ繝ｫ |

陬懆ｶｳ・・026-01-25・・
- `users/{userId}/notifications/{notificationId}` 縺ｮ菴懈・縺ｧ `onNotificationCreated` 縺瑚・蜍輔〒FCM騾∽ｿ｡
- `pushPolicy: never` 繧帝夂衍繝峨く繝･繝｡繝ｳ繝医↓謖√◆縺帙ｋ縺ｨ縲碁夂衍縺ｯ菴懊ｋ縺継ush縺ｯ騾√ｉ縺ｪ縺・・
### circle-ai/ - 繧ｵ繝ｼ繧ｯ繝ｫAI蟆ら畑

| 繝輔ぃ繧､繝ｫ | 讖溯・ |
|---------|------|
| `posts.ts` | 繧ｵ繝ｼ繧ｯ繝ｫAI謚慕ｨｿ逕滓・繝ｻ螳溯｡・|
| `generator.ts` | 繧ｵ繝ｼ繧ｯ繝ｫAI繝壹Ν繧ｽ繝顔函謌・|

### ai/ - AI髢｢騾｣

| 繝輔ぃ繧､繝ｫ | 讖溯・ |
|---------|------|
| `provider.ts` | AI繝励Ο繝舌う繝繝ｼ繝輔ぃ繧ｯ繝医Μ繝ｼ・・emini/OpenAI・・|
| `personas.ts` | AI繝壹Ν繧ｽ繝雁ｮ夂ｾｩ繝ｻ繧ｷ繧ｹ繝・Β繝励Ο繝ｳ繝励ヨ |
| `prompts/comment.ts` | 繧ｳ繝｡繝ｳ繝育函謌舌・繝ｭ繝ｳ繝励ヨ |
| `prompts/moderation.ts` | 繝｢繝・Ξ繝ｼ繧ｷ繝ｧ繝ｳ繝励Ο繝ｳ繝励ヨ |
| `prompts/post-generation.ts` | 謚慕ｨｿ逕滓・繝励Ο繝ｳ繝励ヨ |
| `prompts/bio-generation.ts` | bio逕滓・繝励Ο繝ｳ繝励ヨ |

### config/ - 險ｭ螳・

| 繝輔ぃ繧､繝ｫ | 蜀・ｮｹ |
|---------|------|
| `constants.ts` | `LOCATION`, `PROJECT_ID`, `AI_MODELS` |
| `messages.ts` | 繧ｨ繝ｩ繝ｼ繝｡繝・そ繝ｼ繧ｸ繝ｻ騾夂衍繧ｿ繧､繝医Ν繝ｻ繝ｩ繝吶Ν螳壽焚 |
| `secrets.ts` | API繧ｭ繝ｼ蜿ら・ |

### helpers/ - 繝倥Ν繝代・

| 繝輔ぃ繧､繝ｫ | 讖溯・ |
|---------|------|
| `firebase.ts` | Firestore蛻晄悄蛹悶・db蜿ら・ |
| `admin.ts` | 邂｡逅・・愛螳・`isAdmin()` |
| `virtue.ts` | 蠕ｳ繝昴う繝ｳ繝郁ｨ育ｮ・|
| `notification.ts` | 繝励ャ繧ｷ繝･騾夂衍騾∽ｿ｡ |
| `storage.ts` | Storage繝輔ぃ繧､繝ｫ蜑企勁 |
| `moderation.ts` | 繝｡繝・ぅ繧｢繝｢繝・Ξ繝ｼ繧ｷ繝ｧ繝ｳ |
| `cloud-tasks-auth.ts` | Cloud Tasks隱崎ｨｼ |

---

## 肌 謾ｹ菫ｮ繝代ち繝ｼ繝ｳ

### 譁ｰ縺励＞Callable髢｢謨ｰ繧定ｿｽ蜉縺吶ｋ蝣ｴ蜷・

1. `callable/` 縺ｫ驕ｩ蛻・↑繝輔ぃ繧､繝ｫ繧帝∈縺ｶ・医∪縺溘・譁ｰ隕丈ｽ懈・・・
2. 髢｢謨ｰ繧貞ｮ溯｣・ｼ・onCall` 菴ｿ逕ｨ・・
3. `index.ts` 縺ｧ繧ｨ繧ｯ繧ｹ繝昴・繝郁ｿｽ蜉
4. 隱崎ｨｼ繝√ぉ繝・け: `AUTH_ERRORS.UNAUTHENTICATED`
5. 讓ｩ髯舌メ繧ｧ繝・け: `AUTH_ERRORS.ADMIN_REQUIRED`

### 譁ｰ縺励＞螳壽悄螳溯｡後ｒ霑ｽ蜉縺吶ｋ蝣ｴ蜷・

1. `scheduled/` 縺ｫ驕ｩ蛻・↑繝輔ぃ繧､繝ｫ繧帝∈縺ｶ
2. `onSchedule` 縺ｧ螳溯｣・
3. `index.ts` 縺ｧ繧ｨ繧ｯ繧ｹ繝昴・繝郁ｿｽ蜉

### 譁ｰ縺励＞繝医Μ繧ｬ繝ｼ繧定ｿｽ蜉縺吶ｋ蝣ｴ蜷・

1. `triggers/` 縺ｫ驕ｩ蛻・↑繝輔ぃ繧､繝ｫ繧帝∈縺ｶ
2. `onDocumentCreated/Updated/Deleted` 縺ｧ螳溯｣・
3. `index.ts` 縺ｧ繧ｨ繧ｯ繧ｹ繝昴・繝郁ｿｽ蜉

### AI繝励Ο繝ｳ繝励ヨ繧貞､画峩縺吶ｋ蝣ｴ蜷・

1. `ai/prompts/` 縺ｮ隧ｲ蠖薙ヵ繧｡繧､繝ｫ繧堤ｷｨ髮・
2. 繧ｳ繝｡繝ｳ繝育函謌・ `comment.ts`
3. 繝｢繝・Ξ繝ｼ繧ｷ繝ｧ繝ｳ: `moderation.ts`
4. 謚慕ｨｿ逕滓・: `post-generation.ts`

### 繧ｨ繝ｩ繝ｼ繝｡繝・そ繝ｼ繧ｸ繧定ｿｽ蜉縺吶ｋ蝣ｴ蜷・

1. `config/messages.ts` 縺ｫ螳壽焚繧定ｿｽ蜉
2. 驕ｩ蛻・↑繧ｫ繝・ざ繝ｪ縺ｫ驟咲ｽｮ・・AUTH_ERRORS`, `VALIDATION_ERRORS` 縺ｪ縺ｩ・・

---

## 搭 讖溯・繧ｫ繝・ざ繝ｪ蛻･ 蟇ｾ蠢懊ヵ繧｡繧､繝ｫ

| 繧・ｊ縺溘＞縺薙→ | 蟇ｾ蠢懊ヵ繧｡繧､繝ｫ |
|-------------|-------------|
| 繝ｦ繝ｼ繧ｶ繝ｼ隱崎ｨｼ繝ｻ讓ｩ髯・| `callable/admin.ts`, `helpers/admin.ts` |
| 繝輔か繝ｭ繝ｼ讖溯・ | `callable/users.ts` |
| 謚慕ｨｿ菴懈・繝ｻ繝｢繝・Ξ繝ｼ繧ｷ繝ｧ繝ｳ | `callable/posts.ts`, `helpers/moderation.ts` |
| 繧ｵ繝ｼ繧ｯ繝ｫ邂｡逅・| `callable/circles.ts`, `triggers/circles.ts` |
| 繧ｵ繝ｼ繧ｯ繝ｫAI | `circle-ai/*.ts` |
| 繧ｿ繧ｹ繧ｯ邂｡逅・| `callable/tasks.ts`, `triggers/tasks.ts` |
| 逶ｮ讓吶Μ繝槭う繝ｳ繝繝ｼ | `triggers/goals.ts`, `scheduled/reminders.ts` |
| 騾壼ｱ讖溯・ | `callable/reports.ts` |
| 蝠上＞蜷医ｏ縺・| `callable/inquiries.ts` |
| 騾夂衍繝ｻ繝励ャ繧ｷ繝･ | `triggers/notifications.ts`, `helpers/notification.ts` |
| AI逕滓・・亥・闊ｬ・・| `callable/ai.ts`, `ai/provider.ts` |
| AI繝励Ο繝ｳ繝励ヨ | `ai/prompts/*.ts` |
| 螳壽悄繧ｯ繝ｪ繝ｼ繝ｳ繧｢繝・・ | `scheduled/cleanup.ts` |
| 繧ｨ繝ｩ繝ｼ繝｡繝・そ繝ｼ繧ｸ | `config/messages.ts` |

---

## ｧｭ 驕狗畑/謇句虚逕ｨ 髢｢謨ｰ縺ｮ謇ｱ縺・婿驥晢ｼ・026-01-28・・
莉･荳九・ **驕狗畑繝ｻ謇句虚螳溯｡悟髄縺・* 縺ｮ髢｢謨ｰ縺ｧ縺吶・ 
迴ｾ迥ｶ縺ｯ邯ｭ謖√＠縺ｾ縺吶′縲・*莉雁ｾ後ｂ驕狗畑縺ｧ菴ｿ繧上↑縺・↑繧牙炎髯､蛟呵｣・* 縺ｨ縺励∪縺吶・
- `cleanUpUserFollows`
- `cleanupOrphanedCircleAIs`
- `triggerCircleAIPosts`
- `triggerEvolveCircleAIs`

**讓ｩ髯蝉ｻ倅ｸ守ｳｻ** 縺ｯ蟆・擂縺ｮ驕狗畑縺ｧ蠢・ｦ√↓縺ｪ繧句庄閭ｽ諤ｧ縺後≠繧九◆繧√・*迴ｾ迥ｶ邯ｭ謖・* 縺ｨ縺励∪縺吶・
- `setAdminRole`
- `removeAdminRole`

**繧ｿ繧ｹ繧ｯ邉ｻ Callable**・・createTask`, `getTasks`・峨・縲∫樟迥ｶ縺ｯ邯ｭ謖√＠縺ｾ縺吶′縲・ 
繧ｯ繝ｩ繧､繧｢繝ｳ繝亥・縺ｮFirestore逶ｴ謗･謫堺ｽ懊ｒ邯ｭ謖√☆繧区婿驥昴・蝣ｴ蜷医・ **蟆・擂蜑企勁蛟呵｣・* 縺ｨ縺励∪縺吶・
---

## 笞・・豕ｨ諢丈ｺ矩・

1. **繝ｪ繝ｼ繧ｸ繝ｧ繝ｳ**: 蠢・★ `LOCATION` 螳壽焚繧剃ｽｿ逕ｨ
2. **繧ｨ繝ｩ繝ｼ繝｡繝・そ繝ｼ繧ｸ**: `config/messages.ts` 縺ｮ螳壽焚繧剃ｽｿ逕ｨ
3. **邂｡逅・・メ繧ｧ繝・け**: `isAdmin()` 繧剃ｽｿ逕ｨ
4. **db蜿ら・**: `helpers/firebase.ts` 縺九ｉ繧､繝ｳ繝昴・繝・
5. **譁ｰ隕上お繧ｯ繧ｹ繝昴・繝・*: 蠢・★ `index.ts` 縺ｫ霑ｽ蜉


---

## scripts

- functions/scripts/backfill-public-users.js
  Backfill publicUsers from users (local script).
