// EasyWork 产品页：唯一职责——让命令可一键复制。
// 无依赖；脚本失效时命令仍可手动选择复制。
(function () {
  "use strict";

  // 无障碍状态播报（视觉上不可见）
  var live = document.createElement("p");
  live.setAttribute("role", "status");
  live.setAttribute("aria-live", "polite");
  live.style.cssText =
    "position:absolute;width:1px;height:1px;margin:-1px;padding:0;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap;border:0";
  document.body.appendChild(live);

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
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

  function payloadOf(block) {
    var nodes = block.querySelectorAll(".cmd");
    var lines = [];
    Array.prototype.forEach.call(nodes, function (node) {
      node.textContent.split("\n").forEach(function (line) {
        var t = line.trim();
        // 跳过空行与注释行：复制出来的是可直接执行的命令
        if (t && t.charAt(0) !== "#") {
          lines.push(t);
        }
      });
    });
    return lines.join("\n");
  }

  function flash(button, ok) {
    var label = button.getAttribute("data-label") || button.textContent;
    button.setAttribute("data-label", label);
    button.textContent = ok ? "已复制" : "复制失败";
    button.setAttribute("data-done", ok ? "true" : "false");
    window.setTimeout(function () {
      button.textContent = label;
      button.removeAttribute("data-done");
    }, 1600);
  }

  Array.prototype.forEach.call(document.querySelectorAll("[data-copy-block]"), function (block) {
    var button = block.querySelector(".copy");
    if (!button) {
      return;
    }
    button.addEventListener("click", function () {
      copyText(payloadOf(block)).then(
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
