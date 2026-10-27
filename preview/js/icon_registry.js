/**
 * SingWallet 集中化图标注册中心 (SSOT Icon Registry)
 * 统一管理分类图标、UI 状态提示图标以及蓝金双色精致 SVG 矢量图标库。
 * 主色柔和蓝银 #c7d2fe + 点缀色暖金 #fde68a，2px 圆角描边风格。
 * 支持“改一处，全系统关联 DOM 自动联动刷新”，100% 保持向后兼容性，彻底告别彩色 Emoji。
 */

(function (window) {
  'use strict';

  // ================= 8 大核心分类矢量 SVG 图标库 (FAITHFUL_CAT_SVGS) =================
  const FAITHFUL_CAT_SVGS = {
    '餐饮美食': `
      <svg class="w-full h-full inline-block" viewBox="0 0 48 48" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <!-- Wine Glass Left -->
        <path d="M10 14h10v6a5 5 0 0 1-10 0v-6z" stroke="#c7d2fe"/>
        <line x1="10" y1="18" x2="20" y2="18" stroke="#fde68a"/>
        <line x1="15" y1="25" x2="15" y2="34" stroke="#c7d2fe"/>
        <line x1="11" y1="34" x2="19" y2="34" stroke="#c7d2fe"/>
        <!-- Cloche Dome Right -->
        <path d="M23 34h17" stroke="#c7d2fe"/>
        <path d="M24 34a7.5 7.5 0 0 1 15 0" stroke="#fde68a" stroke-width="2"/>
        <circle cx="31.5" cy="24.5" r="1.5" stroke="#fde68a" fill="#fde68a"/>
      </svg>
    `,
    '交通出行': `
      <svg class="w-full h-full inline-block" viewBox="0 0 48 48" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <!-- Exact Streamlined Bullet Train Side Profile from Reference -->
        <path d="M8 20h19c4.5 0 9 2 12.5 5.5-1 2-3 2.5-5.5 2.5H8v-8z" stroke="#c7d2fe"/>
        <!-- Cab Slanted Windshield (Gold) -->
        <path d="M29 21.5h3.5c2 1 4 2.5 5 4h-7l-1.5-4z" stroke="#fde68a" fill="#fde68a" fill-opacity="0.25"/>
        <!-- Passenger Door -->
        <rect x="22" y="21.5" width="3.8" height="6.5" stroke="#c7d2fe"/>
        <!-- Gold Speed Lines -->
        <line x1="8" y1="21.5" x2="19" y2="21.5" stroke="#fde68a" stroke-width="2"/>
        <line x1="8" y1="24.5" x2="19" y2="24.5" stroke="#fde68a" stroke-width="1.6"/>
        <!-- Track Rail Below -->
        <line x1="6" y1="31" x2="42" y2="31" stroke="#c7d2fe" stroke-width="2"/>
      </svg>
    `,
    '日常购物': `
      <svg class="w-full h-full inline-block" viewBox="0 0 48 48" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <!-- Trapezoidal Bag Body -->
        <path d="M12 19h24l-2 16a3 3 0 0 1-3 3H17a3 3 0 0 1-3-3L12 19z" stroke="#c7d2fe"/>
        <!-- Inner Loop Handle (Warm Gold) -->
        <path d="M19 19v-4.5a5 5 0 0 1 10 0V19" stroke="#fde68a" stroke-width="2"/>
        <!-- Outer Loop Handle Behind -->
        <path d="M17 19v-5.5a7 7 0 0 1 14 0V19" stroke="#c7d2fe" stroke-opacity="0.6"/>
        <!-- Handle attachment rivets -->
        <circle cx="19" cy="20" r="1" fill="#fde68a"/>
        <circle cx="29" cy="20" r="1" fill="#fde68a"/>
      </svg>
    `,
    '休闲娱乐': `
      <svg class="w-full h-full inline-block" viewBox="0 0 48 48" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <!-- Gamepad Body -->
        <path d="M13 24c-3 3-3.5 8.5-1 11 2 2 4.5 1.5 6-1.5l2-4.5h8l2 4.5c1.5 3 4 3.5 6 1.5 2.5-2.5 2-8-1-11l-3.5-3.5a5 5 0 0 0-4-1.5h-7a5 5 0 0 0-4 1.5L13 24z" stroke="#c7d2fe"/>
        <!-- D-Pad Cross on Left (Gold) -->
        <path d="M17 25v5m-2.5-2.5h5" stroke="#fde68a" stroke-width="2"/>
        <!-- 4 Action Buttons on Right -->
        <circle cx="31" cy="25" r="0.9" fill="#fde68a"/>
        <circle cx="33" cy="27" r="0.9" fill="#fde68a"/>
        <circle cx="29" cy="27" r="0.9" fill="#c7d2fe"/>
        <circle cx="31" cy="29" r="0.9" fill="#c7d2fe"/>
        <!-- Curving Cord & Beamed Musical Notes -->
        <path d="M24 19c-1-4 2-5 3-7" stroke="#c7d2fe"/>
        <path d="M34 11v6m4-8v6m-4-6h4" stroke="#fde68a" stroke-width="1.8"/>
        <ellipse cx="32.5" cy="17" rx="1.5" ry="1.2" fill="#fde68a"/>
        <ellipse cx="36.5" cy="15" rx="1.5" ry="1.2" fill="#fde68a"/>
      </svg>
    `,
    '生活缴费': `
      <svg class="w-full h-full inline-block" viewBox="0 0 48 48" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <!-- Left Wire -->
        <line x1="7" y1="24" x2="16" y2="24" stroke="#c7d2fe"/>
        <!-- Lightning Bolt (Gold) -->
        <path d="M23 12L16 25h6l-3 12 11-15h-6l4-10z" stroke="#fde68a" stroke-width="2" fill="#fde68a" fill-opacity="0.15"/>
        <!-- Right Wire & Power Plug (Silver/Indigo) -->
        <line x1="26" y1="24" x2="33" y2="24" stroke="#c7d2fe"/>
        <path d="M33 20v8a2 2 0 0 0 2 2h2v-12h-2a2 2 0 0 0-2 2z" stroke="#c7d2fe"/>
        <line x1="37" y1="21.5" x2="41" y2="21.5" stroke="#fde68a" stroke-width="1.8"/>
        <line x1="37" y1="26.5" x2="41" y2="26.5" stroke="#fde68a" stroke-width="1.8"/>
      </svg>
    `,
    '医疗健康': `
      <svg class="w-full h-full inline-block" viewBox="0 0 48 48" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <!-- Rounded Medical Cross (Left & Center) -->
        <path d="M19 12h6v6h6v6h-6v6h-6v-6h-6v-6h6v-6z" stroke="#c7d2fe" stroke-linejoin="round"/>
        <!-- Elegant Botanical Leaf overlaying on the right (Gold) -->
        <path d="M25 31c6-2 11-7 12-14-6 1-12 6-12 14z" stroke="#fde68a" stroke-width="2" fill="#fde68a" fill-opacity="0.15"/>
        <path d="M25 31c4-5 8-9 12-14" stroke="#fde68a" stroke-width="1.5"/>
      </svg>
    `,
    '其他支出': `
      <svg class="w-full h-full inline-block" viewBox="0 0 48 48" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <!-- Isometric 3D Box Outer Hexagon Contour -->
        <path d="M24 10l13 7.5v15L24 40l-13-7.5v-15L24 10z" stroke="#c7d2fe"/>
        <!-- Three Inner Crease Edges meeting at center -->
        <line x1="24" y1="25" x2="37" y2="17.5" stroke="#c7d2fe"/>
        <line x1="24" y1="25" x2="11" y2="17.5" stroke="#c7d2fe"/>
        <line x1="24" y1="25" x2="24" y2="40" stroke="#c7d2fe"/>
        <!-- Sealing Tape on Top Face (Gold) -->
        <line x1="17.5" y1="13.7" x2="30.5" y2="21.3" stroke="#fde68a" stroke-width="2"/>
        <line x1="24" y1="25" x2="24" y2="33" stroke="#fde68a" stroke-width="1.8"/>
      </svg>
    `,
    '工资收入': `
      <svg class="w-full h-full inline-block" viewBox="0 0 48 48" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <!-- Left Lower Coin Stack (Silver/Indigo) -->
        <ellipse cx="16" cy="30" rx="6" ry="2.2" stroke="#c7d2fe"/>
        <path d="M10 30v4c0 1.2 2.7 2.2 6 2.2s6-1 6-2.2v-4" stroke="#c7d2fe"/>
        <path d="M10 34v4c0 1.2 2.7 2.2 6 2.2s6-1 6-2.2v-4" stroke="#c7d2fe"/>
        <!-- Right Higher Coin Stack (Gold) -->
        <ellipse cx="30" cy="24" rx="6.5" ry="2.2" stroke="#fde68a" stroke-width="2"/>
        <path d="M23.5 24v3.5c0 1.2 2.9 2.2 6.5 2.2s6.5-1 6.5-2.2v-3.5" stroke="#fde68a"/>
        <path d="M23.5 27.5v3.5c0 1.2 2.9 2.2 6.5 2.2s6.5-1 6.5-2.2v-3.5" stroke="#fde68a"/>
        <path d="M23.5 31v3.5c0 1.2 2.9 2.2 6.5 2.2s6.5-1 6.5-2.2v-3.5" stroke="#fde68a"/>
        <path d="M23.5 34.5v3.5c0 1.2 2.9 2.2 6.5 2.2s6.5-1 6.5-2.2v-3.5" stroke="#fde68a"/>
        <!-- Upward Trend Growth Arrow -->
        <path d="M12 22c6-5 14-6 23-4" stroke="#fde68a" stroke-width="2"/>
        <path d="M31 16l5 2-2 5" stroke="#fde68a" stroke-width="2" stroke-linejoin="round"/>
      </svg>
    `
  };

  // 蓝金双色精致矢量分类折角标签图标 (tag_badge)
  const DEFAULT_TAG_BADGE_SVG = `
    <svg class="w-full h-full inline-block" viewBox="0 0 48 48" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M22 8H10a2 2 0 0 0-2 2v12a2 2 0 0 0 .59 1.41l16 16a2 2 0 0 0 2.83 0l11.17-11.17a2 2 0 0 0 0-2.83l-16-16A2 2 0 0 0 22 8z" stroke="#c7d2fe"/>
      <circle cx="15" cy="15" r="2.5" stroke="#fde68a" fill="#fde68a" fill-opacity="0.25"/>
      <path d="M26 22l5 5" stroke="#fde68a" stroke-width="1.8"/>
    </svg>
  `;

  FAITHFUL_CAT_SVGS['tag_badge'] = DEFAULT_TAG_BADGE_SVG;
  FAITHFUL_CAT_SVGS['收入'] = FAITHFUL_CAT_SVGS['工资收入'];
  FAITHFUL_CAT_SVGS['收入/退款'] = FAITHFUL_CAT_SVGS['工资收入'];

  // ================= 全局 UI 状态与提示蓝金双色线性 SVG 图标库 (UI_STATUS_SVGS) =================
  const UI_STATUS_SVGS = {
    // 1. AI 视觉引擎 (芯片/智能体面罩)
    aiRobot: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5V2" stroke="#c7d2fe"/><circle cx="12" cy="2" r="1" fill="#fde68a" stroke="#fde68a"/><rect x="4" y="5" width="16" height="14" rx="3.5" stroke="#c7d2fe"/><circle cx="9" cy="11" r="1.2" fill="#fde68a" stroke="#fde68a"/><circle cx="15" cy="11" r="1.2" fill="#fde68a" stroke="#fde68a"/><path d="M8.5 15h1m1.5 0h2m1.5 0h1" stroke="#fde68a" stroke-width="1.8"/><line x1="2" y1="12" x2="4" y2="12" stroke="#c7d2fe"/><line x1="20" y1="12" x2="22" y2="12" stroke="#c7d2fe"/></svg>`,

    // 2. AI 智能星芒 (一大一小四角星)
    sparkles: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M9.5 2c0 3.8-1.7 5.5-5.5 5.5 3.8 0 5.5 1.7 5.5 5.5 0-3.8 1.7-5.5 5.5-5.5-3.8 0-5.5-1.7-5.5-5.5z" stroke="#fde68a" fill="#fde68a" fill-opacity="0.2"/><path d="M17 12c0 2.2-1 3.2-3.2 3.2 2.2 0 3.2 1 3.2 3.2 0-2.2 1-3.2 3.2-3.2-2.2 0-3.2-1-3.2-3.2z" stroke="#c7d2fe" fill="#c7d2fe" fill-opacity="0.2"/></svg>`,

    // 3. 流光沙漏 (几何对称沙漏)
    spinner: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M6 3h12" stroke="#c7d2fe"/><path d="M6 21h12" stroke="#c7d2fe"/><path d="M7 3v3.5c0 2.5 2 4.5 5 5.5-3 1-5 3-5 5.5V21" stroke="#c7d2fe"/><path d="M17 3v3.5c0 2.5-2 4.5-5 5.5 3 1 5 3 5 5.5V21" stroke="#c7d2fe"/><path d="M9 7h6l-1 2.5h-4L9 7z" stroke="#fde68a" fill="#fde68a" fill-opacity="0.3"/><line x1="12" y1="12" x2="12" y2="15" stroke="#fde68a" stroke-width="1.6"/><circle cx="12" cy="18.5" r="1.2" fill="#fde68a" stroke="#fde68a"/></svg>`,

    // 4. 灵感小灯泡
    bulb: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M9 16c-2.4-1.4-4-4-4-7a7 7 0 1 1 14 0c0 3-1.6 5.6-4 7v2H9v-2z" stroke="#c7d2fe"/><path d="M10 10l2-2.5 2 2.5" stroke="#fde68a" stroke-width="1.8"/><line x1="9.5" y1="18.5" x2="14.5" y2="18.5" stroke="#fde68a" stroke-width="1.8"/><line x1="10.5" y1="21" x2="13.5" y2="21" stroke="#fde68a" stroke-width="1.8"/></svg>`,

    // 5. 分类折角标签
    ruleTag: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12.5 3H6a2 2 0 0 0-2 2v6.5a2 2 0 0 0 .59 1.41l7.5 7.5a2 2 0 0 0 2.83 0l5.17-5.17a2 2 0 0 0 0-2.83l-7.5-7.5A2 2 0 0 0 12.5 3z" stroke="#c7d2fe"/><circle cx="7.5" cy="6.5" r="1.5" stroke="#fde68a" fill="#fde68a" fill-opacity="0.25"/><line x1="11.5" y1="10.5" x2="15.5" y2="14.5" stroke="#fde68a" stroke-width="1.8"/></svg>`,

    // 6. 验证成功
    success: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9" stroke="#c7d2fe"/><polyline points="8 12 10.8 14.8 16 9.2" stroke="#fde68a" stroke-width="2.2"/></svg>`,

    // 7. 安全预警
    warning: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" stroke="#c7d2fe"/><line x1="12" y1="9" x2="12" y2="13.5" stroke="#fde68a" stroke-width="2.2"/><circle cx="12" cy="17" r="0.8" fill="#fde68a" stroke="#fde68a"/></svg>`,

    // 8. 异常拦截
    error: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9" stroke="#c7d2fe"/><line x1="8.5" y1="8.5" x2="15.5" y2="15.5" stroke="#fde68a" stroke-width="2.2"/><line x1="15.5" y1="8.5" x2="8.5" y2="15.5" stroke="#fde68a" stroke-width="2.2"/></svg>`,

    // 9. 规则同步刷新
    refresh: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M20.5 11.5A8.5 8.5 0 0 0 5.8 7.2M5.5 3.5v4h4" stroke="#c7d2fe"/><path d="M3.5 12.5a8.5 8.5 0 0 0 14.7 4.3M18.5 20.5v-4h-4" stroke="#fde68a"/></svg>`,

    // 10. 灵动岛全面屏
    mobile: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><rect x="5.5" y="2.5" width="13" height="19" rx="3" stroke="#c7d2fe"/><rect x="9.5" y="4.5" width="5" height="1.8" rx="0.9" fill="#fde68a" stroke="#fde68a"/><line x1="9.5" y1="19" x2="14.5" y2="19" stroke="#c7d2fe" stroke-opacity="0.6"/></svg>`,

    // 11. 精准秒表
    timer: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M10 2h4" stroke="#fde68a" stroke-width="2"/><line x1="12" y1="2" x2="12" y2="4.5" stroke="#fde68a"/><line x1="18" y1="6" x2="16.5" y2="7.5" stroke="#c7d2fe"/><circle cx="12" cy="13.5" r="8" stroke="#c7d2fe"/><polyline points="12 9.5 12 13.5 15 13.5" stroke="#fde68a" stroke-width="2"/></svg>`,

    // 12. 系统信息
    info: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9" stroke="#c7d2fe"/><circle cx="12" cy="7.8" r="0.8" fill="#fde68a" stroke="#fde68a"/><line x1="12" y1="10.5" x2="12" y2="16.2" stroke="#fde68a" stroke-width="2.2"/></svg>`,

    // 13. 回收站
    trash: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M9.5 4.5h5v-1a.5.5 0 0 0-.5-.5h-4a.5.5 0 0 0-.5.5v1z" stroke="#c7d2fe"/><line x1="4.5" y1="5.5" x2="19.5" y2="5.5" stroke="#fde68a" stroke-width="2"/><path d="M6.5 7l1.5 12a2 2 0 0 0 2 1.8h4a2 2 0 0 0 2-1.8L17.5 7" stroke="#c7d2fe"/><line x1="10" y1="9.5" x2="10.5" y2="16.5" stroke="#fde68a" stroke-width="1.6"/><line x1="14" y1="9.5" x2="13.5" y2="16.5" stroke="#fde68a" stroke-width="1.6"/></svg>`,

    // 14. 草稿收件箱
    inbox: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><line x1="8" y1="6" x2="16" y2="6" stroke="#fde68a" stroke-width="1.8"/><line x1="9" y1="9" x2="15" y2="9" stroke="#fde68a" stroke-width="1.6"/><path d="M4.5 10.5h15l-1.5 8.5a1.5 1.5 0 0 1-1.5 1.2H7.5a1.5 1.5 0 0 1-1.5-1.2L4.5 10.5z" stroke="#c7d2fe"/><path d="M4.5 11.5h4.5l1.5 3h3l1.5-3h4.5" stroke="#c7d2fe"/></svg>`,

    // 15. 凭证相机
    camera: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M9 6l1.5-2h3l1.5 2" stroke="#c7d2fe"/><rect x="3.5" y="6" width="17" height="14" rx="3" stroke="#c7d2fe"/><circle cx="16.5" cy="8.5" r="0.9" fill="#fde68a"/><circle cx="12" cy="13" r="4.2" stroke="#c7d2fe"/><path d="M12 9.5l2 2.2-.5 2.6-2.2.5-1.4-2.2.6-2.2" stroke="#fde68a" stroke-width="1.4"/></svg>`,

    // 16. 闪电
    bolt: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12.5 2.5L5.5 12h5l-1.5 8.5 7.5-10.5h-5l3-7.5z" stroke="#fde68a" stroke-width="2" fill="#fde68a" fill-opacity="0.18"/><line x1="17" y1="13" x2="20" y2="13" stroke="#c7d2fe" stroke-width="1.8"/><line x1="18.5" y1="11.5" x2="18.5" y2="14.5" stroke="#c7d2fe" stroke-width="1.8"/></svg>`,

    // 17. 剪贴板
    clipboard: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M9 5V3.5a1.5 1.5 0 0 1 1.5-1.5h3A1.5 1.5 0 0 1 15 3.5V5" stroke="#fde68a" stroke-width="2"/><rect x="5.5" y="4.5" width="13" height="16" rx="2" stroke="#c7d2fe"/><line x1="9.5" y1="9.5" x2="15" y2="9.5" stroke="#fde68a" stroke-width="1.8"/><line x1="9.5" y1="13.5" x2="15" y2="13.5" stroke="#c7d2fe"/><line x1="9.5" y1="16.5" x2="13" y2="16.5" stroke="#c7d2fe"/></svg>`,

    // 18. 保存
    save: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M5 4.5A1.5 1.5 0 0 1 6.5 3h10.3a1.5 1.5 0 0 1 1.06.44l2.7 2.7A1.5 1.5 0 0 1 21 7.2v12.3a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 5 19.5v-15z" stroke="#c7d2fe"/><rect x="8" y="3" width="8" height="5.5" rx="0.5" stroke="#fde68a" stroke-width="1.8"/><line x1="12" y1="4.5" x2="12" y2="7" stroke="#fde68a" stroke-width="1.8"/><rect x="7.5" y="12.5" width="9" height="7" rx="1" stroke="#c7d2fe"/></svg>`,

    // 19. 上传
    upload: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M4.5 15.5v3a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2v-3" stroke="#c7d2fe"/><polyline points="7.5 8.5 12 4 16.5 8.5" stroke="#fde68a" stroke-width="2"/><line x1="12" y1="4" x2="12" y2="14.5" stroke="#fde68a" stroke-width="2"/></svg>`,

    // 20. 扫除清理
    broom: `<svg class="w-4 h-4 inline-block align-text-bottom shrink-0" viewBox="0 0 24 24" fill="none" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><line x1="17.5" y1="3.5" x2="11" y2="11.5" stroke="#c7d2fe" stroke-width="2"/><path d="M11 11.5l-3 4.5-4 2 2.5-4 3.5-3.5 1 1z" stroke="#fde68a" stroke-width="1.8" fill="#fde68a" fill-opacity="0.2"/><circle cx="19.5" cy="7.5" r="0.8" fill="#fde68a" stroke="#fde68a"/><line x1="5.5" y1="19.5" x2="7.5" y2="17.5" stroke="#c7d2fe"/></svg>`,

    // 21. 庆祝 (别名 -> sparkles)
    celebrate: null,

    // 22. 兜底分类
    fallbackCategory: null,

    // 23. 默认分类
    defaultCategory: null,

    // 24. 蓝金折角标签徽章
    tag_badge: null,
    tagBadge: null
  };

  UI_STATUS_SVGS.celebrate = UI_STATUS_SVGS.sparkles;
  UI_STATUS_SVGS.fallbackCategory = FAITHFUL_CAT_SVGS['其他支出'];
  UI_STATUS_SVGS.defaultCategory = FAITHFUL_CAT_SVGS['餐饮美食'];
  UI_STATUS_SVGS.tag_badge = DEFAULT_TAG_BADGE_SVG;
  UI_STATUS_SVGS.tagBadge = DEFAULT_TAG_BADGE_SVG;

  // 初始 8 大核心分类默认图标 (直接以 FAITHFUL_CAT_SVGS 为默认值)
  const INITIAL_DEFAULT_EMOJIS = {
    '餐饮美食': FAITHFUL_CAT_SVGS['餐饮美食'],
    '日常购物': FAITHFUL_CAT_SVGS['日常购物'],
    '交通出行': FAITHFUL_CAT_SVGS['交通出行'],
    '休闲娱乐': FAITHFUL_CAT_SVGS['休闲娱乐'],
    '生活缴费': FAITHFUL_CAT_SVGS['生活缴费'],
    '医疗健康': FAITHFUL_CAT_SVGS['医疗健康'],
    '其他支出': FAITHFUL_CAT_SVGS['其他支出'],
    '工资收入': FAITHFUL_CAT_SVGS['工资收入'],
    '收入': FAITHFUL_CAT_SVGS['工资收入'],
    '收入/退款': FAITHFUL_CAT_SVGS['工资收入']
  };

  // 反向映射字典 (保留向后兼容接口，内部无硬编码 Emoji)
  const EMOJI_TO_CATEGORY_MAP = {};

  // 集中管理所有 UI 状态与提示图标字典 (直接以 UI_STATUS_SVGS 作为默认值)
  const UI_STATUS_EMOJIS = { ...UI_STATUS_SVGS };

  // 分类当前注册图标字典
  const categoryEmojis = { ...INITIAL_DEFAULT_EMOJIS };

  // 当前渲染模式：'svg' | 'emoji' (默认设为 'svg')
  let currentRenderMode = 'svg';

  // 核心注册管理对象
  const IconRegistry = {
    categoryEmojis: categoryEmojis,
    uiStatusEmojis: UI_STATUS_EMOJIS,

    /**
     * 获取指定分类或旧标识对应的最新分类图标
     * @param {string} catOrEmoji 分类名、子分类名或默认图标
     * @returns {string} 对应的图标字符串
     */
    getCategoryIcon(catOrEmoji) {
      if (!catOrEmoji) return this.uiStatusEmojis.fallbackCategory;
      const str = String(catOrEmoji).trim();
      if (str === 'tag_badge' || str === 'tagBadge') {
        return DEFAULT_TAG_BADGE_SVG;
      }

      // 1. 如果传入的是反向映射，定位分类并返回最新注册图标
      if (EMOJI_TO_CATEGORY_MAP[str]) {
        const mappedCat = EMOJI_TO_CATEGORY_MAP[str];
        return this.categoryEmojis[mappedCat] || INITIAL_DEFAULT_EMOJIS[mappedCat] || str;
      }

      // 2. 如果已直接在注册表中，直接返回
      if (this.categoryEmojis[str]) {
        return this.categoryEmojis[str];
      }

      // 3. 语义推导：匹配已有 8 大核心分类语义
      if (/餐饮|美食|饭|餐|外卖|咖啡|奶茶|火锅|小吃/.test(str)) return this.categoryEmojis['餐饮美食'] || FAITHFUL_CAT_SVGS['餐饮美食'];
      if (/出行|交通|车|打车|地铁|公交|机票|高铁|火车|加油|停车/.test(str)) return this.categoryEmojis['交通出行'] || FAITHFUL_CAT_SVGS['交通出行'];
      if (/购物|超市|商超|便利店|衣服|服饰|数码|买/.test(str)) return this.categoryEmojis['日常购物'] || FAITHFUL_CAT_SVGS['日常购物'];
      if (/娱乐|游戏|电影|演出|旅游|度假/.test(str)) return this.categoryEmojis['休闲娱乐'] || FAITHFUL_CAT_SVGS['休闲娱乐'];
      if (/缴费|水费|电费|燃气|话费|宽带|房租|物业/.test(str)) return this.categoryEmojis['生活缴费'] || FAITHFUL_CAT_SVGS['生活缴费'];
      if (/医|药|健康|医院|门诊/.test(str)) return this.categoryEmojis['医疗健康'] || FAITHFUL_CAT_SVGS['医疗健康'];
      if (/工资|薪资|收入|理财|分红|收益/.test(str)) return this.categoryEmojis['工资收入'] || FAITHFUL_CAT_SVGS['工资收入'];

      // 4. 通过 resolveParentCategory 归并为一级分类后获取
      const resolver = window.resolveParentCategory || (window.DomainRegistry && window.DomainRegistry.resolveParentCategory);
      if (typeof resolver === 'function') {
        const parent = resolver(str);
        if (parent && this.categoryEmojis[parent] && parent !== '其他支出') {
          return this.categoryEmojis[parent];
        }
      }

      // 5. 判断是否属于系统状态图标
      if (this.uiStatusEmojis[str]) {
        return this.uiStatusEmojis[str];
      }

      // 6. 新增自定义分类回退至蓝金双色 tag_badge
      return DEFAULT_TAG_BADGE_SVG;
    },

    /**
     * 动态修改指定分类的图标，并立即触发全局所有关联地方的自动同步刷新！
     * @param {string} catName 分类名
     * @param {string} newEmoji 新图标 (SVG 字符串或自定义字符串)
     */
    setCategoryIcon(catName, newEmoji) {
      if (!catName || !newEmoji) return;
      const resolver = window.resolveParentCategory || (window.DomainRegistry && window.DomainRegistry.resolveParentCategory);
      const parent = typeof resolver === 'function' ? resolver(catName) : catName;

      this.categoryEmojis[parent] = newEmoji;
      this.categoryEmojis[catName] = newEmoji;
      baseCategoryIconMap[parent] = newEmoji;
      baseCategoryIconMap[catName] = newEmoji;

      // 自动触发全系统 UI 同步更新
      this.refreshAllIcons();
    },

    /**
     * 获取指定 UI 状态图标
     */
    getStatusIcon(key) {
      return this.uiStatusEmojis[key] || this.uiStatusEmojis.fallbackCategory;
    },

    /**
     * 修改指定 UI 状态图标并同步刷新
     */
    setStatusIcon(key, newEmoji) {
      if (!key || !newEmoji) return;
      this.uiStatusEmojis[key] = newEmoji;
      this.refreshAllIcons();
    },

    /**
     * 切换全局渲染模式 ('emoji' | 'svg')
     */
    setRenderMode(mode) {
      currentRenderMode = mode === 'svg' ? 'svg' : 'emoji';
      this.refreshAllIcons();
    },

    getRenderMode() {
      return currentRenderMode;
    },

    /**
     * 核心联动函数：遍历更新全系统所有绑定图标的 DOM 节点
     */
    refreshAllIcons() {
      // 1. 遍历所有带有 [data-cat-icon] 的元素
      try {
        const catElements = document.querySelectorAll('[data-cat-icon]');
        catElements.forEach(el => {
          const cat = el.getAttribute('data-cat-icon');
          if (cat) {
            const icon = this.getCategoryIcon(cat);
            el.innerHTML = icon;
          }
        });
      } catch (e) {}

      // 2. 遍历所有带有 [data-ui-icon] 的元素
      try {
        const uiElements = document.querySelectorAll('[data-ui-icon]');
        uiElements.forEach(el => {
          const key = el.getAttribute('data-ui-icon');
          if (key) {
            const icon = this.getStatusIcon(key);
            el.innerHTML = icon;
          }
        });
      } catch (e) {}

      // 3. 同步草稿箱推荐分类图标 (#suggested-icon)
      try {
        const sugCatEl = document.getElementById('suggested-cat') || document.getElementById('select-draft-category');
        const sugIcon = document.getElementById('suggested-icon');
        if (sugIcon && sugCatEl) {
          const catVal = sugCatEl.value || sugCatEl.textContent || sugCatEl.innerText || '';
          if (catVal) {
            sugIcon.innerHTML = this.getCategoryIcon(catVal.trim());
          }
        }
      } catch (e) {}

      // 4. 调用业务视图刷新回调函数 (如果存在)
      if (typeof window.refreshAppViewsOnIconChange === 'function') {
        try {
          window.refreshAppViewsOnIconChange();
        } catch (e) {
          console.warn('refreshAppViewsOnIconChange error:', e);
        }
      }
    }
  };

  // 底层实际存储图标的对象
  const baseCategoryIconMap = { ...INITIAL_DEFAULT_EMOJIS };

  // ES6 Proxy 代理对象：支持直接读写 CATEGORY_ICON_MAP['餐饮美食'] = '<svg>...' 自动触发联动
  const categoryIconProxyHandler = {
    get(target, prop) {
      if (typeof prop === 'symbol') return target[prop];
      if (typeof prop === 'string') {
        if (prop in target) return target[prop];
        return IconRegistry.getCategoryIcon(prop);
      }
      return target[prop];
    },
    set(target, prop, value) {
      if (typeof prop === 'string') {
        target[prop] = value;
        IconRegistry.setCategoryIcon(prop, value);
        return true;
      }
      target[prop] = value;
      return true;
    },
    has(target, prop) {
      return true;
    }
  };

  const CATEGORY_ICON_MAP = new Proxy(baseCategoryIconMap, categoryIconProxyHandler);
  const parentCategoryIcons = new Proxy(baseCategoryIconMap, categoryIconProxyHandler);

  // ================= 矢量系统通用 SVG 图标库 (SYSTEM_SVGS) =================
  const SYSTEM_SVGS = {
    // 1. Ledger Transactions (Receipt with jagged cut bottom and text lines)
    'ledger': `
      <svg class="w-full h-full" viewBox="0 0 48 48" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M14 10h15l6 6v18l-3-2.5-3 2.5-3-2.5-3 2.5-3-2.5-3 2.5-3-2.5V10z" stroke="#c7d2fe"/>
        <path d="M29 10v6h6" stroke="#c7d2fe"/>
        <line x1="18" y1="18" x2="26" y2="18" stroke="#fde68a" stroke-width="2.2"/>
        <line x1="18" y1="23" x2="23" y2="23" stroke="#c7d2fe"/>
        <line x1="26" y1="23" x2="30" y2="23" stroke="#fde68a"/>
        <line x1="18" y1="27" x2="25" y2="27" stroke="#c7d2fe"/>
        <line x1="28" y1="27" x2="31" y2="27" stroke="#fde68a"/>
      </svg>
    `,
    // 2. Drafts Inbox (Document tray with papers inside)
    'drafts_inbox': `
      <svg class="w-full h-full" viewBox="0 0 48 48" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <!-- Paper sheets inside -->
        <path d="M16 16h16" stroke="#fde68a" stroke-width="2"/>
        <path d="M18 20h12" stroke="#fde68a" stroke-width="1.8"/>
        <!-- Inbox Tray Body -->
        <path d="M11 22h26l-2 12a2 2 0 0 1-2 2H15a2 2 0 0 1-2-2L11 22z" stroke="#c7d2fe"/>
        <!-- Front Grab Notch -->
        <path d="M11 24h8l2.5 5h5l2.5-5h8" stroke="#c7d2fe" stroke-width="2"/>
      </svg>
    `,
    // 3. Rules & Control Center (Equalizer sliders + toggle switch)
    'rules_control': `
      <svg class="w-full h-full" viewBox="0 0 48 48" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <!-- Slider 1 -->
        <line x1="14" y1="14" x2="14" y2="34" stroke="#c7d2fe"/>
        <circle cx="14" cy="27" r="2.5" stroke="#fde68a" stroke-width="2" fill="#0f172a"/>
        <!-- Slider 2 -->
        <line x1="21" y1="14" x2="21" y2="34" stroke="#c7d2fe"/>
        <circle cx="21" cy="20" r="2.5" stroke="#fde68a" stroke-width="2" fill="#0f172a"/>
        <!-- Slider 3 -->
        <line x1="28" y1="22" x2="28" y2="34" stroke="#c7d2fe"/>
        <circle cx="28" cy="29" r="2.5" stroke="#fde68a" stroke-width="2" fill="#0f172a"/>
        <!-- Toggle Switch Capsule Top Right -->
        <rect x="25" y="13" width="13" height="7" rx="3.5" stroke="#c7d2fe"/>
        <circle cx="34" cy="16.5" r="2" stroke="#fde68a" fill="#fde68a"/>
      </svg>
    `,
    // 4. Advanced Filter (Funnel with gold top rim)
    'filter': `
      <svg class="w-full h-full" viewBox="0 0 48 48" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <line x1="11" y1="14" x2="37" y2="14" stroke="#fde68a" stroke-width="2.5"/>
        <path d="M12 15l10 12v9h4v-9l10-12" stroke="#c7d2fe" stroke-width="2"/>
        <line x1="17" y1="20" x2="31" y2="20" stroke="#fde68a" stroke-width="1.8"/>
      </svg>
    `,
    // 5. Recycling Bin (Fluted wastebasket with lid handle)
    'trash': `
      <svg class="w-full h-full" viewBox="0 0 48 48" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M20 13h8v-2a1 1 0 0 0-1-1h-6a1 1 0 0 0-1 1v2z" stroke="#c7d2fe"/>
        <line x1="11" y1="15" x2="37" y2="15" stroke="#c7d2fe" stroke-width="2.2"/>
        <path d="M14 17l2.5 17a3 3 0 0 0 3 2.5h9a3 3 0 0 0 3-2.5L34 17" stroke="#c7d2fe"/>
        <line x1="20" y1="20" x2="21" y2="31" stroke="#fde68a" stroke-width="1.8"/>
        <line x1="24" y1="20" x2="24" y2="31" stroke="#fde68a" stroke-width="1.8"/>
        <line x1="28" y1="20" x2="27" y2="31" stroke="#fde68a" stroke-width="1.8"/>
      </svg>
    `,
    // 6. Quick Record (Glowing circle with warm gold plus)
    'quick_add': `
      <svg class="w-full h-full" viewBox="0 0 48 48" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="24" cy="24" r="16" stroke="#c7d2fe" stroke-width="2"/>
        <line x1="24" y1="16" x2="24" y2="32" stroke="#fde68a" stroke-width="2.5"/>
        <line x1="16" y1="24" x2="32" y2="24" stroke="#fde68a" stroke-width="2.5"/>
      </svg>
    `,
    // 7. Receipt Camera (Camera body with aperture blades)
    'camera': `
      <svg class="w-full h-full" viewBox="0 0 48 48" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M19 14l2-3h6l2 3" stroke="#c7d2fe"/>
        <rect x="10" y="14" width="28" height="21" rx="4" stroke="#c7d2fe" stroke-width="2"/>
        <circle cx="33" cy="18" r="1.3" fill="#fde68a"/>
        <circle cx="24" cy="25" r="7.5" stroke="#c7d2fe"/>
        <!-- Aperture Blades -->
        <path d="M24 18l3.5 4-1 5-4.5 1-2.5-4 1.5-4.5" stroke="#fde68a" stroke-width="1.6"/>
      </svg>
    `,
    // 8. Privacy & Offline Security (Shield with padlock)
    'offline_security': `
      <svg class="w-full h-full" viewBox="0 0 48 48" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M24 10c7 0 12 2 12 9 0 8-6 15-12 19-6-4-12-11-12-19 0-7 5-9 12-9z" stroke="#c7d2fe" stroke-width="2"/>
        <path d="M21 23v-3a3 3 0 0 1 6 0v3" stroke="#fde68a" stroke-width="1.8"/>
        <rect x="19" y="23" width="10" height="7.5" rx="1.5" stroke="#fde68a" stroke-width="1.8"/>
        <circle cx="24" cy="26.5" r="1" fill="#fde68a"/>
      </svg>
    `,
    // 9. Alert / Warning Triangle
    'alert': `
      <svg class="w-full h-full" viewBox="0 0 24 24" fill="none" stroke="#fde68a" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/>
        <line x1="12" y1="9" x2="12" y2="13"/>
        <line x1="12" y1="17" x2="12.01" y2="17"/>
      </svg>
    `,
    // 10. Success / Check Circle
    'check_circle': `
      <svg class="w-full h-full" viewBox="0 0 24 24" fill="none" stroke="#6ee7b7" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
        <polyline points="22 4 12 14.01 9 11.01"/>
      </svg>
    `,
    // 11. Calendar
    'calendar': `
      <svg class="w-full h-full" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <rect x="3" y="4" width="18" height="18" rx="2" ry="2"/>
        <line x1="16" y1="2" x2="16" y2="6"/>
        <line x1="8" y1="2" x2="8" y2="6"/>
        <line x1="3" y1="10" x2="21" y2="10"/>
      </svg>
    `,
    // 12. Refresh
    'refresh': `
      <svg class="w-full h-full" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <polyline points="23 4 23 10 17 10"/>
        <polyline points="1 20 1 14 7 14"/>
        <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/>
      </svg>
    `,
    // 13. Search
    'search': `
      <svg class="w-full h-full" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="11" cy="11" r="8"/>
        <line x1="21" y1="21" x2="16.65" y2="16.65"/>
      </svg>
    `,
    // 14. Eye
    'eye': `
      <svg class="w-full h-full" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/>
        <circle cx="12" cy="12" r="3"/>
      </svg>
    `,
    // 15. Tag
    'tag': `
      <svg class="w-full h-full" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z"/>
        <line x1="7" y1="7" x2="7.01" y2="7"/>
      </svg>
    `
  };

  /**
   * 渲染带圆角平滑背景的图标容器 (Squircle Icon)
   */
  function renderSquircleIcon(catName, size = 'w-10 h-10', iconPadding = '') {
    const icon = IconRegistry.getCategoryIcon(catName);
    return `
      <div class="${size} rounded-2xl bg-slate-700/50 flex items-center justify-center text-lg shrink-0 border border-slate-600/40 shadow-sm ${iconPadding}" data-cat-icon="${catName}">
        ${icon}
      </div>
    `;
  }

  /**
   * 渲染小尺寸分类图标
   */
  function getSmallCatSvg(catName) {
    const icon = IconRegistry.getCategoryIcon(catName);
    return `<span class="w-full h-full flex items-center justify-center text-sm" data-cat-icon="${catName}">${icon}</span>`;
  }

  /**
   * DOM SVG 界面增强初始化函数
   */
  function initSvgUI() {
    if (!window.SYSTEM_SVGS || !window.FAITHFUL_CAT_SVGS) return;

    // 1. Navigation Icons
    const navTx = document.getElementById('nav-icon-transactions');
    if (navTx) navTx.innerHTML = window.SYSTEM_SVGS['ledger'];
    const navDr = document.getElementById('nav-icon-drafts');
    if (navDr) navDr.innerHTML = window.SYSTEM_SVGS['drafts_inbox'];
    const navRu = document.getElementById('nav-icon-rules');
    if (navRu) navRu.innerHTML = window.SYSTEM_SVGS['rules_control'];

    // 2. Top App Bar Buttons
    const filterIcon = document.getElementById('top-bar-filter-icon');
    if (filterIcon) filterIcon.innerHTML = window.SYSTEM_SVGS['filter'];
    const trashIcon = document.getElementById('top-bar-trash-icon');
    if (trashIcon) trashIcon.innerHTML = window.SYSTEM_SVGS['trash'];

    // 3. Status Bar Offline Security
    const secIcon = document.getElementById('status-bar-sec-icon');
    if (secIcon) secIcon.innerHTML = window.SYSTEM_SVGS['offline_security'];

    // 4. Quick Add Floating Button
    const quickPlusIcon = document.getElementById('quick-record-plus-icon');
    if (quickPlusIcon) quickPlusIcon.innerHTML = window.SYSTEM_SVGS['quick_add'];

    // 5. Empty States & Alerts
    const emptyLedger = document.getElementById('empty-state-ledger-icon');
    if (emptyLedger) emptyLedger.innerHTML = window.SYSTEM_SVGS['ledger'];
    const noMatchSearch = document.getElementById('no-match-search-icon');
    if (noMatchSearch) noMatchSearch.innerHTML = window.SYSTEM_SVGS['search'];
    const draftEmptyCheck = document.getElementById('draft-empty-check-icon');
    if (draftEmptyCheck) draftEmptyCheck.innerHTML = window.SYSTEM_SVGS['check_circle'];
    const dedupWarn = document.getElementById('dedup-warn-icon');
    if (dedupWarn) dedupWarn.innerHTML = window.SYSTEM_SVGS['alert'];
    const orderSecShield = document.getElementById('order-sec-shield-icon');
    if (orderSecShield) orderSecShield.innerHTML = window.SYSTEM_SVGS['offline_security'];
    const confGear = document.getElementById('conf-modal-gear-icon');
    if (confGear) confGear.innerHTML = window.SYSTEM_SVGS['rules_control'];
    const manualCam = document.getElementById('manual-cam-icon');
    if (manualCam) manualCam.innerHTML = window.SYSTEM_SVGS['camera'];
    const manualThumb = document.getElementById('manual-img-thumb-icon');
    if (manualThumb) manualThumb.innerHTML = window.SYSTEM_SVGS['camera'];
    const vlmEye = document.getElementById('vlm-eye-btn');
    if (vlmEye) vlmEye.innerHTML = window.SYSTEM_SVGS['eye'];
    const resetDrafts = document.getElementById('btn-reset-drafts-icon');
    if (resetDrafts) resetDrafts.innerHTML = window.SYSTEM_SVGS['refresh'];
    const rerunRules = document.getElementById('rerun-rules-icon');
    if (rerunRules) rerunRules.innerHTML = window.SYSTEM_SVGS['refresh'];
    const guardShield = document.getElementById('guard-shield-svg-icon');
    if (guardShield) guardShield.innerHTML = window.SYSTEM_SVGS['offline_security'];
    const dedupToastWarn = document.getElementById('dedup-toast-warn-icon');
    if (dedupToastWarn) dedupToastWarn.innerHTML = window.SYSTEM_SVGS['alert'];
    const llmTopErr = document.getElementById('llm-top-error-icon');
    if (llmTopErr) llmTopErr.innerHTML = `<svg class="w-full h-full" viewBox="0 0 24 24" fill="none" stroke="#f43f5e" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>`;
    const dayCal = document.getElementById('day-focus-cal-icon');
    if (dayCal) dayCal.innerHTML = window.SYSTEM_SVGS['calendar'];

    const discardBtn = document.getElementById('btn-discard-draft');
    if (discardBtn) {
      discardBtn.innerHTML = `
        <div class="w-3.5 h-3.5 mr-1.5">${window.SYSTEM_SVGS['trash']}</div>
        <span>丢弃</span>
      `;
    }

    // 6. Suggested Icon in Draft View
    const curCat = document.getElementById('select-draft-category')?.value || '餐饮美食';
    const sugIcon = document.getElementById('suggested-icon');
    if (sugIcon) {
      sugIcon.className = "text-sm shrink-0";
      sugIcon.innerHTML = IconRegistry.getCategoryIcon(curCat);
    }

    // 6.1 Enhance rule list badges with category icons
    const ruleBadges = document.querySelectorAll('#rules-list-container .space-x-1\\.5 > span:last-child');
    ruleBadges.forEach(badge => {
      const text = badge.textContent.trim();
      let cat = '餐饮美食';
      if (text.includes('交通') || text.includes('出行')) cat = '交通出行';
      else if (text.includes('餐饮') || text.includes('咖啡') || text.includes('快餐')) cat = '餐饮美食';
      else if (text.includes('购物')) cat = '日常购物';
      else if (text.includes('娱乐')) cat = '休闲娱乐';
      if (!badge.querySelector('span[data-cat-icon]')) {
        const iconSpan = document.createElement('span');
        iconSpan.className = "w-3.5 h-3.5 inline-flex items-center justify-center mr-1 shrink-0";
        iconSpan.setAttribute('data-cat-icon', cat);
        iconSpan.innerHTML = IconRegistry.getCategoryIcon(cat);
        badge.classList.add('inline-flex', 'items-center');
        badge.insertBefore(iconSpan, badge.firstChild);
      }
    });

    // 7. 刷新全系统所有 data-cat-icon 与 data-ui-icon 节点
    IconRegistry.refreshAllIcons();
  }

  // 挂载至全局对象
  window.SINGWALLET_ICON_CONFIG = {
    initialDefaultEmojis: INITIAL_DEFAULT_EMOJIS,
    categoryEmojis: categoryEmojis,
    uiStatusEmojis: UI_STATUS_EMOJIS,
    uiStatusSvgs: UI_STATUS_SVGS,
    faithfulCatSvgs: FAITHFUL_CAT_SVGS,
    systemSvgs: SYSTEM_SVGS
  };

  IconRegistry.DEFAULT_TAG_BADGE_SVG = DEFAULT_TAG_BADGE_SVG;
  window.IconRegistry = IconRegistry;
  window.CATEGORY_ICON_MAP = CATEGORY_ICON_MAP;
  window.parentCategoryIcons = parentCategoryIcons;
  window.FAITHFUL_CAT_SVGS = FAITHFUL_CAT_SVGS;
  window.ELEGANT_CAT_SVGS = FAITHFUL_CAT_SVGS;
  window.UI_STATUS_SVGS = UI_STATUS_SVGS;
  window.SYSTEM_SVGS = SYSTEM_SVGS;
  window.renderSquircleIcon = renderSquircleIcon;
  window.getSmallCatSvg = getSmallCatSvg;
  window.initSvgUI = initSvgUI;
  window.getStatusIcon = (key) => IconRegistry.getStatusIcon(key);
  window.getCategoryIcon = (cat) => IconRegistry.getCategoryIcon(cat);

  // 立即执行一次刷新，并在 DOMContentLoaded 时再次执行
  if (typeof document !== 'undefined') {
    IconRegistry.refreshAllIcons();
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', function () {
        IconRegistry.refreshAllIcons();
      });
    }
  }

})(typeof window !== 'undefined' ? window : this);
