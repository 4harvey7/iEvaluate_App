// This script processes the payload from the Flutter app
const items = $input.all();

return items.map(item => {
  // n8n Webhook data is usually inside item.json.body
  const payload = item.json.body || item.json;
  
  // 1. Get the info sent from Flutter
  const staffId = payload.user_id;
  const googleLink = payload.link;
  
  // 2. Extra Logic: Extract the Spreadsheet ID
  let sheetId = '';
  
  // Add a check to ensure googleLink exists before matching
  if (googleLink && typeof googleLink === 'string') {
    const match = googleLink.match(/\/d\/(.*?)(\/|$)/);
    if (match && match[1]) {
      sheetId = match[1];
    }
  }

  return {
    json: {
      staff_id: staffId,
      google_link: googleLink,
      extracted_sheet_id: sheetId,
      import_type: payload.type,
      sync_time: payload.timestamp
    }
  };
});