const wasm_path = "./zig-out/bin/zlox.wasm";


const wasm = await WebAssembly.instantiateStreaming(fetch(wasm_path),
  {
    js: {
      log: function(ptr, len) {
        const msg = decodeString(ptr, len);
        logs.push(msg);
        console.log(msg);
      },
      panic: function(ptr, len) {
        const msg = decodeString(ptr, len);
        throw new Error("panic: " + msg);
      },
    },
  })

const text_decoder = new TextDecoder();
const text_encoder = new TextEncoder();

const wasm_exports = wasm.instance.exports;

function decodeString(ptr, len) {
  if (len === 0) return "";
  return text_decoder.decode(new Uint8Array(wasm_exports.memory.buffer, ptr, len));
}

function setInputString(s) {
  const jsArray = text_encoder.encode(s);
  const len = jsArray.length;
  const ptr = wasm_exports.set_input_string(len);
  const wasmArray = new Uint8Array(wasm_exports.memory.buffer, ptr, len);
  wasmArray.set(jsArray);
}

const input = document.querySelector("input");
const list = document.querySelector("ul");
var logs = ["Hello"]

input.oninput = () => {
  logs = []
  setInputString(input.value);
  wasm_exports.main();

  // Clear the list first
  list.innerHTML = '';

  // Generate a list item for each string in the logs array
  logs.forEach(log => {
    const listItem = document.createElement('li');
    listItem.textContent = log; // Set the text content to the log string
    list.appendChild(listItem); // Append the list item to the unordered list
  });
}
