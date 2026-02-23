(function() {
  // Get element type (html, img, svg, canvas, iframe, shadow, placeholder)
  function getElementType(e) {
    var t = e.tagName;
    if (t === 'IMG') return 'img';
    if (t === 'SVG' || e.closest('svg')) return 'svg';
    if (t === 'CANVAS') return 'canvas';
    if (t === 'IFRAME') return 'iframe';
    if (e.shadowRoot || e.getRootNode() !== document) return 'shadow';
    if (t === 'INPUT' || t === 'TEXTAREA') {
      if (e.getAttribute('placeholder')) return 'placeholder';
    }
    return 'html';
  }

  // Get implicit ARIA role from element tag
  function getImplicitRole(e) {
    var t = e.tagName;
    if (t === 'A' && e.href) return 'link';
    if (t === 'BUTTON') return 'button';
    if (t === 'INPUT') {
      var type = (e.type || 'text').toLowerCase();
      if (type === 'checkbox') return 'checkbox';
      if (type === 'radio') return 'radio';
      if (type === 'submit' || type === 'button') return 'button';
      return 'textbox';
    }
    if (t === 'TEXTAREA') return 'textbox';
    if (t === 'SELECT') return 'combobox';
    return null;
  }

  // Get accessible name for element
  function getAccessibleName(e) {
    var a = e.getAttribute('aria-label');
    if (a) return a;
    var p = e.getAttribute('placeholder');
    if (p) return p;
    if (e.textContent) {
      var text = e.textContent.trim();
      if (text && text.length < 100) return text;
    }
    var id = e.id;
    if (id) {
      var l = document.querySelector('label[for="' + id + '"]');
      if (l) return l.textContent.trim();
    }
    return e.getAttribute('title');
  }

  // Build CSS selector for element
  function buildSelector(e) {
    if (e.id) return '#' + e.id;
    var parts = [];
    var tag = e.tagName.toLowerCase();
    if (e.getAttribute('role')) {
      parts.push(tag + '[role="' + e.getAttribute('role') + '"]');
    } else if (e.className && typeof e.className === 'string') {
      var firstClass = e.className.split(' ')[0];
      if (firstClass) parts.push(tag + '.' + firstClass);
      else parts.push(tag);
    } else {
      parts.push(tag);
    }
    if (e.getAttribute('name')) {
      parts[parts.length - 1] += '[name="' + e.getAttribute('name') + '"]';
    }
    return parts.join(' > ');
  }

  // Get element info object
  function getElementInfo(el) {
    var tag = el.tagName.toLowerCase();
    var role = el.getAttribute('role') || getImplicitRole(el);
    var name = getAccessibleName(el);
    var id = el.id || null;
    var cls = el.className && typeof el.className === 'string' ? el.className : null;
    var type = getElementType(el);
    var selector = buildSelector(el);
    var rect = el.getBoundingClientRect();

    return {
      type: type,
      tag: tag,
      role: role,
      name: name,
      id: id,
      className: cls,
      selector: selector,
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height
    };
  }

  // ELEMENT_VAR is replaced at runtime with the element reference
  var el = ELEMENT_VAR;
  if (!el) return null;
  return getElementInfo(el);
})()
