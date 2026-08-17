/*************************************************
 * SWIFT SHOP OW – GOOGLE APPS SCRIPT BACKEND
 *************************************************/

function sendPromoEmails(promoRow) {
  const ss = SpreadsheetApp.getActive();

  const promoSheet = ss.getSheetByName("Promos");
  const usersSheet = ss.getSheetByName("SwiftShop Users");

  // Promo data
  const promo = promoSheet.getRange(promoRow, 1, 1, 6).getValues()[0];

  const title = promo[1];
  const price = promo[2];
  const image = promo[3];
  const status = promo[5];

  // Prevent resend
  if (status === "SENT") return;

  // Business WhatsApp number (YOU)
  const businessPhone = "5016080205";

  // Users data
  const users = usersSheet.getDataRange().getValues();
  users.shift(); // remove headers

  users.forEach(user => {
    const name = user[1];
    const email = user[3];

    if (!email || !name) return;

    // WhatsApp message goes to YOU only
    const whatsappMsg =
      `Hey I'm ${name}, I am interested in the Promo: ${title}`;

    const whatsappLink =
      `https://wa.me/${businessPhone}?text=${encodeURIComponent(whatsappMsg)}`;

    // HTML email body (email-safe font, no emojis)
    const htmlBody = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
</head>
<body style="
  font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',
              Roboto,Helvetica,Arial,sans-serif;
  margin:0;
  padding:0;
  color:#111;
">

<div style="
  width:100%;
  padding:44px 20px;
  text-align:center;
  background-color:#ff6a00;
">

  <h2 style="
    margin:0;
    font-weight:900;
    font-size:36px;
    text-transform:uppercase;
    color:#ffffff;
    letter-spacing:0.6px;
    text-shadow:
      0 0 6px rgba(255,255,255,0.55),
      0 3px 6px rgba(0,0,0,0.35);
  ">
    Hey ${name}
  </h2>

  <p style="
    margin-top:14px;
    font-size:20px;
    font-weight:700;
    color:#ffffff;
    text-shadow:
      0 0 4px rgba(255,255,255,0.4),
      0 2px 4px rgba(0,0,0,0.25);
  ">
    Check this out now on <b>SwiftShop OW</b>
  </p>

</div>




  <h3 style="font-weight:600;">${title}</h3>

  <img src="${image}"
       style="width:100%;max-width:300px;border-radius:10px;display:block;margin-bottom:15px;" />

  <p style="font-size:18px;">
  <b>Price: $${price} BZD</b>
</p>


  <a href="${whatsappLink}"
     style="
      display:inline-block;
      padding:12px 20px;
      background:#25D366;
      color:#ffffff;
      text-decoration:none;
      border-radius:8px;
      font-weight:700;
font-size:22px;

     ">
    Order Now 
  </a>

  <p style="margin-top:25px;color:#777;font-size:14px;">
    SwiftShop OW
  </p>

</body>
</html>
`;

    // Send email
    GmailApp.sendEmail(
      email,
      `SwiftShop Promo: ${title}`,
      "Please view this email in HTML format.",
      { htmlBody }
    );

    // Light rate limit protection
    Utilities.sleep(300);
  });

  // Mark promo as SENT
  promoSheet.getRange(promoRow, 6).setValue("SENT");
}


function onEdit(e) {
  const sheet = e.range.getSheet();
  const sheetName = sheet.getName();
  const row = e.range.getRow();
  const col = e.range.getColumn();

  /******** PROMOS TRIGGER ********/
  if (sheetName === "Promos") {
    // Column E = Active
    if (col === 5 && e.value && e.value.toLowerCase() === "yes") {
      sendPromoEmails(row);
    }
  }

  /******** ORDERS TRACKING TRIGGER ********/
  if (sheetName === "Orders") {
    // Column E = Status
    if (col !== 5 || !e.value) return;

    const status = e.value.toString().trim();
    const activeCell = sheet.getRange(row, 6); // Column F = Active
    const activeVal = activeCell.getValue();

    // prevent resending same status
    if (activeVal === status + "_SENT") return;

    const orderId = sheet.getRange(row, 1).getValue();
    const customerName = sheet.getRange(row, 2).getValue();
    const email = sheet.getRange(row, 4).getValue();

    if (!email) return;

    let subject = "";
    let body = "";

   if (status === "On the Way") {
  subject = "Swift Shop OW – Your order is on the way 🚗";
  body =
    `Hi ${customerName},\n\n` +
    `Order ID: ${orderId}\n\n` +
    buildHorizontalTimeline("On the Way") +
    `Your runner is on the way to you.\n\n` +
    `Thank you for ordering with Swift Shop OW!\n`;
}

if (status === "Delivered") {
  subject = "Swift Shop OW – Order delivered ✅";
  body =
    `Hi ${customerName},\n\n` +
    `Order ID: ${orderId}\n\n` +
    buildHorizontalTimeline("Delivered") +
    `Your order has been delivered.\n\n` +
    `Thanks for shopping with Swift Shop OW!\n`;
}

    if (!subject) return;

    MailApp.sendEmail({
      to: email,
      subject: subject,
      body: body
    });

    // mark as sent
    activeCell.setValue(status + "_SENT");
  }
}
function buildHorizontalTimeline(status) {
  let received = "⬜🏢 Order Received";
  let onWay = "⬜🏃‍♂️ On the Way";
  let delivered = "⬜🏠 Delivered";

  if (status === "Order Received") {
    received = "🟢🏢 Order Received";
  }

  if (status === "On the Way") {
    received = "✅🏢 Order Received";
    onWay = "🟢🏃‍♂️ On the Way";
  }

  if (status === "Delivered") {
    received = "✅🏢 Order Received";
    onWay = "✅🏃‍♂️ On the Way";
    delivered = "🟢🏠 Delivered";
  }

  return (
    received +
    "  ➜  " +
    onWay +
    "  ➜  " +
    delivered +
    "\n\n"
  );
}







function updateUserEmail(phone, email) {
  if (!email) return;

  const sheet = SpreadsheetApp
    .getActiveSpreadsheet()
    .getSheetByName("SwiftShop Users");

  const data = sheet.getDataRange().getValues();

  for (let i = 1; i < data.length; i++) {
    if (String(data[i][2]) === String(phone)) {
      sheet.getRange(i + 1, 4).setValue(email);
      break;
    }
  }
}

function doGet(e) {
  const action = e?.parameter?.action;
  if (action === "getLeaderBoard") { const leaderboard = getLeaderBoard(); return ContentService .createTextOutput(JSON.stringify(leaderboard)) .setMimeType(ContentService.MimeType.JSON); }

  // 🏪 PATHWAY 1: Get Store Items (New)
  if (action === "getStoreItems") {
    const storeName = e.parameter.sheet; 
    const items = getStoreItemsFromTab(storeName); 
    
    return ContentService
      .createTextOutput(JSON.stringify(items))
      .setMimeType(ContentService.MimeType.JSON)
      .setHeader("Access-Control-Allow-Origin", "*");
  }

  // 🔄 PATHWAY 2: Get User Balance (Existing)
  if (action === "getBalance") {
    const phone = e.parameter.phone || "";
    const balance = getUserBalance(phone);

    return ContentService
      .createTextOutput(JSON.stringify({ balance }))
      .setMimeType(ContentService.MimeType.JSON);
  }

  // 🌐 PATHWAY 3: Load Web App (Existing)
  return HtmlService
    .createHtmlOutputFromFile("index")
    .setTitle("Swift Shop OW")
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}

// NECESSARY HELPER: Add this below your doGet
function getStoreItemsFromTab(tabName) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName(tabName);
  if (!sheet) return [];

  const data = sheet.getDataRange().getValues();
  data.shift(); // Remove header row

  return data.map(row => ({
    name: row[0],   // Column A
    price: row[1],  // Column B
    image: row[2],  // Column C
    phone: row[3]   // Column D (Seller Number)
  }));
}

/* ================= USER AUTH ================= */

/* SAVE NEW USER */
/* SAVE NEW USER (Initializes Column E with 0) */
/* SAVE NEW USER */
function saveUser(name, phone, email) {
  const sheet = SpreadsheetApp
    .getActiveSpreadsheet()
    .getSheetByName("SwiftShop Users");

  sheet.appendRow([
    new Date(), // A: Timestamp
    name,       // B: Name
    phone,      // C: Phone
    email,      // D: Email
    0,          // E: Points
    0           // F: Balance ✅ REQUIRED
  ]);

  return { success: true };
}

/* CHECK IF USER ALREADY EXISTS & FETCH POINTS */
function checkUser(phone) {
  const sheet = SpreadsheetApp
    .getActiveSpreadsheet()
    .getSheetByName("SwiftShop Users");

  const data = sheet.getDataRange().getValues();

  for (let i = 1; i < data.length; i++) {
    if (String(data[i][2]) === String(phone)) {
      return {
        exists: true,
        name: data[i][1],
        points: data[i][4] || 0 // E: Points (Index 4) ✅ ADDED THIS
      };
    }
  }

  return { exists: false };
}

/**
 * Products Sheet
 * A: ID
 * B: Name
 * C: Category
 * D: Price
 * E: Image URL
 * F: Yes / No
 */
function saveSuggestion(itemName) {
  const sheet = SpreadsheetApp.getActiveSpreadsheet()
    .getSheetByName("Suggestions");

  sheet.appendRow([
    itemName,
    new Date()
  ]);
}
function getProducts() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName("Products");
  if (!sheet) return [];

  const rows = sheet.getDataRange().getValues();
  rows.shift(); // Remove headers

  return rows
    .filter(r => String(r[5]).toLowerCase().trim() === "yes") // Column F Active
    .map(r => ({
      id: r[0],              // Column A
      name: r[1],            // Column B
      category: r[2],        // Column C
      price: Number(r[3]),   // Column D
      image: r[4],           // Column E
      was: r[6] ? Number(r[6]) : null, // Column G (Was price)
      subcategory: r[7] || "Items"     // ⭐ Column H (SubCategory)
    }));
}

/**
 * Send receipt email and track reward points
 */
function sendReceipt(data) {
  if (!data.email) return true;

  // Ensure platform fee is defined for grocery orders
  if (!data.tacoOrder && !data.pickupPlace) {
    data.platformFee = data.platformFee !== undefined ? data.platformFee : 1.50; 
  }

  const orderId = "SS-" + Math.floor(10000 + Math.random() * 90000);
  const orderStatus = "Order Received";

  let body = "";
  body += "Swift Shop OW — Receipt\n";
  body += "================================\n\n";
  body += `Order ID: ${orderId}\n\n`;
  body += buildHorizontalTimeline(orderStatus);
  body += "You will receive updates as your order moves forward.\n\n";

  // 🌮 TACO ORDER (if any)
  if (data.tacoPlace && data.tacoOrder) {
    body += "🌮 TACO ORDER\n";
    body += "--------------------------------\n";
    body += `Place: ${data.tacoPlace}\n`;
    body += `Order: ${data.tacoOrder}\n\n`;
  }

  // 📦 ITEM PICKUP (NEW)
  if (data.pickupPlace && data.pickupOrder) {
    body += "📦 ITEM PICKUP\n";
    body += "--------------------------------\n";
    body += `Store: ${data.pickupPlace}\n`;
    body += `Items: ${data.pickupOrder}\n`;
    if (data.pickupGPS) body += `📍 GPS Pin: ${data.pickupGPS}\n`;
    body += "\n";
  }

  // GROCERY ITEMS
  if (data.items && data.items.length > 0) {
    body += "🛒 GROCERY ITEMS\n";
    body += "--------------------------------\n";
    data.items.forEach((item, i) => {
      const qty = data.quantities[i];
      const price = data.prices ? data.prices[i] : null;
      const subtotal = price ? qty * price : null;
      body += `${item}\n   Quantity: ${qty}`;
      if (price !== null) body += ` @ $${price.toFixed(2)} BZD`;
      body += "\n";
      if (subtotal !== null) body += `   Subtotal: $${subtotal.toFixed(2)} BZD\n`;
      body += "\n";
    });
  }

  // ===== TOTALS SECTION =====
  body += "--------------------------------\n";
  body += `ITEMS TOTAL: $${data.itemsTotal.toFixed(2)} BZD\n`;
  body += `DELIVERY FEE: $${data.deliveryFee.toFixed(2)} BZD\n`;

  if (!data.tacoOrder && !data.pickupPlace && data.platformFee !== undefined) {
    body += `PLATFORM FEE: $${data.platformFee.toFixed(2)} BZD\n`;
  }

  body += "--------------------------------\n";
  body += `GRAND TOTAL: $${data.grandTotal.toFixed(2)} BZD\n\n`;

  // --- LOG TO ORDERS SHEET ---
  const ordersSheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName("Orders");
  if (ordersSheet) {
    ordersSheet.appendRow([
      orderId,
      data.name || "",
      data.phone || "",
      data.email || "",
      orderStatus,
      "SENT",
      data.pickupPlace || data.tacoPlace || "Grocery", // Column G: Type
      data.pickupGPS || ""                            // Column H: GPS Link
    ]);
  }

  // --- REWARD POINTS LOGIC (NEW) ---
  if (data.addPoint && data.phone) {
    const usersSheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName("SwiftShop Users");
    const userData = usersSheet.getDataRange().getValues();
    for (let i = 1; i < userData.length; i++) {
      // Column C (index 2) is Phone
      if (String(userData[i][2]) === String(data.phone)) {
        // Points are in Column E (index 4) - Adjust if your column is different!
        let currentPoints = parseInt(userData[i][4]) || 0; 
        usersSheet.getRange(i + 1, 5).setValue(currentPoints + 1);
        break;
      }
    }
  }

  MailApp.sendEmail({
    to: data.email,
    subject: "Swift Shop OW – Receipt",
    body: body
  });

  return true;
}





function getUserBalance(phone) {
  const ss = SpreadsheetApp.getActive();
  const sheet = ss.getSheetByName("SwiftShop Users");

  const data = sheet.getDataRange().getValues();

  for (let i = 1; i < data.length; i++) {
   if (String(data[i][2]) === String(phone)) { // Column C = Phone

      const balance = data[i][5] || 0;           // 👈 Column F = Balance
      return balance;
    }
  }

  return 0;
}

/**
 * Fetches data from the "Promos" tab
 * Expected Column Order: 
 * A: Timestamp | B: Name | C: Price | D: Image URL | E: Category | F: Was Price
 */
function getPromos() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName("Promos");
  if (!sheet) return [];

  const rows = sheet.getDataRange().getValues();
  rows.shift(); // Remove headers

  // Filter only rows where an Image URL exists (Column D / Index 3)
  return rows
    .filter(r => r[3] !== "") 
    .map(r => ({
      name: r[1],
      price: Number(r[2]),
      image: r[3],
      category: r[4],
      was: r[5] ? Number(r[5]) : null 
    }));
}

function getStoreData(tabName) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName(tabName);
  
  if (!sheet) return [];

  const data = sheet.getDataRange().getValues();
  data.shift(); // Remove headers

  return data.map(row => ({
    name: row[0],
    price: row[1],
    image: row[2],
    phone: row[3],
    comment: row[4] || "" // 🏷️ NEW: Column E (Comment)
  }));
}

/*************************************************
 * GET LEADERBOARD DATA
 *************************************************/

function getLeaderBoard() {

  const sheet = SpreadsheetApp
    .getActiveSpreadsheet()
    .getSheetByName("LeaderBoard");

  if (!sheet) return [];

  const data = sheet.getDataRange().getValues();

  // REMOVE HEADER ROW
  data.shift();

  // SORT BY HIGHEST POINTS
  data.sort((a, b) => Number(b[2]) - Number(a[2]));

  // RETURN CLEAN DATA
  return data.map((row, index) => ({

    rank: index + 1,

    number: row[0], // COLUMN A
    name: row[1],   // COLUMN B
    points: row[2]  // COLUMN C

  }));
}
