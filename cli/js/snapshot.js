(function() {
  var NL = '\n';
  
  // Role mappings for HTML elements
  var ROLE_MAP = {
    'A': 'link',
    'BUTTON': 'button',
    'INPUT': function(e) {
      var t = (e.type || 'text').toLowerCase();
      if (t === 'checkbox') return 'checkbox';
      if (t === 'radio') return 'radio';
      if (t === 'submit' || t === 'button' || t === 'reset') return 'button';
      if (t === 'hidden') return null;
      return 'textbox';
    },
    'TEXTAREA': 'textbox',
    'SELECT': 'combobox',
    'H1': 'heading',
    'H2': 'heading',
    'H3': 'heading',
    'H4': 'heading',
    'H5': 'heading',
    'H6': 'heading',
    'UL': 'list',
    'OL': 'list',
    'LI': 'listitem',
    'TABLE': 'table',
    'NAV': 'navigation',
    'MAIN': 'main',
    'FORM': 'form',
    'IMG': 'img'
  };

  // Get ARIA role for an element
  function getRole(e) {
    var r = e.getAttribute('role');
    if (r) return r.toLowerCase();
    var m = ROLE_MAP[e.tagName];
    if (typeof m === 'function') return m(e);
    return m || null;
  }

  // Get accessible name for an element
  function getName(e) {
    // Check aria-label first
    var a = e.getAttribute('aria-label');
    if (a) return a;
    
    // Check placeholder
    var p = e.getAttribute('placeholder');
    if (p) return p;
    
    var t = e.tagName;
    
    // Links and buttons use text content
    if (t === 'A' || t === 'BUTTON') {
      var x = e.textContent.trim();
      if (x) return x;
    }
    
    // Images use alt text
    if (t === 'IMG') return e.getAttribute('alt');
    
    // Headings use text content
    if (/^H[1-6]$/.test(t)) return e.textContent.trim();
    
    // Inputs/textareas check for associated label
    if (t === 'INPUT' || t === 'TEXTAREA') {
      var id = e.id;
      if (id) {
        var l = document.querySelector('label[for="' + id + '"]');
        if (l) return l.textContent.trim();
      }
    }
    
    return e.getAttribute('title');
  }

  // Get additional attributes for verbose output
  function getAttrs(e) {
    var a = '';
    var n = e.getAttribute('name');
    if (n) a += ' [name="' + n + '"]';
    var p = e.getAttribute('placeholder');
    if (p) a += ' [placeholder="' + p.replace(/"/g, '') + '"]';
    var i = e.id;
    if (i) a += ' [id="' + i + '"]';
    var al = e.getAttribute('alt');
    if (al) a += ' [alt="' + al.replace(/"/g, '') + '"]';
    var t = e.type;
    if (t && e.tagName === 'INPUT') a += ' [type="' + t + '"]';
    return a;
  }

  // Check if element is visible
  function isVisible(e) {
    if (e.hidden) return false;
    try {
      var s = getComputedStyle(e);
      if (s.display === 'none' || s.visibility === 'hidden') return false;
    } catch (x) {}
    return ['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'SVG'].indexOf(e.tagName) === -1;
  }

  // Build accessibility tree recursively
  function build(e, depth, maxDepth) {
    if (maxDepth !== null && depth > maxDepth) return '';
    if (!isVisible(e)) return '';
    
    var result = '';
    var role = getRole(e);
    
    if (role) {
      var name = getName(e);
      var indent = '  '.repeat(depth);
      var attrs = getAttrs(e);
      
      if (name) {
        result += indent + '- ' + role + ' "' + name.replace(/"/g, '') + '"' + attrs + NL;
      } else {
        result += indent + '- ' + role + attrs + NL;
      }
    }
    
    var nextDepth = role ? depth + 1 : depth;
    
    // Process children
    for (var c of e.children) {
      result += build(c, nextDepth, maxDepth);
    }
    
    // Process shadow DOM
    if (e.shadowRoot) {
      for (var c of e.shadowRoot.children) {
        result += build(c, nextDepth, maxDepth);
      }
    }
    
    return result;
  }

  // Main execution
  var selector = SEL_ARG;
  var maxDepth = DEPTH_ARG;
  var root = selector ? document.querySelector(selector) : document.body;
  
  if (selector && !root) return '(not found)';
  return build(root, 0, maxDepth) || '(empty)';
})()
