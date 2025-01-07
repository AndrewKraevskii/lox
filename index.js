import wasm_path from "./zig-out/bin/zlox.wasm";
const wasm_data = await Bun.file(wasm_path).arrayBuffer();
const wasm = await WebAssembly.instantiate(wasm_data,
  {
    js: {
      log: function(ptr, len) {
        const msg = decodeString(ptr, len);
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

setInputString("1 + 1");
wasm_exports.main();
