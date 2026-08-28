# 系统功能介绍动画

动画页已嵌入 **IM Web Console**，源码位于 `apps/web/im-console/public/intro/index.html`。

| 访问方式 | 链接 |
| --- | --- |
| **GitHub 在线观看** | https://memacs.github.io/im/intro/ |
| **GIF 预览（11 屏 × 2s）** | [intro.gif](../../apps/web/im-console/public/intro/intro.gif) |
| **本地开发** | `mise run web:dev` → http://localhost:5173/intro |
| **重新生成 GIF** | `mise run web:intro-gif` |

GitHub Pages 由 [`.github/workflows/pages-intro.yml`](../../.github/workflows/pages-intro.yml) 发布；首次须在仓库 Settings → Pages 启用 **GitHub Actions** 源。
