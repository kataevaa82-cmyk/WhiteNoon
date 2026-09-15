(function () {
  "use strict";

  var nativeFetch = window.fetch.bind(window);
  var encodedFiles = {
    "index.pck": { source: "index.pck.png", type: "application/octet-stream" },
    "index.wasm": { source: "index.wasm.png", type: "application/wasm" }
  };

  async function unpackPng(file) {
    var response = await nativeFetch(new URL(file.source, document.baseURI), { cache: "force-cache" });
    if (!response.ok) throw new Error("Could not load " + file.source + ": " + response.status);
    var bitmap = await createImageBitmap(await response.blob());
    var canvas = document.createElement("canvas");
    canvas.width = bitmap.width;
    canvas.height = bitmap.height;
    var context = canvas.getContext("2d", { alpha: false, willReadFrequently: true });
    context.drawImage(bitmap, 0, 0);
    bitmap.close();
    var rgba = context.getImageData(0, 0, canvas.width, canvas.height).data;
    var rgb = new Uint8Array(canvas.width * canvas.height * 3);
    for (var source = 0, target = 0; source < rgba.length; source += 4) {
      rgb[target++] = rgba[source];
      rgb[target++] = rgba[source + 1];
      rgb[target++] = rgba[source + 2];
    }
    if (rgb[0] !== 87 || rgb[1] !== 78 || rgb[2] !== 80 || rgb[3] !== 71) {
      throw new Error("Invalid White Noon binary image header: " + file.source);
    }
    var size = new DataView(rgb.buffer).getUint32(4, true);
    var payload = rgb.slice(8, 8 + size);
    return new Response(payload, {
      status: 200,
      headers: { "Content-Type": file.type, "Content-Length": String(size) }
    });
  }

  window.fetch = function (input, options) {
    var requestUrl = typeof input === "string" ? input : input && input.url ? input.url : String(input);
    var filename = new URL(requestUrl, document.baseURI).pathname.split("/").pop();
    return encodedFiles[filename] ? unpackPng(encodedFiles[filename]) : nativeFetch(input, options);
  };
})();
