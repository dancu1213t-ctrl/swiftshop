// Set to your actual published customer website, e.g. https://shop.example.com/.
// Native localhost URLs cannot be opened by other customers.
window.SWIFTSHOP_PUBLIC_URL = 'https://swiftshopow.com/';
// Enable only after Firebase/APNs and the delivery push backend are configured.
window.SWIFTSHOP_PUSH_ENABLED = true;
// Enable after applying the notification SQL migration to Supabase.
window.SWIFTSHOP_NOTIFICATION_BACKEND_ENABLED = true;

// Turn on after the ride SQL migration and sender deployment.
window.SWIFTSHOP_RIDE_NOTIFICATION_BACKEND_ENABLED = true;


// Enable after applying 202610040003_app_promotions.sql and redeploying delivery-push.
window.SWIFTSHOP_PROMOTIONS_ENABLED = true;

