/// 教务系统页面探测脚本（正方教务通用页面结构）。
///
/// 探测是编写解析器的前提：先抓取真实 DOM / AJAX / 存储结构，再据此写解析逻辑。
class AcademicProbeScripts {
  const AcademicProbeScripts._();

  /// 在页面加载时尽早注入：记录 XHR / fetch / jQuery.ajax 请求，并转发 console.log。
  static const String installHooks = r'''
(function () {
  if (window.__academicHooked) { return; }
  window.__academicHooked = true;
  window.__academicAjax = window.__academicAjax || [];
  window.__academicLogs = window.__academicLogs || [];

  function push(url, method) {
    if (!url) { return; }
    try {
      window.__academicAjax.push({ method: String(method || 'GET'), url: String(url) });
    } catch (e) {}
  }

  try {
    var origOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url) {
      push(url, method);
      return origOpen.apply(this, arguments);
    };
  } catch (e) {}

  try {
    if (window.fetch) {
      var origFetch = window.fetch;
      window.fetch = function (input, init) {
        var url = (typeof input === 'string') ? input : (input && input.url);
        push(url, (init && init.method) || 'GET');
        return origFetch.apply(this, arguments);
      };
    }
  } catch (e) {}

  function hookJquery() {
    try {
      if (window.jQuery && !window.__academicJqHooked) {
        window.__academicJqHooked = true;
        var origAjax = window.jQuery.ajax;
        window.jQuery.ajax = function (url, options) {
          var u = (typeof url === 'string') ? url : (url && url.url);
          var m = (url && url.method) || (options && options.method) || (options && options.type) || 'GET';
          push(u, m);
          return origAjax.apply(window.jQuery, arguments);
        };
      }
    } catch (e) {}
  }
  hookJquery();
  setTimeout(hookJquery, 800);
  setTimeout(hookJquery, 2500);

  try {
    var origLog = console.log;
    console.log = function () {
      try {
        var text = Array.prototype.map.call(arguments, function (a) {
          try {
            return (typeof a === 'string') ? a : JSON.stringify(a);
          } catch (e) {
            return String(a);
          }
        }).join(' ');
        if (window.__academicLogs.length < 200) {
          window.__academicLogs.push(text.slice(0, 500));
        }
        AcademicProbe.postMessage('LOG:' + text.slice(0, 500));
      } catch (e) {}
      return origLog.apply(console, arguments);
    };
  } catch (e) {}
})();
''';

  /// 采集页面结构并回传 Flutter。
  static const String probe = r'''
(function () {
  var out = {
    url: String(location.href),
    title: String(document.title || ''),
    userAgent: String(navigator.userAgent || ''),
    tables: [],
    iframes: [],
    ajax: [],
    keywords: [],
    storage: {},
    logs: [],
    containerHtml: '',
    bodyHtmlSnippet: ''
  };

  function compact(text, limit) {
    var value = String(text || '').replace(/\s+/g, ' ').trim();
    return value.length > limit ? value.slice(0, limit) + '…' : value;
  }

  function collectTables(doc, prefix) {
    var list = [];
    try {
      var tables = doc.querySelectorAll('table');
      for (var i = 0; i < tables.length; i++) {
        var table = tables[i];
        var rows = [];
        var trs = table.querySelectorAll('tr');
        for (var r = 0; r < trs.length && r < 40; r++) {
          var cells = [];
          var tds = trs[r].querySelectorAll('td,th');
          for (var c = 0; c < tds.length && c < 20; c++) {
            cells.push(compact(tds[c].innerText, 500));
          }
          if (cells.length) { rows.push(cells); }
        }
        list.push({
          source: prefix,
          index: i,
          id: String(table.id || ''),
          cls: compact(table.className, 80),
          rowCount: trs.length,
          colCount: rows.length ? rows[0].length : 0,
          rows: rows
        });
      }
    } catch (e) {}
    return list;
  }

  out.tables = out.tables.concat(collectTables(document, 'main'));

  try {
    var frames = document.querySelectorAll('iframe');
    for (var f = 0; f < frames.length; f++) {
      var frame = frames[f];
      var info = { index: f, id: String(frame.id || ''), src: String(frame.src || ''), accessible: false };
      try {
        var doc = frame.contentDocument || (frame.contentWindow && frame.contentWindow.document);
        if (doc) {
          info.accessible = true;
          info.url = String(doc.location.href || '');
          var inner = collectTables(doc, 'iframe#' + f);
          info.tableCount = inner.length;
          out.tables = out.tables.concat(inner);
        }
      } catch (e) {
        info.error = String(e);
      }
      out.iframes.push(info);
    }
  } catch (e) {}

  try {
    if (window.__academicAjax) { out.ajax = out.ajax.concat(window.__academicAjax); }
  } catch (e) {}
  try {
    var resources = performance.getEntriesByType('resource');
    for (var n = 0; n < resources.length; n++) {
      var entry = resources[n];
      if (entry.initiatorType === 'xmlhttprequest' || entry.initiatorType === 'fetch') {
        out.ajax.push({ method: 'GET(performance)', url: String(entry.name) });
      }
    }
  } catch (e) {}
  var seenAjax = {};
  out.ajax = out.ajax.filter(function (item) {
    var key = item.method + ' ' + item.url;
    if (seenAjax[key]) { return false; }
    seenAjax[key] = true;
    return true;
  }).slice(0, 80);

  var keywords = ['课程', '上课', '教师', '教室', '星期', '节次', '周次', '课表'];
  var seenNodes = {};
  for (var k = 0; k < keywords.length; k++) {
    try {
      var xp = document.evaluate(
        "//*[contains(text(),'" + keywords[k] + "')]",
        document,
        null,
        XPathResult.ORDERED_NODE_SNAPSHOT_TYPE,
        null
      );
      var count = Math.min(xp.snapshotLength, 8);
      for (var i = 0; i < count; i++) {
        var el = xp.snapshotItem(i);
        if (!el || el.nodeType !== 1) { continue; }
        var key = el.tagName + '|' + String(el.id || '') + '|' + String(el.className || '');
        if (seenNodes[key]) { continue; }
        seenNodes[key] = true;
        out.keywords.push({
          keyword: keywords[k],
          tag: String(el.tagName || ''),
          id: String(el.id || ''),
          cls: compact(el.className, 80),
          text: compact(el.innerText, 80)
        });
      }
    } catch (e) {}
  }

  try {
    for (var li = 0; li < localStorage.length; li++) {
      var lk = localStorage.key(li);
      out.storage['local:' + lk] = compact(localStorage.getItem(lk), 200);
    }
  } catch (e) {}
  try {
    for (var si = 0; si < sessionStorage.length; si++) {
      var sk = sessionStorage.key(si);
      out.storage['session:' + sk] = compact(sessionStorage.getItem(sk), 200);
    }
  } catch (e) {}

  try {
    out.logs = (window.__academicLogs || []).slice(-60);
  } catch (e) {}

  try {
    var containers = document.querySelectorAll(
      '#kbtable, #kbcontent, .kbcontent, [id*="kb"], [class*="kb"], [id*="Kb"], [class*="Kb"]'
    );
    var html = '';
    for (var c = 0; c < containers.length && c < 4; c++) {
      html += '<!-- ' + (containers[c].id || containers[c].className) + ' -->\n' + containers[c].outerHTML + '\n';
      if (html.length > 40000) { break; }
    }
    out.containerHtml = html.slice(0, 40000);
  } catch (e) {}

  try {
    out.bodyHtmlSnippet = document.body ? String(document.body.innerHTML).slice(0, 6000) : '';
  } catch (e) {}

  try {
    AcademicProbe.postMessage(JSON.stringify(out));
  } catch (e) {
    try { AcademicProbe.postMessage('ERROR:' + String(e)); } catch (e2) {}
  }
})();
''';
}
