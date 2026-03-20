// Layout path resolution and tree extraction
// Path format: "0/2/1" means body > 1st visible child > 3rd visible child > 2nd visible child

(function(action, path, maxDepth) {
  // Get visible children (width/height > 0)
  function getVisibleChildren(el) {
    return Array.from(el.children).filter(function(c) {
      var r = c.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    });
  }

  // Resolve path to element
  // path = "0/2/1" or "" (for body itself)
  function resolveLayoutPath(pathStr) {
    if (!pathStr || pathStr === '') return document.body;
    
    var indices = pathStr.split('/').map(Number);
    var el = document.body;
    
    for (var i = 0; i < indices.length; i++) {
      var idx = indices[i];
      var children = getVisibleChildren(el);
      if (idx >= children.length) return null;
      el = children[idx];
    }
    return el;
  }

  // Get element position for resolved path
  function getPositionForPath(pathStr) {
    var el = resolveLayoutPath(pathStr);
    if (!el) return null;
    var rect = el.getBoundingClientRect();
    return {
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
      tag: el.tagName.toLowerCase()
    };
  }

  // Get truncated text content (leaf nodes only)
  function getTextPreview(el, maxLen) {
    // Only show text for leaf elements (no visible children)
    var visibleKids = getVisibleChildren(el);
    if (visibleKids.length > 0) return '';
    
    var text = (el.textContent || '').trim();
    if (!text) return '';
    if (text.length <= maxLen) return text;
    return text.substring(0, maxLen) + '...';
  }

  // Generate layout tree recursively
  function getLayoutTree(root, prefix, depth, maxD) {
    if (maxD !== null && depth > maxD) return null;
    
    var rect = root.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return null;
    
    var result = {
      path: prefix,
      tag: root.tagName.toLowerCase(),
      id: root.id || '',
      cls: root.className && typeof root.className === 'string' ? root.className : '',
      text: getTextPreview(root, 30),
      x: Math.round(rect.x),
      y: Math.round(rect.y),
      w: Math.round(rect.width),
      h: Math.round(rect.height),
      children: []
    };
    
    var children = getVisibleChildren(root);
    for (var i = 0; i < children.length; i++) {
      var childPath = prefix ? prefix + '/' + i : String(i);
      var childTree = getLayoutTree(children[i], childPath, depth + 1, maxD);
      if (childTree) {
        result.children.push(childTree);
      }
    }
    return result;
  }

  // Convert element to layout path by walking up the tree
  function elementToLayoutPath(el) {
    if (!el || el === document.body) return '';
    
    var parts = [];
    var current = el;
    
    while (current && current !== document.body) {
      var parent = current.parentElement;
      if (!parent) break;
      
      var siblings = getVisibleChildren(parent);
      var idx = siblings.indexOf(current);
      if (idx === -1) return null; // Element not visible
      
      parts.unshift(idx);
      current = parent;
    }
    
    return parts.join('/');
  }

  // Resolve XPath to element, then get its layout path
  function xpathToLayout(xpath) {
    var result = document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null);
    var el = result.singleNodeValue;
    if (!el) return null;
    
    var layoutPath = elementToLayoutPath(el);
    if (layoutPath === null) return null;
    
    return {
      path: layoutPath ? 'L' + layoutPath : 'L',
      selector: layoutPath ? '@L' + layoutPath : '@L'
    };
  }

  // Action dispatch
  if (action === 'resolve') {
    return getPositionForPath(path);
  } else if (action === 'tree') {
    var root = path ? document.querySelector(path) : document.body;
    if (!root) return null;
    return getLayoutTree(root, '', 0, maxDepth);
  } else if (action === 'tree-json') {
    var root = path ? document.querySelector(path) : document.body;
    if (!root) return null;
    return JSON.stringify(getLayoutTree(root, '', 0, maxDepth), null, 2);
  } else if (action === 'xpath') {
    return xpathToLayout(path);
  } else if (action === 'css2layout') {
    var el = document.querySelector(path);
    if (!el) return null;
    var layoutPath = elementToLayoutPath(el);
    if (layoutPath === null) return null;
    return {
      path: layoutPath ? 'L' + layoutPath : 'L',
      selector: layoutPath ? '@L' + layoutPath : '@L'
    };
  } else if (action === 'exists') {
    // Check if path resolves to a visible element
    var el = resolveLayoutPath(path);
    return el !== null;
  } else if (action === 'parent') {
    // Get parent path
    if (!path || path === '') return { selector: null }; // body has no parent
    var lastSlash = path.lastIndexOf('/');
    if (lastSlash === -1) return { selector: '@L' }; // parent is body
    var parentPath = path.substring(0, lastSlash);
    return { selector: parentPath ? '@L' + parentPath : '@L' };
  } else if (action === 'next' || action === 'prev') {
    // Get sibling path
    if (!path || path === '') return null; // body has no siblings
    var lastSlash = path.lastIndexOf('/');
    var parentPath = lastSlash === -1 ? '' : path.substring(0, lastSlash);
    var idx = parseInt(lastSlash === -1 ? path : path.substring(lastSlash + 1));
    var newIdx = action === 'next' ? idx + 1 : idx - 1;
    if (newIdx < 0) return null;
    var newPath = parentPath ? parentPath + '/' + newIdx : String(newIdx);
    // Validate sibling exists
    if (!resolveLayoutPath(newPath)) return null;
    return { selector: '@L' + newPath };
  } else if (action === 'children') {
    // List child paths
    var el = resolveLayoutPath(path);
    if (!el) return null;
    var kids = getVisibleChildren(el);
    return kids.map(function(_, i) {
      var childPath = path ? path + '/' + i : String(i);
      return '@L' + childPath;
    });
  } else if (action === 'tocss') {
    // Generate CSS selector from layout path
    var el = resolveLayoutPath(path);
    if (!el) return null;
    var parts = ['body'];
    if (path && path !== '') {
      var indices = path.split('/').map(Number);
      for (var i = 0; i < indices.length; i++) {
        parts.push(':nth-child(' + (indices[i] + 1) + ')'); // CSS is 1-indexed
      }
    }
    return { selector: parts.join(' > ') };
  } else if (action === 'find') {
    // Search for elements containing text
    var searchText = (path || '').toLowerCase();
    var results = [];
    
    function searchTree(el, pathStr) {
      var rect = el.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) return;
      
      // Check for direct text content (not inherited from children)
      var hasDirectText = false;
      var directText = '';
      for (var i = 0; i < el.childNodes.length; i++) {
        if (el.childNodes[i].nodeType === 3) { // Text node
          directText += el.childNodes[i].textContent;
        }
      }
      directText = directText.trim();
      
      // Also check value for inputs
      var value = el.value || '';
      
      if (directText.toLowerCase().indexOf(searchText) !== -1 ||
          value.toLowerCase().indexOf(searchText) !== -1) {
        var displayText = directText || value || (el.textContent || '').trim();
        results.push({
          selector: pathStr ? '@L' + pathStr : '@L',
          tag: el.tagName.toLowerCase(),
          id: el.id || '',
          cls: typeof el.className === 'string' ? el.className : '',
          text: displayText.substring(0, 40) + (displayText.length > 40 ? '...' : '')
        });
      }
      
      var children = getVisibleChildren(el);
      for (var i = 0; i < children.length; i++) {
        var childPath = pathStr ? pathStr + '/' + i : String(i);
        searchTree(children[i], childPath);
      }
    }
    
    searchTree(document.body, '');
    return results;
  } else if (action === 'at') {
    // Find element at coordinates (path = "x,y")
    var coords = (path || '0,0').split(',').map(Number);
    var x = coords[0], y = coords[1];
    var el = document.elementFromPoint(x, y);
    if (!el || el === document.documentElement || el === document.body) {
      return { selector: '@L', tag: 'body' };
    }
    
    var layoutPath = elementToLayoutPath(el);
    if (layoutPath === null) return null;
    
    var rect = el.getBoundingClientRect();
    return {
      selector: layoutPath ? '@L' + layoutPath : '@L',
      tag: el.tagName.toLowerCase(),
      id: el.id || '',
      cls: typeof el.className === 'string' ? el.className : '',
      x: Math.round(rect.x),
      y: Math.round(rect.y),
      w: Math.round(rect.width),
      h: Math.round(rect.height)
    };
  } else if (action === 'highlight') {
    // Show visual overlay with @L paths
    // path = specific path to highlight, or empty for all top-level
    // maxDepth = depth limit
    
    // Remove existing highlights
    document.querySelectorAll('.__zchrome_layout_hl').forEach(function(e) { e.remove(); });
    
    var colors = ['rgba(66,133,244,0.25)', 'rgba(234,67,53,0.25)', 'rgba(52,168,83,0.25)', 'rgba(251,188,5,0.25)'];
    var borderColors = ['rgb(66,133,244)', 'rgb(234,67,53)', 'rgb(52,168,83)', 'rgb(251,188,5)'];
    
    function addHighlight(el, layoutPath, depth) {
      var rect = el.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) return;
      
      var color = colors[depth % colors.length];
      var borderColor = borderColors[depth % borderColors.length];
      
      var hl = document.createElement('div');
      hl.className = '__zchrome_layout_hl';
      hl.style.cssText = 'position:fixed;left:'+rect.left+'px;top:'+rect.top+'px;width:'+rect.width+'px;height:'+rect.height+'px;background:'+color+';border:2px solid '+borderColor+';pointer-events:none;z-index:2147483640;box-sizing:border-box;';
      
      // Label in top-left corner
      var label = document.createElement('span');
      label.style.cssText = 'position:absolute;top:0;left:0;background:'+borderColor+';color:white;font:bold 10px monospace;padding:1px 4px;white-space:nowrap;';
      label.textContent = '@L' + (layoutPath || '');
      hl.appendChild(label);
      
      document.body.appendChild(hl);
    }
    
    function highlightTree(el, pathStr, depth, maxD) {
      if (maxD !== null && depth > maxD) return;
      addHighlight(el, pathStr, depth);
      
      var children = getVisibleChildren(el);
      for (var i = 0; i < children.length; i++) {
        var childPath = pathStr ? pathStr + '/' + i : String(i);
        highlightTree(children[i], childPath, depth + 1, maxD);
      }
    }
    
    var root = path ? resolveLayoutPath(path) : document.body;
    if (!root) return false;
    
    var startPath = path || '';
    var startDepth = path ? path.split('/').length : 0;
    highlightTree(root, startPath, startDepth, maxDepth);
    
    // Auto-remove after 5 seconds
    setTimeout(function() {
      document.querySelectorAll('.__zchrome_layout_hl').forEach(function(e) { e.remove(); });
    }, 5000);
    
    return true;
  } else if (action === 'pick') {
    // Interactive element picker - returns Promise
    return new Promise(function(resolve) {
      // Remove any existing picker
      var existing = document.getElementById('__zchrome_pick_overlay');
      if (existing) existing.remove();
      
      // Create overlay
      var overlay = document.createElement('div');
      overlay.id = '__zchrome_pick_overlay';
      overlay.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.05);z-index:2147483646;cursor:crosshair;';
      
      // Instruction label
      var label = document.createElement('div');
      label.style.cssText = 'position:fixed;top:10px;left:50%;transform:translateX(-50%);background:rgba(0,0,0,0.85);color:white;padding:10px 20px;border-radius:6px;font:14px sans-serif;z-index:2147483647;box-shadow:0 2px 10px rgba(0,0,0,0.3);';
      label.textContent = 'Click on an element to get its @L path (ESC to cancel)';
      overlay.appendChild(label);
      
      // Hover highlight
      var hoverHl = document.createElement('div');
      hoverHl.style.cssText = 'position:fixed;background:rgba(66,133,244,0.3);border:2px solid rgb(66,133,244);pointer-events:none;z-index:2147483645;display:none;box-sizing:border-box;';
      overlay.appendChild(hoverHl);
      
      document.body.appendChild(overlay);
      
      function cleanup() {
        overlay.remove();
        document.removeEventListener('keydown', onKey);
      }
      
      function onKey(e) {
        if (e.key === 'Escape') {
          cleanup();
          resolve({ cancelled: true });
        }
      }
      document.addEventListener('keydown', onKey);
      
      // Track hover
      overlay.addEventListener('mousemove', function(e) {
        var el = document.elementFromPoint(e.clientX, e.clientY);
        if (el && el !== overlay && el !== label && el !== hoverHl) {
          var rect = el.getBoundingClientRect();
          hoverHl.style.display = 'block';
          hoverHl.style.left = rect.left + 'px';
          hoverHl.style.top = rect.top + 'px';
          hoverHl.style.width = rect.width + 'px';
          hoverHl.style.height = rect.height + 'px';
        }
      });
      
      overlay.addEventListener('click', function(e) {
        e.preventDefault();
        e.stopPropagation();
        cleanup();
        
        // Get element under click (need to temporarily hide overlay)
        overlay.style.display = 'none';
        var el = document.elementFromPoint(e.clientX, e.clientY);
        overlay.style.display = '';
        
        if (!el || el === document.documentElement) {
          resolve({ selector: '@L', tag: 'body' });
          return;
        }
        
        var layoutPath = elementToLayoutPath(el);
        if (layoutPath === null) {
          resolve({ error: 'Element not in visible tree' });
          return;
        }
        
        var text = (el.textContent || '').trim();
        resolve({
          selector: layoutPath ? '@L' + layoutPath : '@L',
          tag: el.tagName.toLowerCase(),
          id: el.id || '',
          cls: typeof el.className === 'string' ? el.className : '',
          text: text.substring(0, 40) + (text.length > 40 ? '...' : '')
        });
      });
    });
  }
  
  return null;
})
