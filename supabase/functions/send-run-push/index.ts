import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

type Order = {
  order_id: string | number;
  customer_name?: string | null;
  runner_pay?: number | string | null;
  status?: string | null;
  assigned_runner_id?: string | null;
};

type DatabaseWebhook = {
  type: "INSERT" | "UPDATE" | "DELETE";
  record: Order;
  old_record?: Order | null;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY")!;
const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY")!;
const vapidSubject = Deno.env.get("VAPID_SUBJECT")!;

if (!supabaseUrl || !serviceRoleKey || !vapidPublicKey || !vapidPrivateKey || !vapidSubject) {
  throw new Error("Missing required SwiftShop push secrets");
}

webpush.setVapidDetails(vapidSubject, vapidPublicKey, vapidPrivateKey);
const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

function isNewOrRepricedOffer(event: DatabaseWebhook) {
  const run = event.record;
  if (!run || !["Ready", "Pending"].includes(run.status || "") || run.assigned_runner_id) return false;
  if (event.type === "INSERT") return true;
  return event.type === "UPDATE" && event.old_record?.runner_pay !== run.runner_pay;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });

  let event: DatabaseWebhook;
  try {
    event = await request.json();
  } catch {
    return Response.json({ error: "Invalid webhook payload" }, { status: 400 });
  }

  console.log(JSON.stringify({
    message: "SwiftShop push webhook received",
    type: event.type,
    orderId: event.record?.order_id,
    status: event.record?.status,
    assignedRunnerId: event.record?.assigned_runner_id ?? null,
  }));

  // The orders webhook also receives delivery-status updates. Only a new or
  // repriced unassigned offer deserves a runner notification.
  if (!isNewOrRepricedOffer(event)) {
    console.log(JSON.stringify({ message: "SwiftShop push ignored: not a new unassigned offer" }));
    return Response.json({ ignored: true });
  }

  const {data: savedRun,error:runError}=await admin.from("orders").select("order_id,customer_name,runner_pay,status,assigned_runner_id,zone_id").eq("order_id",String(event.record.order_id)).maybeSingle();
  if(runError)return Response.json({error:"Run lookup failed"},{status:503});
  if(!savedRun||!["Ready","Pending"].includes(savedRun.status)||savedRun.assigned_runner_id)return Response.json({ignored:true});
  const run=savedRun;
  const {data:recipients,error:scopeError}=await admin.rpc("swift_region_runner_recipients",{p_order:String(run.order_id)});
  if(scopeError)return Response.json({error:"Service area lookup failed"},{status:503});
  if(!recipients?.length)return Response.json({notified:0});
  const { data: subscriptions, error } = await admin
    .from("push_subscriptions")
    .select("id, endpoint, subscription, profiles!inner(id, active, role, dispatch_active)")
    .eq("enabled", true)
    .in("profiles.id", recipients)
    .eq("profiles.active", true)
    .eq("profiles.role", "runner")
    .eq("profiles.dispatch_active", true);

  if (error) {
    console.error(JSON.stringify({ message: "SwiftShop push subscription lookup failed", error: error.message }));
    return Response.json({ error: error.message }, { status: 500 });
  }

  console.log(JSON.stringify({ message: "SwiftShop eligible runner subscriptions", count: (subscriptions || []).length }));

  const pay = Number(run.runner_pay || 0).toFixed(2);
  const payload = JSON.stringify({
    title: `SwiftShop: $${pay} run available`,
    body: `${run.customer_name || "New delivery"} · Tap to view and accept.`,
    orderId: String(run.order_id),
  });

  const results = await Promise.all((subscriptions || []).map(async (entry) => {
    try {
      await webpush.sendNotification(entry.subscription, payload, {
        // Keep an urgent offer available while a runner briefly loses signal or wakes their phone.
        TTL: 60 * 60 * 24,
        urgency: "high",
        topic: `run-${String(run.order_id).slice(-24)}`,
      });
      return { id: entry.id, delivered: true };
    } catch (pushError: unknown) {
      const statusCode = (pushError as { statusCode?: number }).statusCode;
      // 404/410 mean that browser/device subscription is gone. Keep the table tidy.
      if (statusCode === 404 || statusCode === 410) {
        await admin.from("push_subscriptions").update({ enabled: false }).eq("id", entry.id);
      }
      return { id: entry.id, delivered: false, statusCode };
    }
  }));

  const notified = results.filter((r) => r.delivered).length;
  console.log(JSON.stringify({ message: "SwiftShop push result", orderId: run.order_id, notified, results }));
  return Response.json({ notified, results });
});
