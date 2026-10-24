const path = require('path');
require('dotenv').config({ path: path.resolve(process.cwd(), '.env') });

const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

async function main() {
  console.log('Connecting to Supabase...');

  const { data: geojson, error: rpcError } = await supabase
    .rpc('export_all_forests_geojson');

  if (rpcError) {
    console.error('RPC error:', rpcError);
    process.exit(1);
  }

  if (!geojson) {
    console.error('RPC returned no data');
    process.exit(1);
  }

  console.log('RPC returned GeoJSON data');

  const body = Buffer.from(JSON.stringify(geojson), 'utf8');

  const { error: uploadError } = await supabase.storage
    .from('forest-data')
    .upload('forests.geojson', body, {
      contentType: 'application/geo+json',
      upsert: true,
    });

  if (uploadError) {
    console.error('Upload error:', uploadError);
    process.exit(1);
  }

  console.log('Uploaded forests.geojson to bucket forest-data');

  const { data: urlData } = supabase.storage
    .from('forest-data')
    .getPublicUrl('forests.geojson');

  console.log(urlData.publicUrl);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
