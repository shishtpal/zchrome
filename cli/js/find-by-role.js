(function(role, name, nth) {
  // Mapping of ARIA roles to native HTML element selectors
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

  // Query all elements including shadow DOM
  function queryAll(root, selector) {
    var results = Array.from(root.querySelectorAll(selector));
    root.querySelectorAll('*').forEach(function(el) {
      if (el.shadowRoot) {
        results = results.concat(queryAll(el.shadowRoot, selector));
      }
    });
    return results;
  }

  // Get accessible name for matching
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

  // Find elements with explicit role attribute
  var els = queryAll(document, '[role="' + role + '"]');

  // Also find elements with implicit roles (native HTML)
  if (IMPLICIT_ROLES[role]) {
    var implicit = queryAll(document, IMPLICIT_ROLES[role]);
    implicit = implicit.filter(function(el) {
      return !el.hasAttribute('role');
    });
    els = els.concat(implicit);
  }

  // Filter by name if specified
  if (name) {
    els = els.filter(function(el) {
      return getLabel(el) === name;
    });
  }

  // Return nth element's bounding rect
  var el = els[nth || 0];
  if (!el) return null;
  var rect = el.getBoundingClientRect();
  return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
})
