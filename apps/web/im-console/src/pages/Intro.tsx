import { Link } from "react-router-dom";

/** 全屏嵌入 public/intro/index.html 功能介绍动画 */
export function IntroPage() {
  return (
    <div className="intro-page">
      <Link className="intro-back" to="/login">
        ← 返回 Console
      </Link>
      <iframe
        className="intro-frame"
        src="/intro/index.html"
        title="IM 系统功能介绍"
      />
    </div>
  );
}
