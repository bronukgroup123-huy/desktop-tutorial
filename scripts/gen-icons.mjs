// scripts/gen-icons.mjs
import sharp from 'sharp';
import fs from 'node:fs';
import path from 'node:path';

const OUT_DIR = 'web-guardian/public/icons';
if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR, { recursive: true });

// Малюємо простий SVG із грибом та фоном #F5E6D0
const svgBuffer = Buffer.from(`
<svg width="512" height="512" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg">
  <rect width="512" height="512" fill="#F5E6D0"/>
  <path d="M256 100 C150 100 80 180 80 250 C80 280 100 300 130 300 L382 300 C412 300 432 280 432 250 C432 180 362 100 256 100 Z" fill="#8B4513"/>
  <path d="M200 300 L200 400 C200 430 220 450 256 450 C292 450 312 430 312 400 L312 300 Z" fill="#FDF5E6"/>
  <circle cx="180" cy="200" r="25" fill="#F5E6D0"/>
  <circle cx="300" cy="160" r="30" fill="#F5E6D0"/>
  <circle cx="350" cy="240" r="20" fill="#F5E6D0"/>
</svg>
`);

async function generate() {
  console.log('⏳ Генерація іконок...');
  
  await sharp(svgBuffer)
    .resize(192, 192)
    .png()
    .toFile(path.join(OUT_DIR, 'icon-192.png'));

  await sharp(svgBuffer)
    .resize(512, 512)
    .png()
    .toFile(path.join(OUT_DIR, 'icon-512.png'));

  console.log('✅ Іконки успішно створено у папці:', OUT_DIR);
}

generate().catch(console.error);
