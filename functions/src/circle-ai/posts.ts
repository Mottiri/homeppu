/**
 * 驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫAI髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ髫ｶ蛹・ｽｺ・ｯ郢晢ｽｻ
 * - generateCircleAIPosts: 髯橸ｽｳ陞｢・ｽ隰斐・讌懆ｲ・ｽｯ繝ｻ・｡鬲・ｼ夲ｽｽ・ｼ郢晢ｽｻloud Scheduler郢晢ｽｻ郢晢ｽｻ
 * - executeCircleAIPost: Cloud Tasks驛｢譎｢・ｽ・ｯ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｫ驛｢譎｢・ｽ・ｼ
 * - triggerCircleAIPosts: 髫ｰ繝ｻ蜚ｱ髯悟､ゑｽｹ譎冗樟・取㏍・ｹ・ｧ繝ｻ・ｬ驛｢譎｢・ｽ・ｼ郢晢ｽｻ髢ｧ・ｲ繝ｻ・ｮ繝ｻ・｡鬨ｾ繝ｻ繝ｻ・つ郢晢ｽｻ騾｡莉｣繝ｻ郢晢ｽｻ
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as functionsV1 from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { GoogleGenerativeAI } from "@google/generative-ai";
import { db, FieldValue } from "../helpers/firebase";
import { isAdmin } from "../helpers/admin";
import { scheduleHttpTask } from "../helpers/cloud-tasks";
import { PROJECT_ID, LOCATION, AI_MODELS } from "../config/constants";
import { geminiApiKey } from "../config/secrets";
import { AUTH_ERRORS } from "../config/messages";

// 驛｢譏ｴ繝ｻ邵ｺ蟶ｷ・ｹ譎√＃騾｡莉｣繝ｻ陞｢・ｽ隰費ｽｽ鬨ｾ・｡繝ｻ・ｪ驍ｵ・ｺ繝ｻ・ｯ100
const MAX_CIRCLES_PER_RUN = 3;

/**
 * 驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫAI驍ｵ・ｺ繝ｻ・ｮ髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驛｢・ｧ陜｣・､陷・ｽｽ髫ｰ迹壹・隨倥・・ｹ・ｧ闕ｵ譏ｴ笘・Δ・ｧ繝ｻ・ｹ驛｢譏ｴ繝ｻ・主､・ｹ譎丞ｹｲ・取ｺｽ・ｹ譎｢・ｽ・ｳ驛｢譎丞ｹｲ郢晢ｽｨ
 */
function getCircleAIPostPrompt(
  aiName: string,
  circleName: string,
  circleDescription: string,
  category: string,
  circleRules: string,
  circleGoal: string,
  recentPosts: string[] = [] // 鬯ｩ遨ゑｽｸ・ｻ隰碑・・ｸ・ｺ繝ｻ・ｮ髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ髯ｷﾂ郢晢ｽｻ繝ｻ・ｮ繝ｻ・ｹ郢晢ｽｻ騾趣ｽｯ郤・ｽｾ鬮ｫ髦ｪ繝ｻ陞ｻ鬥ｴ・ｩ蛹・ｽｽ・ｿ鬨ｾ蛹・ｽｽ・ｨ郢晢ｽｻ郢晢ｽｻ
): string {
  const recentPostsSection = recentPosts.length > 0
    ? `
驍ｵ・ｲ陞ｳ・｣遶擾ｽｩ驍ｵ・ｺ闔会ｽ｣繝ｻ迢暦ｽｸ・ｺ繝ｻ・ｹ驍ｵ・ｺ隶守ｿｫ繝ｻ髯橸ｽｳ繝ｻ・ｹ驍ｵ・ｲ郢晢ｽｻ
髣比ｼ夲ｽｽ・･髣包ｽｳ闕ｵ譏ｴ繝ｻ髫ｴ蟠｢ﾂ鬮ｴ蜿ｰ・ｻ・｣郢晢ｽｻ髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驍ｵ・ｺ繝ｻ・ｧ驍ｵ・ｺ陷ｷ・ｶ・つ郢ｧ繝ｻ・ｼ繝ｻ・ｹ・ｧ陟暮ｯ会ｽｽ閾･・ｸ・ｺ繝ｻ・ｨ髣費ｽｨ繝ｻ・ｼ驍ｵ・ｺ雋・ｽｷ郢晢ｽｻ髯橸ｽｳ繝ｻ・ｹ驛｢・ｧ郢晢ｽｻ鬩溽坩・ｸ・ｺ陋滂ｽｩ繝ｻ・｡繝ｻ・ｨ髴托ｽｴ繝ｻ・ｾ驍ｵ・ｺ繝ｻ・ｯ鬩搾ｽｨ繝ｻ・ｶ髯昴・・ｽ・ｾ驍ｵ・ｺ繝ｻ・ｫ髣厄ｽｴ繝ｻ・ｿ驛｢・ｧ闕ｳ蟯ｩ繝ｻ驍ｵ・ｺ郢晢ｽｻ邵ｲ蝣､・ｸ・ｺ闕ｳ蟯ｩ蜻ｳ驍ｵ・ｺ髴郁ｲｻ・ｼ讒ｭ繝ｻ郢晢ｽｻ
${recentPosts.map((p) => `- ${p}`).join("\n")}
`
    : "";

  return `
驍ｵ・ｺ郢ｧ繝ｻ繝ｻ驍ｵ・ｺ雋・･繝ｻ驍ｵ・ｲ陟募ｨｯ諡ｬ驛｢・ｧ遶丞｣ｺ螟｢驍ｵ・ｺ繝ｻ・ｷ驍ｵ・ｲ鬮ｦ・ｪ遶雁､・ｸ・ｺ郢晢ｽｻ遶包ｽｧSNS驍ｵ・ｺ繝ｻ・ｮ驛｢譎｢・ｽ・ｦ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｶ驛｢譎｢・ｽ・ｼ驍ｵ・ｲ郢晢ｽｻ{aiName}驍ｵ・ｲ鬮ｦ・ｪ邵ｲ蝣､・ｸ・ｺ陷ｷ・ｶ・つ郢晢ｽｻ
驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ驍ｵ・ｲ郢晢ｽｻ{circleName}驍ｵ・ｲ鬮ｦ・ｪ郢晢ｽｻ驛｢譎｢・ｽ・｡驛｢譎｢・ｽ・ｳ驛｢譎√・郢晢ｽｻ驍ｵ・ｺ繝ｻ・ｨ驍ｵ・ｺ陷会ｽｱ遯ｶ・ｻ髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驍ｵ・ｺ陷会ｽｱ遶擾ｽｪ驍ｵ・ｺ陷ｷ・ｶ・つ郢晢ｽｻ

驍ｵ・ｲ髣雁ｾ鯉ｼ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ髫ｶ蛹・ｽｺ・ｯ郢晢ｽｻ驍ｵ・ｺ繝ｻ・ｫ驍ｵ・ｺ繝ｻ・､驍ｵ・ｺ郢晢ｽｻ遯ｶ・ｻ驍ｵ・ｲ郢晢ｽｻ
驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ驍ｵ・ｺ繝ｻ・ｯ髯ｷ・ｷ陟募具ｽｧ鬮ｮ諛ｶ・ｽ・｣髯ｷ・ｻ繝ｻ・ｳ驛｢・ｧ郢晢ｽｻ郢晢ｽｻ髯ｷ・ｻ繝ｻ・ｳ驛｢・ｧ陷ｻ蝓滉ｺ憺し・ｺ繝ｻ・､驛｢譎｢・ｽ・ｦ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｶ驛｢譎｢・ｽ・ｼ驍ｵ・ｺ驕停・・ｯ逧ｮ・ｸ・ｺ繝ｻ・ｾ驛｢・ｧ闕ｵ譏ｴ・・Δ譎・ｽｺ菴ｩ遉ｼ・ｹ譏懶ｽｹ譏ｴﾎ倬Δ・ｧ繝ｻ・｣驍ｵ・ｺ繝ｻ・ｧ驍ｵ・ｺ陷ｷ・ｶ・つ郢晢ｽｻ
驛｢譎｢・ｽ・｡驛｢譎｢・ｽ・ｳ驛｢譎√・郢晢ｽｻ驍ｵ・ｺ繝ｻ・ｯ驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ驍ｵ・ｺ繝ｻ・ｮ驛｢譏ｴ繝ｻ郢晢ｽｻ驛｢譎・ｽｧ・ｭ遶企ｦｴ・ｫ・｢繝ｻ・｢驍ｵ・ｺ陷ｷ・ｶ繝ｻ邇厄ｽｭ魃会ｽｽ・･髯晢ｽｶ繝ｻ・ｸ驍ｵ・ｺ繝ｻ・ｮ髯ｷ繝ｻ・ｽ・ｺ髫ｴ螟ｲ・ｽ・･髣費｣ｰ闕ｵ謨鳴遶擾ｽｵ隨渉髫ｲ・ｰ繝ｻ・ｳ驍ｵ・ｲ遶擾ｽｫ陋ｹ・ｱ鬮ｫ遨ゑｽｹ譏ｶ繝ｻ驍ｵ・ｺ繝ｻ・ｩ驛｢・ｧ陞ｳ螢ｹ繝ｻ鬨ｾ蛹・ｽｽ・ｱ驍ｵ・ｺ繝ｻ・ｫ髯ｷ闌ｨ・ｽ・ｱ髫ｴ蟶幢ｽｳ・ｨ繝ｻ・ｰ驍ｵ・ｺ繝ｻ・ｾ驍ｵ・ｺ陷ｷ・ｶ・つ郢晢ｽｻ

驍ｵ・ｲ髣雁ｾ鯉ｼ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ髫ｲ・ｰ郢晢ｽｻ繝ｻ・ｰ繝ｻ・ｱ驍ｵ・ｲ郢晢ｽｻ
- 驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ髯ｷ・ｷ郢晢ｽｻ ${circleName}
- 驛｢・ｧ繝ｻ・ｫ驛｢譏ｴ繝ｻ邵ｺ荵滂ｽｹ譎｢・ｽ・ｪ: ${category}
- 鬮ｫ・ｱ繝ｻ・ｬ髫ｴ荳翫・ ${circleDescription}
- 驛｢譎｢・ｽ・ｫ驛｢譎｢・ｽ・ｼ驛｢譎｢・ｽ・ｫ: ${circleRules || "驍ｵ・ｺ繝ｻ・ｪ驍ｵ・ｺ郢晢ｽｻ}
- 鬨ｾ・ｶ繝ｻ・ｮ髫ｶ阮吶・ ${circleGoal || "驍ｵ・ｺ繝ｻ・ｪ驍ｵ・ｺ郢晢ｽｻ}

驍ｵ・ｲ陷井ｺ･繝ｻ鬩墓ｩｸ・ｽ・ｿ驍ｵ・ｺ繝ｻ・ｮ驛｢譎｢・ｽ・ｫ驛｢譎｢・ｽ・ｼ驛｢譎｢・ｽ・ｫ驍ｵ・ｲ郢晢ｽｻ
1. 驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ驍ｵ・ｺ繝ｻ・ｮ驛｢譏ｴ繝ｻ郢晢ｽｻ驛｢譎・ｽｧ・ｭ遶頑･｢・ｱ謦ｰ・ｽ・ｿ驍ｵ・ｺ繝ｻ・｣驍ｵ・ｺ雋顔§繝ｻ鬩墓ｩｸ・ｽ・ｿ驛｢・ｧ陋幢ｽｵ繝ｻ・ｰ驍ｵ・ｺ繝ｻ・ｦ驍ｵ・ｺ闕ｳ蟯ｩ蜻ｳ驍ｵ・ｺ髴郁ｲｻ・ｼ繝ｻ
2. 驛｢譎｢・ｽ・ｫ驛｢譎｢・ｽ・ｼ驛｢譎｢・ｽ・ｫ驍ｵ・ｺ陟募ｨｯ譌ｺ驛｢・ｧ陷ｿ・･繝ｻ・ｰ繝ｻ・ｴ髯ｷ・ｷ陋ｹ・ｻ郢晢ｽｻ驍ｵ・ｲ遶丞｣ｺ關ｽ驍ｵ・ｺ繝ｻ・ｮ驛｢譎｢・ｽ・ｫ驛｢譎｢・ｽ・ｼ驛｢譎｢・ｽ・ｫ驛｢・ｧ陝ｶ譏ｴ繝ｻ髯橸ｽｳ陋ｹ・ｻ繝ｻ・ｰ驍ｵ・ｺ繝ｻ・ｦ驍ｵ・ｺ闕ｳ蟯ｩ蜻ｳ驍ｵ・ｺ髴郁ｲｻ・ｼ繝ｻ
3. 鬨ｾ・ｶ繝ｻ・ｮ髫ｶ轣倡函遯ｶ・ｲ驍ｵ・ｺ郢ｧ繝ｻ・ｽ邇匁捗繝ｻ・ｴ髯ｷ・ｷ陋ｹ・ｻ郢晢ｽｻ驍ｵ・ｲ遶丞｣ｺ關ｽ驍ｵ・ｺ繝ｻ・ｮ鬨ｾ・ｶ繝ｻ・ｮ髫ｶ轣倡函遶頑･｢諠ｺ闔会ｽ｣・ゑｽｰ驍ｵ・ｺ繝ｻ・｣驍ｵ・ｺ繝ｻ・ｦ髯ｷ莨夲ｽｽ・ｪ髯ｷ迚呻ｽｸ蜻ｻ・ｼ・ｰ驍ｵ・ｺ繝ｻ・ｦ驍ｵ・ｺ郢晢ｽｻ繝ｻ邇匁ｲゅ・・ｿ髯ｷ謳ｾ・ｽ・｢驍ｵ・ｺ繝ｻ・ｧ髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驍ｵ・ｺ陷会ｽｱ遯ｶ・ｻ驍ｵ・ｺ闕ｳ蟯ｩ蜻ｳ驍ｵ・ｺ髴郁ｲｻ・ｼ繝ｻ
4. 鬮｢・ｾ繝ｻ・ｪ髴取ｻゑｽｽ・ｶ驍ｵ・ｺ繝ｻ・ｪ髫ｴ魃会ｽｽ・･髫ｴ蟷｢・ｽ・ｬ鬮ｫ・ｱ隶抵ｽｭ邵ｲ蝣､・ｸ・ｲ郢晢ｽｾNS驛｢・ｧ陝ｲ・ｨ繝ｻ・ｰ驍ｵ・ｺ郢晢ｽｻ邵ｺ蜥ｲ・ｹ・ｧ繝ｻ・ｸ驛｢譎｢・ｽ・･驛｢・ｧ繝ｻ・｢驛｢譎｢・ｽ・ｫ驍ｵ・ｺ繝ｻ・ｪ髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驍ｵ・ｺ繝ｻ・ｫ驍ｵ・ｺ陷会ｽｱ遯ｶ・ｻ驍ｵ・ｺ闕ｳ蟯ｩ蜻ｳ驍ｵ・ｺ髴郁ｲｻ・ｼ繝ｻ
5. 30驍ｵ・ｲ郢晢ｽｻ0髫ｴ竏壹・繝ｻ・ｭ驕会ｽｼ繝ｻ・ｨ陷ｿ・･繝ｻ・ｺ繝ｻ・ｦ驍ｵ・ｺ繝ｻ・ｮ鬩墓得・ｽ・ｭ驍ｵ・ｺ郢晢ｽｻ陷域・笳・・・ｿ驍ｵ・ｺ繝ｻ・ｫ驍ｵ・ｺ陷会ｽｱ遯ｶ・ｻ驍ｵ・ｺ闕ｳ蟯ｩ蜻ｳ驍ｵ・ｺ髴郁ｲｻ・ｼ繝ｻ
6. 驛｢譏懶ｽｸ鄙ｫﾎ暮Δ・ｧ繝ｻ・ｷ驛｢譎｢・ｽ・･驛｢・ｧ繝ｻ・ｿ驛｢・ｧ繝ｻ・ｰ郢晢ｽｻ郢晢ｽｻ髫ｨ・ｳ鬩ｫﾂ鬮ｮ・ｷ郢晢ｽｻ陝ｲ・ｨ郢晢ｽｻ鬩搾ｽｨ繝ｻ・ｶ髯昴・・ｽ・ｾ驍ｵ・ｺ繝ｻ・ｫ髣厄ｽｴ繝ｻ・ｿ鬨ｾ蛹・ｽｽ・ｨ驍ｵ・ｺ陷会ｽｱ遶企・・ｸ・ｺ郢晢ｽｻ邵ｲ蝣､・ｸ・ｺ闕ｳ蟯ｩ蜻ｳ驍ｵ・ｺ髴郁ｲｻ・ｼ繝ｻ
7. 髮惹ｺ包ｽｸ・ｻ陞ｻ鬥ｴﾂ・｡繝ｻ・ｰ驍ｵ・ｺ繝ｻ・ｪ驛｢・ｧ陷ｿ・･郢晢ｽｻ髯橸ｽｳ繝ｻ・ｹ驛｢譎｢・ｽ・ｻ鬮ｯ・ｦ繝ｻ・ｨ髴托ｽｴ繝ｻ・ｾ驍ｵ・ｺ繝ｻ・ｧ髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驍ｵ・ｺ陷会ｽｱ遯ｶ・ｻ驍ｵ・ｺ闕ｳ蟯ｩ蜻ｳ驍ｵ・ｺ髴郁ｲｻ・ｼ讒ｭ繝ｻ闔・･鬩溽坩・ｸ・ｺ闖ｫ・ｶ隴ｫ螟舌・繝ｻ・ｰ驍ｵ・ｺ繝ｻ・ｮ髣厄ｽｴ繝ｻ・ｿ驍ｵ・ｺ郢晢ｽｻ陞ｻ骰具ｽｸ・ｺ雋会ｽｧG郢晢ｽｻ郢晢ｽｻ

驍ｵ・ｲ陞ｳ・｣遶擾ｽｩ驍ｵ・ｺ闔会ｽ｣繝ｻ迢暦ｽｸ・ｺ繝ｻ・ｹ驍ｵ・ｺ陝雜｣・ｽ・｡繝ｻ・ｨ髴托ｽｴ繝ｻ・ｾ驍ｵ・ｲ郢晢ｽｻ
- 驛｢譏懶ｽｸ鄙ｫﾎ暮Δ・ｧ繝ｻ・ｷ驛｢譎｢・ｽ・･驛｢・ｧ繝ｻ・ｿ驛｢・ｧ繝ｻ・ｰ郢晢ｽｻ郢晢ｽｻ髯ｷ蜥ｲ逕･繝ｻ・ｼ繝ｻ・ｷ #鬮ｮ蟲ｨ繝ｻ繝ｻ・ｰ繝ｻ・ｼ 驍ｵ・ｺ繝ｻ・ｪ驍ｵ・ｺ繝ｻ・ｩ郢晢ｽｻ郢晢ｽｻ
- 髯ｷ隨ｬ・ｦ髮・ｽｱ骰具ｽｸ・ｺ繝ｻ・ｨ髯ｷ・ｷ陟募具ｽｧ髯ｷﾂ郢晢ｽｻ繝ｻ・ｮ繝ｻ・ｹ
- 髯ｷ・ｷ陟募具ｽｧ驛｢譎・ｽｼ驥・ｨ抵ｽｹ譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｺ驍ｵ・ｺ繝ｻ・ｮ鬩幢ｽ｢繝ｻ・ｰ驛｢・ｧ鬯伜∞・ｽ・ｿ隴∵腸・ｼ・ｰ
${recentPostsSection}
驍ｵ・ｲ髣雁ｨｯ譌ｺ驍ｵ・ｺ繝ｻ・ｪ驍ｵ・ｺ雋・･繝ｻ髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驍ｵ・ｲ郢晢ｽｻ
`;
}

/**
 * 驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫAI髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驛｢・ｧ髮区ｩｸ・ｽ・ｮ陞｢・ｽ隰斐・讌懆ｲ・ｽｯ繝ｻ・｡鬲・ｼ夲ｽｽ・ｼ郢晢ｽｻloud Scheduler鬨ｾ蛹・ｽｽ・ｨ郢晢ｽｻ郢晢ｽｻ
 * 髮惹ｺ･蜿呵慕事・ｭ蟶吶・髫ｴ蠑ｱ・・ｫ雁ｮ壽｣皮ｹ晢ｽｻ0髫ｴ蠑ｱ・・ｫ頑･｢讌懆ｲ・ｽｯ繝ｻ・｡陟暮ｯ会ｽｽ螳夲ｽｫ・ｰ繝ｻ・ｳ髯橸ｽｳ郢晢ｽｻ
 *
 * 髫ｴ蟠｢ﾂ鬯ｩ蛹・ｽｽ・ｩ髯具ｽｹ闕ｵ貊難ｽｲ・ｿ郢晢ｽｻ郢晢ｽｻ025-12-26郢晢ｽｻ郢晢ｽｻ
 * - 髯ｷ闌ｨ・ｽ・ｨ驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ髫俶誓・ｽ・ｰ髫ｴ貊ゑｽｽ・ｻ驍ｵ・ｺ繝ｻ・ｧ驍ｵ・ｺ繝ｻ・ｯ驍ｵ・ｺ繝ｻ・ｪ驍ｵ・ｺ闕ｳ闔槫ｸｷ・ｹ譎｢・ｽ・ｳ驛｢謨鳴驛｢譎｢・｣・ｰ驍ｵ・ｺ繝ｻ・ｫ髫ｴ蟠｢ﾂ髯樊ｻゑｽｽ・ｧ100髣比ｼ夲ｽｽ・ｶ鬯ｩ蛹・ｽｽ・ｸ髫ｰ螢ｹ繝ｻ
 * - 髯ｷ鬘後＊陟慕距・ｸ・ｺ繝ｻ・ｫ髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驍ｵ・ｺ陷会ｽｱ隨ｳ繝ｻ・ｹ・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ驍ｵ・ｺ繝ｻ・ｯ鬯ｮ・ｯ繝ｻ・､髯樊ｺ倥・
 * - 驛｢・ｧ繝ｻ・ｳ驛｢・ｧ繝ｻ・ｹ驛｢譏懶ｽｺ・･霓､謇具ｽｲ繧・ｽｸ蜷ｶ繝ｻ驍ｵ・ｺ雋・∞・ｽ竏ｬ諤弱・・ｦ鬨ｾ繝ｻ繝ｻ霎溷､ゑｽｹ・ｧ髮区ｧｫ・ｮ蟷・ｽｫ・ｯ郢晢ｽｻ
 */
export const generateCircleAIPosts = functionsV1.region(LOCATION).runWith({
  secrets: ["GEMINI_API_KEY"],
  timeoutSeconds: 120,
  memory: "256MB",
}).pubsub.schedule("0 9,20 * * *").timeZone("Asia/Tokyo").onRun(async () => {
  console.log("=== generateCircleAIPosts START (Scheduler - Optimized) ===");

  try {
    const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
    const queue = "generate-circle-ai-posts";
    const location = LOCATION;

    // 髫ｴ謫ｾ・ｽ・ｨ髫ｴ魃会ｽｽ・･驍ｵ・ｺ繝ｻ・ｮ髫ｴ魃会ｽｽ・･髣皮甥ﾂ・･繝ｻ螳壽╂鬮｢ﾂ繝ｻ・ｾ隴会ｽｦ繝ｻ・ｼ騾趣ｽｯ陷坂握譽碑嵯貅ｽ闊樒ｹ晢ｽｻ郢晢ｽｻ
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayStr = yesterday.toISOString().split("T")[0]; // "YYYY-MM-DD"

    // 髫ｴ謫ｾ・ｽ・ｨ髫ｴ魃会ｽｽ・･髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驍ｵ・ｺ陷会ｽｱ隨ｳ繝ｻ・ｹ・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫID驛｢譎｢・ｽ・ｪ驛｢・ｧ繝ｻ・ｹ驛｢譎冗樟繝ｻ螳壽╂鬮｢ﾂ繝ｻ・ｾ郢晢ｽｻ
    const historyDoc = await db.collection("circleAIPostHistory").doc(yesterdayStr).get();
    const excludedCircleIds: string[] = historyDoc.exists ? (historyDoc.data()?.circleIds || []) : [];
    console.log(`Excluding ${excludedCircleIds.length} circles from yesterday`);

    // 髯ｷ闌ｨ・ｽ・ｨ驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ驛｢・ｧ髮区ｧｫ蠕宣辧蠅灘惧繝ｻ・ｼ郢晢ｽｻsDeleted驛｢譎・ｽｼ譁絶襖驛｢譎｢・ｽ・ｼ驛｢譎｢・ｽ・ｫ驛｢譎擾ｽｳ・ｨ遯ｶ・ｲ驍ｵ・ｺ繝ｻ・ｪ驍ｵ・ｺ郢晢ｽｻ邵ｺ遉ｼ・ｹ譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ驛｢・ｧ郢ｧ繝ｻﾂ・ｧ驛｢・ｧ遶丞､ｲ・ｽ荵昴・郢晢ｽｻ
    const circlesSnapshot = await db.collection("circles").get();

    // AI驍ｵ・ｺ陟暮ｯ会ｽｼ讓抵ｽｸ・ｺ繝ｻ・ｦ驍ｵ・ｲ遶乗刮・朱ｬｮ・ｯ繝ｻ・､驍ｵ・ｺ髴郁ｲｻ・ｽ讙趣ｽｸ・ｺ繝ｻ・ｦ驍ｵ・ｺ郢晢ｽｻ遶企・・ｸ・ｺ郢晢ｽｻ邵ｺ遉ｼ・ｹ譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ驍ｵ・ｺ繝ｻ・ｮ驍ｵ・ｺ繝ｻ・ｿ驛｢譎・ｽｼ譁絶襖驛｢譎｢・ｽ・ｫ驛｢・ｧ繝ｻ・ｿ驛｢譎｢・ｽ・ｪ驛｢譎｢・ｽ・ｳ驛｢・ｧ繝ｻ・ｰ
    const eligibleCircles = circlesSnapshot.docs.filter(doc => {
      const data = doc.data();
      // isDeleted驍ｵ・ｺ髣戊ｼブe郢晢ｽｻ陜捺ｺ倥・鬩穂ｼ夲ｽｽ・ｺ鬨ｾ・ｧ郢晢ｽｻ遶頑･｢諱・耳竏晄ｱる寞繧・樟遶擾ｽｩ郢晢ｽｻ陝ｲ・ｨ郢晢ｽｻ髯懶ｽ｣繝ｻ・ｴ髯ｷ・ｷ陋ｹ・ｻ郢晢ｽｻ鬯ｮ・ｯ繝ｻ・､髯樊ｺ倥・
      // isDeleted驍ｵ・ｺ隰暦ｽｲalse驍ｵ・ｺ繝ｻ・ｾ驍ｵ・ｺ雋・･繝ｻ髫ｴ蟷｢・ｽ・ｪ鬮ｫ・ｪ繝ｻ・ｭ髯橸ｽｳ陞｢・ｹ郢晢ｽｻ髯懶ｽ｣繝ｻ・ｴ髯ｷ・ｷ陋ｹ・ｻ郢晢ｽｻ髯昴・・ｽ・ｾ鬮ｮ雜｣・ｽ・｡
      if (data.isDeleted === true) return false;
      const generatedAIs = data.generatedAIs as Array<{ id: string; name: string; avatarIndex: number }> || [];
      // AI驍ｵ・ｺ陟暮ｯ会ｽｼ讓抵ｽｸ・ｺ繝ｻ・ｪ驍ｵ・ｺ郢晢ｽｻ・つ遶丞｣ｺ遨宣し・ｺ雋・･繝ｻ髫ｴ謫ｾ・ｽ・ｨ髫ｴ魃会ｽｽ・･髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ髮九ｇ迴ｾ遶擾ｽｩ驍ｵ・ｺ繝ｻ・ｮ驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ驍ｵ・ｺ繝ｻ・ｯ鬯ｮ・ｯ繝ｻ・､髯樊ｺ倥・
      return generatedAIs.length > 0 && !excludedCircleIds.includes(doc.id);
    });

    console.log(`Eligible circles: ${eligibleCircles.length} (after exclusion)`);

    // 驛｢譎｢・ｽ・ｩ驛｢譎｢・ｽ・ｳ驛｢謨鳴驛｢譎｢・｣・ｰ驍ｵ・ｺ繝ｻ・ｫ髫ｴ蟠｢ﾂ髯樊ｻゑｽｽ・ｧ100髣比ｼ夲ｽｽ・ｶ鬯ｩ蛹・ｽｽ・ｸ髫ｰ螢ｹ繝ｻ
    const shuffled = eligibleCircles.sort(() => Math.random() - 0.5);
    const selectedCircles = shuffled.slice(0, MAX_CIRCLES_PER_RUN);

    console.log(`Selected ${selectedCircles.length} circles for processing`);

    let scheduledCount = 0;
    const postedCircleIds: string[] = [];

    // 髣碑崟・ｰ螟ｧ・ｾ迢暦ｽｸ・ｺ繝ｻ・ｮ髫ｴ魃会ｽｽ・･髣泌ｳｨ繝ｻ
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayTimestamp = admin.firestore.Timestamp.fromDate(today);
    const todayStr = new Date().toISOString().split("T")[0];

    for (const circleDoc of selectedCircles) {
      const circleData = circleDoc.data();
      const circleId = circleDoc.id;

      const generatedAIs = circleData.generatedAIs as Array<{
        id: string;
        name: string;
        avatarIndex: number;
      }>;

      // 驍ｵ・ｺ陷ｷ・ｶ邵ｲ蝣､・ｸ・ｺ繝ｻ・ｫ髣碑崟・ｰ螟ｧ・ｾ邇厄ｽｬ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驍ｵ・ｺ陟募ｨｯ譌ｺ驛｢・ｧ闕ｵ謨厄ｽｰ驛｢譏ｶ繝ｻ邵ｺ閾･・ｹ譏ｴ繝ｻ邵ｺ繝ｻ
      const todayPosts = await db.collection("posts")
        .where("circleId", "==", circleId)
        .where("createdAt", ">=", todayTimestamp)
        .get();

      // 髣碑崟・ｰ螟ｧ・ｾ迢暦ｽｸ・ｺ陷ｷ・ｶ邵ｲ蝣､・ｸ・ｺ繝ｻ・ｫ2髣比ｼ夲ｽｽ・ｶ髣比ｼ夲ｽｽ・･髣包ｽｳ鬯・､ｧ繝ｻ鬩墓ｩｸ・ｽ・ｿ驍ｵ・ｺ陟募ｨｯ譌ｺ驛｢・ｧ陟募ｾ後・驛｢・ｧ繝ｻ・ｹ驛｢・ｧ繝ｻ・ｭ驛｢譏ｴ繝ｻ郢晢ｽｻ
      if (todayPosts.size >= 2) {
        console.log(`Circle ${circleId} already has ${todayPosts.size} posts today, skipping`);
        continue;
      }

      // 驛｢譎｢・ｽ・ｩ驛｢譎｢・ｽ・ｳ驛｢謨鳴驛｢譎｢・｣・ｰ驍ｵ・ｺ繝ｻ・ｫAI驛｢・ｧ郢晢ｽｻ髣厄ｽｴ鬯･・ｴ遶城メ・ｬ螢ｹ繝ｻ
      const randomAI = generatedAIs[Math.floor(Math.random() * generatedAIs.length)];

      // 0驍ｵ・ｲ郢晢ｽｻ髫ｴ蠑ｱ・玖将・｣髯溷供・ｾ蠕後・驛｢譎｢・ｽ・ｩ驛｢譎｢・ｽ・ｳ驛｢謨鳴驛｢譎｢・｣・ｰ驍ｵ・ｺ繝ｻ・ｪ髫ｴ蠑ｱ・玖将・｣驍ｵ・ｺ繝ｻ・ｫ驛｢・ｧ繝ｻ・ｹ驛｢・ｧ繝ｻ・ｱ驛｢・ｧ繝ｻ・ｸ驛｢譎｢・ｽ・･驛｢譎｢・ｽ・ｼ驛｢譎｢・ｽ・ｫ郢晢ｽｻ闔・･郢晢ｽｻ髯ｷ髮・繝ｻ・ｽ・ｽ鬮ｦ・ｪ邵ｲ螳壼ｴ慕ｹ晢ｽｻ雎ｺ・ｵ郢晢ｽｻ郢晢ｽｻ
      const delayMinutes = Math.floor(Math.random() * 180); // 0驍ｵ・ｲ郢晢ｽｻ80髯具ｽｻ郢晢ｽｻ繝ｻ・ｼ郢晢ｽｻ髫ｴ蠑ｱ・玖将・｣郢晢ｽｻ郢晢ｽｻ
      const scheduleTime = new Date(Date.now() + delayMinutes * 60 * 1000);

      // Cloud Tasks驍ｵ・ｺ繝ｻ・ｫ驛｢・ｧ繝ｻ・ｿ驛｢・ｧ繝ｻ・ｹ驛｢・ｧ繝ｻ・ｯ驛｢・ｧ陜｣・､陋ｹ・ｳ鬯ｪ・ｭ繝ｻ・ｲ
      const targetUrl = `https://${location}-${project}.cloudfunctions.net/executeCircleAIPost`;
      // OIDC驛｢譎冗樟郢晢ｽｻ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｳ鬨ｾ蠅難ｽｻ阮吶・鬨ｾ蛹・ｽｽ・ｨ驍ｵ・ｺ繝ｻ・ｮ驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢譎∽ｾｭ邵ｺ蟶ｷ・ｹ・ｧ繝ｻ・｢驛｢・ｧ繝ｻ・ｫ驛｢・ｧ繝ｻ・ｦ驛｢譎｢・ｽ・ｳ驛｢譎∬か繝ｻ・ｼ郢晢ｽｻloud-tasks-sa驛｢・ｧ陷代・・ｽ・ｽ繝ｻ・ｿ鬨ｾ蛹・ｽｽ・ｨ郢晢ｽｻ郢晢ｽｻ

      const payload = {
        circleId,
        circleName: circleData.name,
        circleDescription: circleData.description || "",
        circleCategory: circleData.category || "驍ｵ・ｺ隴擾ｽｴ郢晢ｽｻ髣泌ｳｨ繝ｻ,
        circleRules: circleData.rules || "",
        circleGoal: circleData.goal || "",
        aiId: randomAI.id,
        aiName: randomAI.name,
        aiAvatarIndex: randomAI.avatarIndex,
      };

      try {
        await scheduleHttpTask({
          queue,
          url: targetUrl,
          payload,
          scheduleTime,
          projectId: project,
          location,
        });
        console.log(`Scheduled post for ${circleData.name} at ${scheduleTime.toISOString()} (delay: ${delayMinutes}min)`);
        scheduledCount++;
        postedCircleIds.push(circleId);
      } catch (error) {
        console.error(`Error scheduling task for circle ${circleId}:`, error);
      }
    }

    // 髣碑崟・ｰ螟ｧ・ｾ迢暦ｽｸ・ｺ繝ｻ・ｮ髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ髯橸ｽｻ繝ｻ・･髮弱・・ｽ・ｴ驛｢・ｧ陷代・・ｽ・ｿ隴取得・ｽ・ｭ陋帙・・ｽ・ｼ陜捺ｺ倥・髫ｴ魃会ｽｽ・･驍ｵ・ｺ繝ｻ・ｮ鬯ｮ・ｯ繝ｻ・､髯樊ｻ会ｽｹ貅ｽ闊樒ｹ晢ｽｻ郢晢ｽｻ
    if (postedCircleIds.length > 0) {
      const historyRef = db.collection("circleAIPostHistory").doc(todayStr);
      const existingHistory = await historyRef.get();
      const existingIds: string[] = existingHistory.exists ? (existingHistory.data()?.circleIds || []) : [];
      const mergedIds = [...new Set([...existingIds, ...postedCircleIds])];

      await historyRef.set({
        date: todayStr,
        circleIds: mergedIds,
        updatedAt: FieldValue.serverTimestamp(),
      });
      console.log(`Saved ${mergedIds.length} circle IDs to history for ${todayStr}`);
    }

    console.log(`=== generateCircleAIPosts COMPLETE: Scheduled ${scheduledCount} posts ===`);

  } catch (error) {
    console.error("=== generateCircleAIPosts ERROR:", error);
  }
});


/**
 * 驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫAI髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驛｢・ｧ髮区ｩｸ・ｽ・ｮ雋・ｽｯ繝ｻ・｡陟募ｨｯ繝ｻ驛｢・ｧ闕ｵ譁滂ｽ｡驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｫ驛｢譎｢・ｽ・ｼ郢晢ｽｻ郢晢ｽｻloud Tasks驍ｵ・ｺ闕ｵ譎｢・ｽ闃ｽ諠ｱ繝ｻ・ｼ驍ｵ・ｺ繝ｻ・ｳ髯ｷ繝ｻ・ｽ・ｺ驍ｵ・ｺ隴会ｽｦ繝ｻ・ｼ郢晢ｽｻ
 */
export const executeCircleAIPost = functionsV1.region(LOCATION).runWith({
  secrets: ["GEMINI_API_KEY"],
  timeoutSeconds: 60,
}).https.onRequest(async (request, response) => {
  // Cloud Tasks 驍ｵ・ｺ闕ｵ譎｢・ｽ閾･・ｸ・ｺ繝ｻ・ｮ驛｢譎｢・ｽ・ｪ驛｢・ｧ繝ｻ・ｯ驛｢・ｧ繝ｻ・ｨ驛｢・ｧ繝ｻ・ｹ驛｢譎冗樟繝ｻ繝ｻOIDC 驛｢譎冗樟郢晢ｽｻ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｳ驍ｵ・ｺ繝ｻ・ｧ髫ｶﾂ隲帙・・ｽ・ｨ繝ｻ・ｼ郢晢ｽｻ闔・･髯悟､青・ｧ郢晢ｽｻ邵ｺ繝ｻ・ｹ譎｢・ｽ・ｳ驛｢譎・ｺ｢郢晢ｽｻ驛｢譎∬か繝ｻ・ｼ郢晢ｽｻ
  const { verifyCloudTasksRequest } = await import("../helpers/cloud-tasks-auth");
  if (!await verifyCloudTasksRequest(request, "executeCircleAIPost")) {
    response.status(403).send("Unauthorized");
    return;
  }

  try {
    const {
      circleId,
      circleName,
      circleDescription,
      circleCategory,
      circleRules,
      circleGoal,
      aiId,
      aiName,
      aiAvatarIndex,
    } = request.body;

    console.log(`Executing AI post for circle ${circleName} by ${aiName}`);

    // 驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ驍ｵ・ｺ隰疲ｺｽ・朱ｬｮ・ｯ繝ｻ・､驍ｵ・ｺ髴郁ｲｻ・ｽ讙趣ｽｸ・ｺ繝ｻ・ｦ驍ｵ・ｺ郢晢ｽｻ遶企・・ｸ・ｺ郢晢ｽｻ・ゑｽｰ鬩墓慣・ｽ・ｺ鬮ｫ・ｱ郢晢ｽｻ
    const circleDoc = await db.collection("circles").doc(circleId).get();
    if (!circleDoc.exists || circleDoc.data()?.isDeleted) {
      console.log(`Circle ${circleId} is deleted or not found, skipping AI post`);
      response.status(200).send("Circle deleted, skipping");
      return;
    }

    // 鬯ｩ遨ゑｽｸ・ｻ隰碑・・ｸ・ｺ繝ｻ・ｮ髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驛｢・ｧ髮区ｧｫ蠕宣辧蠅灘惧繝ｻ・ｼ騾趣ｽｯ郤・ｽｾ鬮ｫ髦ｪ繝ｻ陞ｻ鬥ｴ・ｩ蛹・ｽｽ・ｿ鬨ｾ蛹・ｽｽ・ｨ郢晢ｽｻ郢晢ｽｻ
    const recentPostsSnapshot = await db.collection("posts")
      .where("circleId", "==", circleId)
      .orderBy("createdAt", "desc")
      .limit(5)
      .get();

    const recentPostContents = recentPostsSnapshot.docs.map(doc => doc.data().content as string).filter(Boolean);
    console.log(`Found ${recentPostContents.length} recent posts for deduplication`);

    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      throw new Error("GEMINI_API_KEY is not set");
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: AI_MODELS.GEMINI_DEFAULT });

    // Gemini驍ｵ・ｺ繝ｻ・ｧ髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ髯ｷﾂ郢晢ｽｻ繝ｻ・ｮ繝ｻ・ｹ驛｢・ｧ陜｣・､陷・ｽｽ髫ｰ譴ｧ閻ｸ繝ｻ・ｼ騾趣ｽｯ驍・・諠ｷ繝ｻ・ｻ髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驛｢・ｧ陷ｻ闌ｨ・ｽ・ｸ繝ｻ・｡驍ｵ・ｺ陷会ｽｱ遯ｶ・ｻ鬯ｩ・･陝雜｣・ｽ・､郢晢ｽｻ陞ｻ鬥ｴ・ｩ蛹・ｽｽ・ｿ郢晢ｽｻ郢晢ｽｻ
    const prompt = getCircleAIPostPrompt(aiName, circleName, circleDescription, circleCategory, circleRules, circleGoal, recentPostContents);
    const result = await model.generateContent(prompt);
    let postContent = result.response.text()?.trim();

    // 驛｢譏懶ｽｸ鄙ｫﾎ暮Δ・ｧ繝ｻ・ｷ驛｢譎｢・ｽ・･驛｢・ｧ繝ｻ・ｿ驛｢・ｧ繝ｻ・ｰ驍ｵ・ｺ隰疲ｻ督・ｧ驍ｵ・ｺ繝ｻ・ｾ驛｢・ｧ陟募ｨｯﾂ・ｻ驍ｵ・ｺ郢晢ｽｻ隨ｳ繝ｻ・ｹ・ｧ霑壼衷・朱ｬｮ・ｯ繝ｻ・､
    if (postContent) {
      postContent = postContent.replace(/#[^\s#]+/g, "").trim();
    }

    if (!postContent) {
      console.log(`Empty post generated for circle ${circleId}`);
      response.status(200).send("Empty post, skipping");
      return;
    }

    // 髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驛｢・ｧ陷代・・ｽ・ｽ隲帛現繝ｻ
    const postRef = db.collection("posts").doc();
    await postRef.set({
      userId: aiId,
      userDisplayName: aiName,
      userAvatarIndex: aiAvatarIndex,
      content: postContent,
      postMode: "mix",
      circleId: circleId,
      isVisible: true,
      reactions: {},
      commentCount: 0,
      createdAt: FieldValue.serverTimestamp(),
    });

    // 驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ驍ｵ・ｺ繝ｻ・ｮ髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ髫ｰ・ｨ繝ｻ・ｰ驛｢・ｧ陷ｻ莠･・ｳ・ｩ髫ｴ繝ｻ・ｽ・ｰ
    await db.collection("circles").doc(circleId).update({
      postCount: admin.firestore.FieldValue.increment(1),
      recentActivity: FieldValue.serverTimestamp(),
    });

    console.log(`Created AI post in circle ${circleName}: ${postContent.substring(0, 50)}...`);
    response.status(200).send("Post created");

  } catch (error) {
    console.error("executeCircleAIPost ERROR:", error);
    response.status(500).send(`Error: ${error}`);
  }
});

/**
 * 驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫAI髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驛｢・ｧ陷ｻ閧ｲ繝ｻ髯ｷ蟠趣ｽｼ譁石夐Δ譎｢・ｽ・ｪ驛｢・ｧ繝ｻ・ｬ驛｢譎｢・ｽ・ｼ郢晢ｽｻ陋ｹ・ｻ郢晢ｽｦ驛｢・ｧ繝ｻ・ｹ驛｢譎√＃騾｡莉｣繝ｻ郢晢ｽｻ
 * 髫ｴ蟠｢ﾂ鬯ｩ蛹・ｽｽ・ｩ髯具ｽｹ闕ｵ貊難ｽｲ・ｿ郢晢ｽｻ陜滂ｽｩenerateCircleAIPosts驍ｵ・ｺ繝ｻ・ｨ髯ｷ・ｷ陟募具ｽｧ驛｢譎｢・ｽ・ｭ驛｢・ｧ繝ｻ・ｸ驛｢譏ｴ繝ｻ邵ｺ驢搾ｽｹ・ｧ陷代・・ｽ・ｽ繝ｻ・ｿ鬨ｾ蛹・ｽｽ・ｨ
 */
export const triggerCircleAIPosts = onCall(
  { region: LOCATION, secrets: [geminiApiKey], timeoutSeconds: 300 },
  async (request) => {
    // 驛｢・ｧ繝ｻ・ｻ驛｢・ｧ繝ｻ・ｭ驛｢譎｢・ｽ・･驛｢譎｢・ｽ・ｪ驛｢譏ｴ繝ｻ邵ｺ繝ｻ 鬩阪ｑ・ｽ・｡鬨ｾ繝ｻ繝ｻ・つ郢晢ｽｻ繝ｻ・ｨ繝ｻ・ｩ鬯ｮ・ｯ髣雁ｾ湖馴Δ・ｧ繝ｻ・ｧ驛｢譏ｴ繝ｻ邵ｺ繝ｻ
    if (!request.auth) {
      throw new HttpsError("unauthenticated", AUTH_ERRORS.UNAUTHENTICATED);
    }
    const userIsAdmin = await isAdmin(request.auth.uid);
    if (!userIsAdmin) {
      throw new HttpsError("permission-denied", AUTH_ERRORS.ADMIN_REQUIRED);
    }

    console.log("=== triggerCircleAIPosts (manual - optimized) START ===");

    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      return { success: false, message: "GEMINI_API_KEY is not set" };
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: AI_MODELS.GEMINI_DEFAULT });

    let totalPosts = 0;
    const postedCircleIds: string[] = [];

    try {
      // 髫ｴ謫ｾ・ｽ・ｨ髫ｴ魃会ｽｽ・･驍ｵ・ｺ繝ｻ・ｮ髫ｴ魃会ｽｽ・･髣皮甥ﾂ・･繝ｻ螳壽╂鬮｢ﾂ繝ｻ・ｾ隴会ｽｦ繝ｻ・ｼ騾趣ｽｯ陷坂握譽碑嵯貅ｽ闊樒ｹ晢ｽｻ郢晢ｽｻ
      const yesterday = new Date();
      yesterday.setDate(yesterday.getDate() - 1);
      const yesterdayStr = yesterday.toISOString().split("T")[0];

      // 髫ｴ謫ｾ・ｽ・ｨ髫ｴ魃会ｽｽ・･髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驍ｵ・ｺ陷会ｽｱ隨ｳ繝ｻ・ｹ・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫID驛｢譎｢・ｽ・ｪ驛｢・ｧ繝ｻ・ｹ驛｢譎冗樟繝ｻ螳壽╂鬮｢ﾂ繝ｻ・ｾ郢晢ｽｻ
      const historyDoc = await db.collection("circleAIPostHistory").doc(yesterdayStr).get();
      const excludedCircleIds: string[] = historyDoc.exists ? (historyDoc.data()?.circleIds || []) : [];
      console.log(`Excluding ${excludedCircleIds.length} circles from yesterday`);

      // 髯ｷ闌ｨ・ｽ・ｨ驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ驛｢・ｧ髮区ｧｫ蠕宣辧蠅灘惧繝ｻ・ｼ郢晢ｽｻsDeleted驛｢譎・ｽｼ譁絶襖驛｢譎｢・ｽ・ｼ驛｢譎｢・ｽ・ｫ驛｢譎擾ｽｳ・ｨ遯ｶ・ｲ驍ｵ・ｺ繝ｻ・ｪ驍ｵ・ｺ郢晢ｽｻ邵ｺ遉ｼ・ｹ譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ驛｢・ｧ郢ｧ繝ｻﾂ・ｧ驛｢・ｧ遶丞､ｲ・ｽ荵昴・郢晢ｽｻ
      const circlesSnapshot = await db.collection("circles").get();

      // AI驍ｵ・ｺ陟暮ｯ会ｽｼ讓抵ｽｸ・ｺ繝ｻ・ｦ驍ｵ・ｲ遶乗刮・朱ｬｮ・ｯ繝ｻ・､驍ｵ・ｺ髴郁ｲｻ・ｽ讙趣ｽｸ・ｺ繝ｻ・ｦ驍ｵ・ｺ郢晢ｽｻ遶企・・ｸ・ｺ郢晢ｽｻ邵ｺ遉ｼ・ｹ譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫ驍ｵ・ｺ繝ｻ・ｮ驍ｵ・ｺ繝ｻ・ｿ驛｢譎・ｽｼ譁絶襖驛｢譎｢・ｽ・ｫ驛｢・ｧ繝ｻ・ｿ驛｢譎｢・ｽ・ｪ驛｢譎｢・ｽ・ｳ驛｢・ｧ繝ｻ・ｰ
      const eligibleCircles = circlesSnapshot.docs.filter(doc => {
        const data = doc.data();
        // isDeleted驍ｵ・ｺ髣戊ｼブe郢晢ｽｻ陜捺ｺ倥・鬩穂ｼ夲ｽｽ・ｺ鬨ｾ・ｧ郢晢ｽｻ遶頑･｢諱・耳竏晄ｱる寞繧・樟遶擾ｽｩ郢晢ｽｻ陝ｲ・ｨ郢晢ｽｻ髯懶ｽ｣繝ｻ・ｴ髯ｷ・ｷ陋ｹ・ｻ郢晢ｽｻ鬯ｮ・ｯ繝ｻ・､髯樊ｺ倥・
        if (data.isDeleted === true) return false;
        const generatedAIs = data.generatedAIs as Array<{ id: string; name: string; avatarIndex: number }> || [];
        return generatedAIs.length > 0 && !excludedCircleIds.includes(doc.id);
      });

      console.log(`Eligible circles: ${eligibleCircles.length} (after exclusion)`);

      // 驛｢譎｢・ｽ・ｩ驛｢譎｢・ｽ・ｳ驛｢謨鳴驛｢譎｢・｣・ｰ驍ｵ・ｺ繝ｻ・ｫ髫ｴ蟠｢ﾂ髯樊ｻゑｽｽ・ｧMAX_CIRCLES_PER_RUN髣比ｼ夲ｽｽ・ｶ鬯ｩ蛹・ｽｽ・ｸ髫ｰ螢ｹ繝ｻ
      const shuffled = eligibleCircles.sort(() => Math.random() - 0.5);
      const selectedCircles = shuffled.slice(0, MAX_CIRCLES_PER_RUN);

      console.log(`Selected ${selectedCircles.length} circles for processing`);

      // 髣碑崟・ｰ螟ｧ・ｾ迢暦ｽｸ・ｺ繝ｻ・ｮ髫ｴ魃会ｽｽ・･髣泌ｳｨ繝ｻ
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const todayTimestamp = admin.firestore.Timestamp.fromDate(today);
      const todayStr = new Date().toISOString().split("T")[0];

      for (const circleDoc of selectedCircles) {
        const circleData = circleDoc.data();
        const circleId = circleDoc.id;

        const generatedAIs = circleData.generatedAIs as Array<{
          id: string;
          name: string;
          avatarIndex: number;
        }>;

        // 驍ｵ・ｺ陷ｷ・ｶ邵ｲ蝣､・ｸ・ｺ繝ｻ・ｫ髣碑崟・ｰ螟ｧ・ｾ邇厄ｽｬ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驍ｵ・ｺ陟募ｨｯ譌ｺ驛｢・ｧ闕ｵ謨厄ｽｰ驛｢譏ｶ繝ｻ邵ｺ閾･・ｹ譏ｴ繝ｻ邵ｺ繝ｻ
        const todayPosts = await db.collection("posts")
          .where("circleId", "==", circleId)
          .where("createdAt", ">=", todayTimestamp)
          .get();

        if (todayPosts.size >= 2) {
          console.log(`Circle ${circleId} already has ${todayPosts.size} posts today, skipping`);
          continue;
        }

        const randomAI = generatedAIs[Math.floor(Math.random() * generatedAIs.length)];

        // 鬯ｩ遨ゑｽｸ・ｻ隰碑・・ｸ・ｺ繝ｻ・ｮ髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驛｢・ｧ髮区ｧｫ蠕宣辧蠅灘惧繝ｻ・ｼ騾趣ｽｯ郤・ｽｾ鬮ｫ髦ｪ繝ｻ陞ｻ鬥ｴ・ｩ蛹・ｽｽ・ｿ鬨ｾ蛹・ｽｽ・ｨ郢晢ｽｻ郢晢ｽｻ
        const recentPostsSnapshot = await db.collection("posts")
          .where("circleId", "==", circleId)
          .orderBy("createdAt", "desc")
          .limit(5)
          .get();
        const recentPostContents = recentPostsSnapshot.docs.map(doc => doc.data().content as string).filter(Boolean);

        const prompt = getCircleAIPostPrompt(
          randomAI.name,
          circleData.name,
          circleData.description || "",
          circleData.category || "驍ｵ・ｺ隴擾ｽｴ郢晢ｽｻ髣泌ｳｨ繝ｻ,
          circleData.rules || "",
          circleData.goal || "",
          recentPostContents
        );

        try {
          const result = await model.generateContent(prompt);
          let postContent = result.response.text()?.trim();

          if (postContent) {
            postContent = postContent.replace(/#[^\s#]+/g, "").trim();
          }

          if (!postContent) continue;

          const postRef = db.collection("posts").doc();
          await postRef.set({
            userId: randomAI.id,
            userDisplayName: randomAI.name,
            userAvatarIndex: randomAI.avatarIndex,
            content: postContent,
            postMode: "mix",
            circleId: circleId,
            isVisible: true,
            reactions: {},
            commentCount: 0,
            createdAt: FieldValue.serverTimestamp(),
          });

          await db.collection("circles").doc(circleId).update({
            postCount: admin.firestore.FieldValue.increment(1),
            recentActivity: FieldValue.serverTimestamp(),
          });

          totalPosts++;
          postedCircleIds.push(circleId);
          await new Promise((resolve) => setTimeout(resolve, 500));

        } catch (error) {
          console.error(`Error generating post for circle ${circleId}:`, error);
        }
      }

      // 髣碑崟・ｰ螟ｧ・ｾ迢暦ｽｸ・ｺ繝ｻ・ｮ髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ髯橸ｽｻ繝ｻ・･髮弱・・ｽ・ｴ驛｢・ｧ陷代・・ｽ・ｿ隴取得・ｽ・ｭ陋帙・・ｽ・ｼ陜捺ｺ倥・髫ｴ魃会ｽｽ・･驍ｵ・ｺ繝ｻ・ｮ鬯ｮ・ｯ繝ｻ・､髯樊ｻ会ｽｹ貅ｽ闊樒ｹ晢ｽｻ郢晢ｽｻ
      if (postedCircleIds.length > 0) {
        const historyRef = db.collection("circleAIPostHistory").doc(todayStr);
        const existingHistory = await historyRef.get();
        const existingIds: string[] = existingHistory.exists ? (existingHistory.data()?.circleIds || []) : [];
        const mergedIds = [...new Set([...existingIds, ...postedCircleIds])];

        await historyRef.set({
          date: todayStr,
          circleIds: mergedIds,
          updatedAt: FieldValue.serverTimestamp(),
        });
        console.log(`Saved ${mergedIds.length} circle IDs to history for ${todayStr}`);
      }

      return {
        success: true,
        message: `驛｢・ｧ繝ｻ・ｵ驛｢譎｢・ｽ・ｼ驛｢・ｧ繝ｻ・ｯ驛｢譎｢・ｽ・ｫAI髫ｰ螢ｽ繝ｻ繝ｻ・ｨ繝ｻ・ｿ驛｢・ｧ郢晢ｽｻ{totalPosts}髣比ｼ夲ｽｽ・ｶ髣厄ｽｴ隲帛現繝ｻ驍ｵ・ｺ陷会ｽｱ遶擾ｽｪ驍ｵ・ｺ陷会ｽｱ隨ｳ繝ｻ繝ｻ陜捺ｻ督蜻ｵ譽斐・・ｧ${MAX_CIRCLES_PER_RUN}髣比ｼ夲ｽｽ・ｶ髯ｷ繝ｻ・ｽ・ｦ鬨ｾ繝ｻ繝ｻ繝ｻ・ｼ髣輔・
        totalPosts,
      };

    } catch (error) {
      console.error("triggerCircleAIPosts ERROR:", error);
      return { success: false, message: `驛｢・ｧ繝ｻ・ｨ驛｢譎｢・ｽ・ｩ驛｢譎｢・ｽ・ｼ: ${error}` };
    }
  }
);
