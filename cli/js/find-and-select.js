(function(role, name, nth, value) {
  var IMPLICIT_ROLES = {
    'combobox': 'select',
    'listbox': 'select[multiple]',
    'textbox': 'input:not([type]), input[type="text"], input[type="email"], input[type="password"], input[type="search"], input[type="tel"], input[type="url"], input[type="number"], textarea, [contenteditable="true"], [contenteditable=""]'
  };

  function queryAll(root, selector) {
    var results = Array.from(root.querySelectorAll(selector));
    root.querySelectorAll('*').forEach(function(el) {
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
      var l = document.querySelector('label[for="' + id + '"]');
      if (l) return l.textContent.trim();
    }
    return el.textContent.trim();
  }

  var els = queryAll(document, '[role="' + role + '"]');
  if (IMPLICIT_ROLES[role]) {
    var implicit = queryAll(document, IMPLICIT_ROLES[role]);
    implicit = implicit.filter(function(el) { return !el.hasAttribute('role'); });
    els = els.concat(implicit);
  }

  if (name) {
    els = els.filter(function(el) { return getLabel(el) === name; });
  }

  var el = els[nth || 0];
  if (el) {
    el.value = value;
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
})
