export function decodeDEM(pixels) {
  const width = Math.sqrt(pixels.length / 4);
  const gridSize = width + 1;
  const terrain = new Float32Array(gridSize * gridSize);

  const tileSize = width;

  // decode terrain values
  for (let y = 0; y < tileSize; y++) {
    for (let x = 0; x < tileSize; x++) {
      const k = (y * tileSize + x) * 4;
      const r = pixels[k + 0];
      const g = pixels[k + 1];
      const b = pixels[k + 2];
      terrain[y * gridSize + x] =
        (r * 256 * 256 + g * 256.0 + b) / 10.0 - 10000.0;
    }
  }
  // backfill right and bottom borders
  for (let x = 0; x < gridSize - 1; x++) {
    terrain[gridSize * (gridSize - 1) + x] =
      terrain[gridSize * (gridSize - 2) + x];
  }
  for (let y = 0; y < gridSize; y++) {
    terrain[gridSize * y + gridSize - 1] = terrain[gridSize * y + gridSize - 2];
  }

  return terrain;
}

export function maxHeight(pixels) {
  let maxHeight = -1;
  for (let i = 0; i < pixels.length; i += 4) {
    const R = pixels[i];
    const G = pixels[i + 1];
    const B = pixels[i + 2];
    const height = -10000 + (R * 256 * 256 + G * 256 + B) * 0.1;

    if (height > maxHeight) {
      maxHeight = height;
    }
  }
  return maxHeight;
}

export function getPixels(texture) {
  const canvas = document.createElement("canvas");
  const ctx = canvas.getContext("2d");
  const img = texture.image;
  canvas.width = img.width;
  canvas.height = img.height;
  ctx.drawImage(img, 0, 0);
  const imgData = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const pixels = imgData.data;
  return pixels;
}
