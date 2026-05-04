// ============================================
// yAllsale Backend API
// Supabase Edge Functions
// Deploy: supabase functions deploy
// ============================================

// ── FUNCTION 1: Create Stripe Checkout Session ──
// File: supabase/functions/create-checkout/index.ts

export const createCheckoutHandler = `
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import Stripe from "https://esm.sh/stripe@12.0.0?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, { apiVersion: "2023-10-16" });
const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };

  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { type, user_id, sale_id } = await req.json();

    // Get or create Stripe customer
    const { data: user } = await supabase.from("users").select("stripe_customer_id, email, first_name, last_name").eq("id", user_id).single();

    let customerId = user?.stripe_customer_id;
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: user.email,
        name: \`\${user.first_name} \${user.last_name}\`,
        metadata: { supabase_user_id: user_id }
      });
      customerId = customer.id;
      await supabase.from("users").update({ stripe_customer_id: customerId }).eq("id", user_id);
    }

    let session;

    if (type === "membership_verified") {
      // $2.99 one-time verified membership
      session = await stripe.checkout.sessions.create({
        customer: customerId,
        payment_method_types: ["card"],
        line_items: [{
          price_data: {
            currency: "usd",
            product_data: {
              name: "yAllsale Verified Member",
              description: "ID verification + verified badge + post listings + reservations",
              images: ["https://yallsale.com/badge.png"]
            },
            unit_amount: 299,
          },
          quantity: 1,
        }],
        mode: "payment",
        success_url: \`https://yallsale.com/app?payment=success&type=verified\`,
        cancel_url: \`https://yallsale.com/app?payment=cancelled\`,
        metadata: { user_id, type: "membership_verified" }
      });

    } else if (type === "membership_pro") {
      // $9.99/month pro subscription
      session = await stripe.checkout.sessions.create({
        customer: customerId,
        payment_method_types: ["card"],
        line_items: [{
          price: Deno.env.get("STRIPE_PRO_PRICE_ID"),
          quantity: 1
        }],
        mode: "subscription",
        success_url: \`https://yallsale.com/app?payment=success&type=pro\`,
        cancel_url: \`https://yallsale.com/app?payment=cancelled\`,
        metadata: { user_id, type: "membership_pro" }
      });

    } else if (type === "featured_listing") {
      // $3 featured listing
      session = await stripe.checkout.sessions.create({
        customer: customerId,
        payment_method_types: ["card"],
        line_items: [{
          price_data: {
            currency: "usd",
            product_data: {
              name: "Featured Listing — 7 Days",
              description: "Gold pin on map, top of search results for 7 days"
            },
            unit_amount: 300,
          },
          quantity: 1,
        }],
        mode: "payment",
        success_url: \`https://yallsale.com/app?payment=success&type=featured&sale_id=\${sale_id}\`,
        cancel_url: \`https://yallsale.com/app?payment=cancelled\`,
        metadata: { user_id, type: "featured_listing", sale_id }
      });
    }

    // Save payment record
    await supabase.from("payments").insert({
      user_id,
      type,
      amount: type === "membership_verified" ? 2.99 : type === "featured_listing" ? 3.00 : 9.99,
      currency: "USD",
      status: "pending",
      stripe_session_id: session.id,
      metadata: { sale_id }
    });

    return new Response(JSON.stringify({ url: session.url, session_id: session.id }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  }
});
`;

// ── FUNCTION 2: Stripe Identity Verification ──
export const stripeIdentityHandler = `
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import Stripe from "https://esm.sh/stripe@12.0.0?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, { apiVersion: "2023-10-16" });
const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

serve(async (req) => {
  const corsHeaders = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { user_id } = await req.json();

    // Create Stripe Identity verification session (included in $2.99 membership)
    const verificationSession = await stripe.identity.verificationSessions.create({
      type: "document",
      options: {
        document: {
          allowed_types: ["driving_license", "id_card", "passport"],
          require_id_number: false,
          require_live_capture: true,
          require_matching_selfie: true,
        },
      },
      metadata: { user_id },
      return_url: \`https://yallsale.com/app?verification=complete\`,
    });

    // Save session
    await supabase.from("verification_sessions").upsert({
      user_id,
      stripe_session_id: verificationSession.id,
      status: "pending",
      verification_type: "id_selfie"
    });

    await supabase.from("users").update({ stripe_identity_session_id: verificationSession.id }).eq("id", user_id);

    return new Response(JSON.stringify({
      session_id: verificationSession.id,
      client_secret: verificationSession.client_secret,
      url: verificationSession.url
    }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
`;

// ── FUNCTION 3: Stripe Webhook Handler ──
export const webhookHandler = `
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import Stripe from "https://esm.sh/stripe@12.0.0?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, { apiVersion: "2023-10-16" });
const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;

serve(async (req) => {
  const signature = req.headers.get("stripe-signature")!;
  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(body, signature, webhookSecret);
  } catch (err) {
    return new Response(\`Webhook Error: \${err.message}\`, { status: 400 });
  }

  switch (event.type) {

    case "checkout.session.completed": {
      const session = event.data.object as Stripe.Checkout.Session;
      const { user_id, type, sale_id } = session.metadata!;

      // Update payment status
      await supabase.from("payments").update({
        status: "succeeded",
        stripe_payment_intent_id: session.payment_intent as string,
        completed_at: new Date().toISOString()
      }).eq("stripe_session_id", session.id);

      if (type === "membership_verified") {
        // Upgrade user to verified tier
        await supabase.from("users").update({
          membership_tier: "verified",
        }).eq("id", user_id);

        // Start ID verification flow
        // (User is prompted to complete ID verification after payment)

        // Send notification
        await supabase.from("notifications").insert({
          user_id,
          type: "payment_success",
          title: "Payment successful!",
          body: "You're now a Verified Member. Complete your ID verification to get the verified badge.",
          data: { type: "membership_verified" }
        });

      } else if (type === "membership_pro") {
        await supabase.from("users").update({
          membership_tier: "pro",
          membership_expires_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
        }).eq("id", user_id);

        await supabase.from("notifications").insert({
          user_id,
          type: "payment_success",
          title: "Pro Seller activated!",
          body: "You now have unlimited listings, featured priority, and analytics dashboard.",
          data: { type: "membership_pro" }
        });

      } else if (type === "featured_listing" && sale_id) {
        // Mark listing as featured for 7 days
        const endsAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
        await supabase.from("sales").update({
          is_featured: true,
          status: "featured",
          featured_until: endsAt
        }).eq("id", sale_id);

        await supabase.from("featured_listings").insert({
          sale_id, user_id,
          ends_at: endsAt
        });

        await supabase.from("notifications").insert({
          user_id,
          type: "payment_success",
          title: "Your listing is now featured!",
          body: "Your sale now appears as a gold pin on the map and at the top of search results for 7 days.",
          data: { sale_id }
        });
      }
      break;
    }

    case "identity.verification_session.verified": {
      const session = event.data.object as any;
      const user_id = session.metadata?.user_id;

      if (user_id) {
        await supabase.from("users").update({
          id_verified: true,
          selfie_verified: true,
        }).eq("id", user_id);

        await supabase.from("verification_sessions").update({
          status: "verified",
          completed_at: new Date().toISOString(),
          result: { verified: true }
        }).eq("stripe_session_id", session.id);

        await supabase.from("notifications").insert({
          user_id,
          type: "verification_complete",
          title: "Identity verified! ✓",
          body: "Your ID and selfie have been verified. Your listings now show the verified badge.",
          data: { verified: true }
        });

        // Auto-verify pending sales
        await supabase.from("sales").update({ is_verified: true }).eq("host_id", user_id).eq("status", "pending");
      }
      break;
    }

    case "identity.verification_session.requires_input": {
      const session = event.data.object as any;
      const user_id = session.metadata?.user_id;
      if (user_id) {
        await supabase.from("verification_sessions").update({
          status: "failed",
          result: { error: session.last_error }
        }).eq("stripe_session_id", session.id);
      }
      break;
    }

    case "customer.subscription.deleted": {
      const subscription = event.data.object as Stripe.Subscription;
      const { data: users } = await supabase.from("users").select("id").eq("stripe_customer_id", subscription.customer as string);
      if (users && users[0]) {
        await supabase.from("users").update({ membership_tier: "verified", membership_expires_at: null }).eq("id", users[0].id);
      }
      break;
    }
  }

  return new Response(JSON.stringify({ received: true }), { headers: { "Content-Type": "application/json" } });
});
`;

// ── FUNCTION 4: Nearby Sales Search ──
export const nearbySalesHandler = `
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

serve(async (req) => {
  const corsHeaders = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const url = new URL(req.url);
  const lat = parseFloat(url.searchParams.get("lat") || "42.3601");
  const lng = parseFloat(url.searchParams.get("lng") || "-71.0589");
  const radius = parseInt(url.searchParams.get("radius") || "10");
  const categories = url.searchParams.get("categories")?.split(",").filter(Boolean);
  const verified_only = url.searchParams.get("verified_only") === "true";
  const weekend_only = url.searchParams.get("weekend_only") === "true";

  try {
    const { data, error } = await supabase.rpc("get_nearby_sales", {
      user_lat: lat,
      user_lng: lng,
      radius_miles: radius,
      limit_count: 50
    });

    if (error) throw error;

    let results = data || [];

    if (verified_only) results = results.filter((s: any) => s.is_verified);
    if (categories?.length) results = results.filter((s: any) => s.categories?.some((c: string) => categories.includes(c)));
    if (weekend_only) {
      results = results.filter((s: any) => {
        const day = new Date(s.date_start).getDay();
        return day === 0 || day === 6;
      });
    }

    return new Response(JSON.stringify({ sales: results, total: results.length }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
`;

// ── FUNCTION 5: Send Notifications ──
export const notificationsHandler = `
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

serve(async (req) => {
  const corsHeaders = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    // Find users with active item tracking
    const { data: trackers } = await supabase
      .from("item_tracking")
      .select("*, user:users(id, email, phone, sms_notifications, email_notifications, language)")
      .eq("is_active", true);

    if (!trackers) return new Response(JSON.stringify({ checked: 0 }));

    let notified = 0;

    for (const tracker of trackers) {
      // Find matching products
      const { data: products } = await supabase
        .from("products")
        .select("*, sale:sales(title, address, date_start, lat, lng)")
        .ilike("name", \`%\${tracker.keyword}%\`)
        .eq("status", "available")
        .gt("created_at", tracker.last_notified_at || new Date(0).toISOString());

      if (products && products.length > 0) {
        for (const product of products) {
          // Check proximity
          if (tracker.lat && tracker.lng && product.sale?.lat && product.sale?.lng) {
            const dist = Math.sqrt(
              Math.pow(tracker.lat - product.sale.lat, 2) +
              Math.pow(tracker.lng - product.sale.lng, 2)
            ) * 69;
            if (dist > tracker.radius_miles) continue;
          }

          // Create notification
          await supabase.from("notifications").insert({
            user_id: tracker.user_id,
            type: "item_found",
            title: tracker.user?.language === "tr" ? "Aradığın ürün bulundu! 📍" :
                   tracker.user?.language === "es" ? "¡Artículo encontrado cerca! 📍" :
                   "Item found nearby! 📍",
            body: tracker.user?.language === "tr" ?
              \`"\${product.name}" $\${product.price} fiyatıyla \${product.sale?.title}'de listelendi.\` :
              tracker.user?.language === "es" ?
              \`"\${product.name}" por $\${product.price} en \${product.sale?.title}.\` :
              \`"\${product.name}" for $\${product.price} listed at \${product.sale?.title}.\`,
            data: { product_id: product.id, sale_id: product.sale_id, keyword: tracker.keyword }
          });

          notified++;
        }

        // Update last notified
        await supabase.from("item_tracking")
          .update({ last_notified_at: new Date().toISOString(), match_count: tracker.match_count + products.length })
          .eq("id", tracker.id);
      }
    }

    return new Response(JSON.stringify({ checked: trackers.length, notified }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
`;

console.log("Backend functions ready to deploy!");
console.log("Files to create in supabase/functions/:");
console.log("  - create-checkout/index.ts");
console.log("  - stripe-identity/index.ts");
console.log("  - stripe-webhook/index.ts");
console.log("  - nearby-sales/index.ts");
console.log("  - send-notifications/index.ts");
