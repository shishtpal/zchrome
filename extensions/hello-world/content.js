// Content script - runs on every page
console.log('[Hello World Extension] Content script loaded on:', window.location.href);

// Add a small indicator to show the extension is active
const indicator = document.createElement('div');
indicator.id = 'zchrome-hello-world-indicator';
indicator.style.cssText = `
  position: fixed;
  bottom: 10px;
  right: 10px;
  background: #4285f4;
  color: white;
  padding: 5px 10px;
  border-radius: 4px;
  font-family: Arial, sans-serif;
  font-size: 12px;
  z-index: 999999;
  opacity: 0.8;
`;
indicator.textContent = 'Hello World Extension Active';
document.body.appendChild(indicator);

// Fade out after 3 seconds
setTimeout(() => {
  indicator.style.transition = 'opacity 1s';
  indicator.style.opacity = '0';
  setTimeout(() => indicator.remove(), 1000);
}, 3000);
