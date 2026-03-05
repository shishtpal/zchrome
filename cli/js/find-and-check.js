(function(role, name, nth, checked) {
  var IMPLICIT_ROLES = {
    'checkbox': 'input[type="checkbox"]',
    'radio': 'input[type="radio"]',
    'switch': 'input[type="checkbox"]'
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
    // For checkboxes/radios, also check parent label
    if (el.type === 'checkbox' || el.type === 'radio') {
      var parent = el.closest('label');
      if (parent) return parent.textContent.trim();
    }
    return el.textContent.trim();
  }

  function matchesName(el, targetName) {
    // First check the accessible label
    if (getLabel(el) === targetName) return true;
    // For radio/checkbox, also match by name attribute or id
    if (el.type === 'checkbox' || el.type === 'radio') {
      if (el.getAttribute('name') === targetName) return true;
      if (el.id === targetName) return true;
    }
    return false;
  }

  var els = queryAll(document, '[role="' + role + '"]');
  if (IMPLICIT_ROLES[role]) {
    var implicit = queryAll(document, IMPLICIT_ROLES[role]);
    implicit = implicit.filter(function(el) { return !el.hasAttribute('role'); });
    els = els.concat(implicit);
  }

  if (name) {
    els = els.filter(function(el) { return matchesName(el, name); });
  }

  var el = els[nth || 0];
  if (el && el.checked !== checked) el.click();
})
