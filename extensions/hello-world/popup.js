// Simple counter for the popup
let count = 0;

document.getElementById('increment').addEventListener('click', () => {
  count++;
  document.getElementById('counter').textContent = count;
});

console.log('Hello World extension popup loaded!');
