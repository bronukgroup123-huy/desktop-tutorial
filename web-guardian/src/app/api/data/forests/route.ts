import { NextResponse } from 'next/server';
import * as fs from 'fs';
import * as path from 'path';

export async function GET() {
  try {
    const filePath = path.join(process.cwd(), 'public', 'forests.geojson');
    const fileContents = fs.readFileSync(filePath, 'utf-8');
    const geojson = JSON.parse(fileContents);
    
    return NextResponse.json(geojson, {
      headers: {
        'Content-Type': 'application/geo+json',
        'Cache-Control': 'public, max-age=31536000, immutable',
      },
    });
  } catch (error) {
    console.error('Error loading forests.geojson:', error);
    return NextResponse.json(
      { type: 'FeatureCollection', features: [] },
      { status: 500 }
    );
  }
}