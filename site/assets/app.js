// EasyWork 产品页：只做一件事——让安装命令可一键复制。
// 无依赖、无框架；脚本失败时页面仍可正常阅读与手动选择复制。
(function () {
  "use strict";

  var live = document.createElement("p");
  live.setAttribute("role", "status");
  live.setAttribute("aria-live", "polite");
  live.className = "sr-only";
  live.style.cssText =
    "position:absolute;width:1px;height:1px;margin:-1px;padding:0;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap;border:0";
  document.body.appendChild(live);

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    // 旧浏览器 / 非安全上下文兜底
    return new Promise(function (resolve, reject) {
      var ta = document.createElement("textarea");
      ta.value = text;
      ta.setAttribute("readonly", "");
      ta.style.cssText = "position:absolute;left:-9999px;top:0";
      document.body.appendChild(ta);
      ta.select();
      var ok = false;
      try {
        ok = document.execCommand("copy");
      } catch (e) {
        ok = false;
      }
      document.body.removeChild(ta);
      ok ? resolve() : reject(new Error("copy failed"));
    });
  }

  function flash(button, ok) {
    var original = button.getAttribute("data-label") || button.textContent;
    button.setAttribute("data-label", original);
    button.textContent = ok ? "已复制" : "复制失败";
    button.setAttribute("data-done", ok ? "true" : "false");
    window.setTimeout(function () {
      button.textContent = original;
      button.removeAttribute("data-done");
    }, 1600);
  }

  var blocks = document.querySelectorAll("[data-copy-block]");
  Array.prototype.forEach.call(blocks, function (block) {
    var button = block.querySelector(".copy");
    var code = block.querySelector("pre code");
    if (!button || !code) {
      return;
    }
    // 只取命令本身，忽略注释行，便于直接粘贴执行
    var lines = code.textContent.split("\n").filter(function (line) {
      return line.trim() && line.trim().indexOf("#") !== 0;
    });
    var payload = lines.join("\n").trim();

    button.addEventListener("click", function () {
      copyText(payload).then(
        function () {
          flash(button, true);
          live.textContent = "已复制到剪贴板";
        },
        function () {
          flash(button, false);
          live.textContent = "复制失败，请手动选择命令";
        }
      );
    });
  });
})();
