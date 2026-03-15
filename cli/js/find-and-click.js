(function(role, name, nth, root) {
  root = root || document;
  var IMPLICIT_ROLES = {
    'link': 'a[href]',
    'button': 'button, input[type="button"], input[type="submit"], input[type="reset"]',
    'textbox': 'input:not([type]), input[type="text"], input[type="email"], input[type="password"], input[type="search"], input[type="tel"], input[type="url"], input[type="number"], textarea, [contenteditable="true"], [contenteditable=""]',
    'checkbox': 'input[type="checkbox"]',
    'radio': 'input[type="radio"]',
    'combobox': 'select',
    'listbox': 'select[multiple]',
    'heading': 'h1, h2, h3, h4, h5, h6',
    'img': 'img',
    'list': 'ul, ol',
    'listitem': 'li',
    'navigation': 'nav',
    'main': 'main',
    'form': 'form',
    'table': 'table',
    'row': 'tr',
    'cell': 'td',
    'columnheader': 'th'
  };

  function queryAll(r, selector) {
    var results = Array.from(r.querySelectorAll(selector));
    r.querySelectorAll('*').forEach(function(el) {
      if (el.shadowRoot) results = results.concat(queryAll(el.shadowRoot, selector));
    });
    return results;
  }

  function getLabel(el) {
    var a = el.getAttribute('aria-label');
    if (a) return a;
    var p = el.getAttribute('placeholder');
    if (p) return p;
    var id = el.id;
    if (id) {
      var doc = root.ownerDocument || root;
      var l = doc.querySelector('label[for="' + id + '"]');
      if (l) return l.textContent.trim();
    }
    return el.textContent.trim();
  }

  function matchesName(el, targetName) {
    if (getLabel(el) === targetName) return true;
    if (el.getAttribute('name') === targetName) return true;
    if (el.id === targetName) return true;
    return false;
  }

  var els = queryAll(root, '[role="' + role + '"]');
  if (IMPLICIT_ROLES[role]) {
    var implicit = queryAll(root, IMPLICIT_ROLES[role]);
    implicit = implicit.filter(function(el) { return !el.hasAttribute('role'); });
    els = els.concat(implicit);
  }

  if (name) {
    els = els.filter(function(el) { return matchesName(el, name); });
  }

  var el = els[nth || 0];
  if (!el) return false;

  // For anchor elements, navigate directly via href to bypass JS event interception
  if (el.tagName === 'A' && el.href) {
    window.location.href = el.href;
    return true;
  }

  // For other elements, dispatch a synthetic click event
  el.dispatchEvent(new MouseEvent('click', {
    bubbles: true,
    cancelable: true,
    view: window
  }));
  return true;
})
