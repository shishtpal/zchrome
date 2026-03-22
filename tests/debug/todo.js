(() => {
  const form = document.getElementById("todo-form");
  const input = document.getElementById("todo-input");
  const list = document.getElementById("todo-list");
  const status = document.getElementById("status");

  const todos = JSON.parse(localStorage.getItem("todos") || "[]");

  function save() {
    localStorage.setItem("todos", JSON.stringify(todos));
  }

  function updateStatus() {
    if (todos.length === 0) {
      status.textContent = "";
      status.classList.add("hidden");
      return;
    }
    const done = todos.filter((t) => t.completed).length;
    status.textContent = `${done} of ${todos.length} completed`;
    status.classList.remove("hidden");
  }

  function render() {
    list.innerHTML = "";
    todos.forEach((todo, index) => {
      const li = document.createElement("li");
      li.className =
        "flex items-center gap-3 bg-gray-50 rounded-lg px-4 py-2 group";

      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.checked = todo.completed;
      checkbox.className =
        "w-5 h-5 rounded border-gray-300 text-blue-600 focus:ring-blue-500 cursor-pointer";
      checkbox.addEventListener("change", () => {
        todos[index].completed = checkbox.checked;
        save();
        render();
      });

      const span = document.createElement("span");
      span.textContent = todo.text;
      span.className =
        `flex-1 text-gray-800${todo.completed ? " line-through text-gray-400" : ""}`;

      const btn = document.createElement("button");
      btn.textContent = "\u00d7";
      btn.className =
        "text-red-500 text-xl leading-none opacity-0 group-hover:opacity-100 transition-opacity hover:text-red-700";
      btn.addEventListener("click", () => {
        todos.splice(index, 1);
        save();
        render();
      });

      li.appendChild(checkbox);
      li.appendChild(span);
      li.appendChild(btn);
      list.appendChild(li);
    });

    updateStatus();
  }

  form.addEventListener("submit", (e) => {
    e.preventDefault();
    const text = input.value.trim();
    if (!text) return;
    todos.push({ text, completed: false });
    save();
    input.value = "";
    render();
  });

  render();
})();
