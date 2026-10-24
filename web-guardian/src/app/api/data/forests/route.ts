import { NextResponse } from 'next/server';
import * as fs from 'fs';
import * as path from 'path';

export async function GET() {
  try {
    const filePath = path.join(process.cwd(), 'public', 'forests.geojson');
    const stat = fs.statSync(filePath);
    
    const stream = fs.createReadStream(filePath);
    
    return new NextResponse(stream as any, {
      headers: {
        'Content-Type': 'application/geo+json',
        'Content-Length': stat.size.toString(),
        'Cache-Control': 'public, max-age=31536000, immutable',
      },
    });
  } catch (error) {
    console.error('Error streaming forests.geojson:', error);
    return NextResponse.json(
      { type: 'FeatureCollection', features: [] },
      { status: 500 }
    );
  }
}