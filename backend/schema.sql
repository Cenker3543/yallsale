-- ============================================
-- yAllsale - Complete Database Schema
-- Run this in Supabase SQL Editor
-- ============================================

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- ============================================
-- USERS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.users (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  auth_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  phone TEXT,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  avatar_url TEXT,
  city TEXT,
  state TEXT DEFAULT 'MA',
  country TEXT DEFAULT 'US',
  bio TEXT,
  -- Verification status
  phone_verified BOOLEAN DEFAULT FALSE,
  email_verified BOOLEAN DEFAULT FALSE,
  id_verified BOOLEAN DEFAULT FALSE,
  selfie_verified BOOLEAN DEFAULT FALSE,
  is_fully_verified BOOLEAN GENERATED ALWAYS AS (phone_verified AND email_verified AND id_verified AND selfie_verified) STORED,
  -- Membership
  membership_tier TEXT DEFAULT 'free' CHECK (membership_tier IN ('free', 'verified', 'pro')),
  membership_expires_at TIMESTAMPTZ,
  stripe_customer_id TEXT UNIQUE,
  stripe_identity_session_id TEXT,
  -- Stats
  total_sales_hosted INTEGER DEFAULT 0,
  total_items_sold INTEGER DEFAULT 0,
  total_earned DECIMAL(10,2) DEFAULT 0,
  avg_rating DECIMAL(3,2),
  review_count INTEGER DEFAULT 0,
  -- Preferences
  language TEXT DEFAULT 'en' CHECK (language IN ('en', 'tr', 'es')),
  notifications_enabled BOOLEAN DEFAULT TRUE,
  email_notifications BOOLEAN DEFAULT TRUE,
  sms_notifications BOOLEAN DEFAULT TRUE,
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- MEMBERSHIP PLANS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.membership_plans (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  name TEXT NOT NULL,
  tier TEXT NOT NULL CHECK (tier IN ('free', 'verified', 'pro')),
  price DECIMAL(10,2) NOT NULL,
  currency TEXT DEFAULT 'USD',
  billing_period TEXT DEFAULT 'one_time' CHECK (billing_period IN ('one_time', 'monthly', 'yearly')),
  stripe_price_id TEXT,
  features JSONB,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert default plans
INSERT INTO public.membership_plans (name, tier, price, billing_period, stripe_price_id, features) VALUES
  ('Free', 'free', 0, 'one_time', NULL, '{"browse_sales": true, "save_favorites": true, "contact_sellers": false, "post_listings": false, "verified_badge": false, "reservations": false}'),
  ('Verified Member', 'verified', 2.99, 'one_time', 'price_verified_member', '{"browse_sales": true, "save_favorites": true, "contact_sellers": true, "post_listings": true, "verified_badge": true, "reservations": true, "id_verification": true, "listings_limit": 3}'),
  ('Pro Seller', 'pro', 9.99, 'monthly', 'price_pro_seller_monthly', '{"browse_sales": true, "save_favorites": true, "contact_sellers": true, "post_listings": true, "verified_badge": true, "reservations": true, "id_verification": true, "listings_limit": -1, "featured_listings": true, "analytics": true, "priority_support": true}');

-- ============================================
-- SALES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.sales (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  host_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  address TEXT NOT NULL,
  city TEXT NOT NULL,
  state TEXT NOT NULL,
  zip_code TEXT,
  country TEXT DEFAULT 'US',
  location GEOGRAPHY(POINT, 4326),
  lat DECIMAL(10, 7),
  lng DECIMAL(10, 7),
  -- Dates & times
  date_start DATE NOT NULL,
  date_end DATE,
  time_open TIME DEFAULT '08:00',
  time_close TIME DEFAULT '15:00',
  -- Categories & metadata
  categories TEXT[] DEFAULT '{}',
  item_count INTEGER DEFAULT 0,
  -- Status
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'featured', 'ended', 'cancelled')),
  is_verified BOOLEAN DEFAULT FALSE,
  is_featured BOOLEAN DEFAULT FALSE,
  featured_until TIMESTAMPTZ,
  has_online_listing BOOLEAN DEFAULT FALSE,
  accepts_reservations BOOLEAN DEFAULT FALSE,
  -- Payment
  featured_payment_id TEXT,
  -- Stats
  view_count INTEGER DEFAULT 0,
  save_count INTEGER DEFAULT 0,
  reservation_count INTEGER DEFAULT 0,
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  published_at TIMESTAMPTZ
);

-- Index for geo queries
CREATE INDEX IF NOT EXISTS sales_location_idx ON public.sales USING GIST(location);
CREATE INDEX IF NOT EXISTS sales_status_idx ON public.sales(status);
CREATE INDEX IF NOT EXISTS sales_host_idx ON public.sales(host_id);

-- ============================================
-- PRODUCTS TABLE (items in a sale)
-- ============================================
CREATE TABLE IF NOT EXISTS public.products (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  sale_id UUID REFERENCES public.sales(id) ON DELETE CASCADE NOT NULL,
  seller_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  price DECIMAL(10,2) NOT NULL,
  original_price DECIMAL(10,2),
  condition TEXT DEFAULT 'good' CHECK (condition IN ('new', 'like_new', 'good', 'fair', 'poor')),
  category TEXT,
  photos TEXT[] DEFAULT '{}',
  emoji TEXT DEFAULT '📦',
  status TEXT DEFAULT 'available' CHECK (status IN ('available', 'reserved', 'sold', 'removed')),
  reserved_by UUID REFERENCES public.users(id),
  reserved_at TIMESTAMPTZ,
  reservation_expires_at TIMESTAMPTZ,
  sold_at TIMESTAMPTZ,
  view_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS products_sale_idx ON public.products(sale_id);
CREATE INDEX IF NOT EXISTS products_status_idx ON public.products(status);

-- ============================================
-- RESERVATIONS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.reservations (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  product_id UUID REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
  sale_id UUID REFERENCES public.sales(id) ON DELETE CASCADE NOT NULL,
  buyer_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  seller_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'confirmed', 'cancelled', 'expired', 'completed')),
  note TEXT,
  expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '24 hours'),
  confirmed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS reservations_buyer_idx ON public.reservations(buyer_id);
CREATE INDEX IF NOT EXISTS reservations_seller_idx ON public.reservations(seller_id);
CREATE INDEX IF NOT EXISTS reservations_product_idx ON public.reservations(product_id);

-- ============================================
-- REVIEWS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.reviews (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  sale_id UUID REFERENCES public.sales(id) ON DELETE CASCADE NOT NULL,
  reviewer_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  seller_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  title TEXT,
  body TEXT,
  is_verified_purchase BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS reviews_seller_idx ON public.reviews(seller_id);
CREATE UNIQUE INDEX IF NOT EXISTS reviews_unique ON public.reviews(sale_id, reviewer_id);

-- ============================================
-- MESSAGES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.messages (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  conversation_id UUID NOT NULL,
  sender_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  receiver_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  sale_id UUID REFERENCES public.sales(id) ON DELETE SET NULL,
  product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
  content TEXT NOT NULL,
  is_read BOOLEAN DEFAULT FALSE,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS messages_conversation_idx ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS messages_receiver_idx ON public.messages(receiver_id, is_read);

-- ============================================
-- SAVED SALES (favorites)
-- ============================================
CREATE TABLE IF NOT EXISTS public.saved_sales (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  sale_id UUID REFERENCES public.sales(id) ON DELETE CASCADE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, sale_id)
);

-- ============================================
-- ITEM TRACKING (alerts)
-- ============================================
CREATE TABLE IF NOT EXISTS public.item_tracking (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  keyword TEXT NOT NULL,
  categories TEXT[] DEFAULT '{}',
  max_price DECIMAL(10,2),
  radius_miles INTEGER DEFAULT 10,
  lat DECIMAL(10,7),
  lng DECIMAL(10,7),
  is_active BOOLEAN DEFAULT TRUE,
  last_notified_at TIMESTAMPTZ,
  match_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS tracking_user_idx ON public.item_tracking(user_id, is_active);

-- ============================================
-- NOTIFICATIONS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('item_found', 'new_sale_nearby', 'reservation_update', 'review_received', 'message_received', 'verification_complete', 'payment_success', 'sale_reminder')),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB DEFAULT '{}',
  is_read BOOLEAN DEFAULT FALSE,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS notifications_user_idx ON public.notifications(user_id, is_read);

-- ============================================
-- PAYMENTS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.payments (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('membership_verified', 'membership_pro', 'featured_listing', 'id_verification')),
  amount DECIMAL(10,2) NOT NULL,
  currency TEXT DEFAULT 'USD',
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'succeeded', 'failed', 'refunded')),
  stripe_payment_intent_id TEXT UNIQUE,
  stripe_session_id TEXT UNIQUE,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS payments_user_idx ON public.payments(user_id);

-- ============================================
-- FEATURED LISTINGS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.featured_listings (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  sale_id UUID REFERENCES public.sales(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  payment_id UUID REFERENCES public.payments(id),
  starts_at TIMESTAMPTZ DEFAULT NOW(),
  ends_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '7 days'),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- VERIFICATION SESSIONS
-- ============================================
CREATE TABLE IF NOT EXISTS public.verification_sessions (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  stripe_session_id TEXT UNIQUE,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'verified', 'failed', 'cancelled')),
  verification_type TEXT DEFAULT 'id_selfie' CHECK (verification_type IN ('id_selfie', 'phone', 'email')),
  result JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

-- ============================================
-- VIEWS & FUNCTIONS
-- ============================================

-- Function: Get nearby sales
CREATE OR REPLACE FUNCTION get_nearby_sales(
  user_lat DECIMAL,
  user_lng DECIMAL,
  radius_miles INTEGER DEFAULT 10,
  limit_count INTEGER DEFAULT 50
)
RETURNS TABLE (
  id UUID,
  title TEXT,
  address TEXT,
  lat DECIMAL,
  lng DECIMAL,
  distance_miles DECIMAL,
  date_start DATE,
  date_end DATE,
  time_open TIME,
  time_close TIME,
  categories TEXT[],
  item_count INTEGER,
  status TEXT,
  is_verified BOOLEAN,
  is_featured BOOLEAN,
  has_online_listing BOOLEAN,
  host_name TEXT,
  host_initials TEXT,
  host_verified BOOLEAN,
  avg_rating DECIMAL,
  review_count INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    s.id, s.title, s.address, s.lat, s.lng,
    ROUND(ST_Distance(
      s.location::geography,
      ST_SetSRID(ST_MakePoint(user_lng, user_lat), 4326)::geography
    ) / 1609.34, 2) AS distance_miles,
    s.date_start, s.date_end, s.time_open, s.time_close,
    s.categories, s.item_count, s.status, s.is_verified, s.is_featured, s.has_online_listing,
    u.first_name || ' ' || u.last_name AS host_name,
    UPPER(LEFT(u.first_name, 1) || LEFT(u.last_name, 1)) AS host_initials,
    u.is_fully_verified AS host_verified,
    u.avg_rating, u.review_count
  FROM public.sales s
  JOIN public.users u ON s.host_id = u.id
  WHERE
    s.status IN ('active', 'featured')
    AND s.date_end >= CURRENT_DATE
    AND ST_DWithin(
      s.location::geography,
      ST_SetSRID(ST_MakePoint(user_lng, user_lat), 4326)::geography,
      radius_miles * 1609.34
    )
  ORDER BY s.is_featured DESC, distance_miles ASC
  LIMIT limit_count;
END;
$$ LANGUAGE plpgsql;

-- Function: Update seller rating after review
CREATE OR REPLACE FUNCTION update_seller_rating()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.users
  SET
    avg_rating = (
      SELECT ROUND(AVG(rating)::DECIMAL, 2)
      FROM public.reviews
      WHERE seller_id = NEW.seller_id
    ),
    review_count = (
      SELECT COUNT(*)
      FROM public.reviews
      WHERE seller_id = NEW.seller_id
    )
  WHERE id = NEW.seller_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_review_created
  AFTER INSERT OR UPDATE ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION update_seller_rating();

-- Function: Auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER update_sales_updated_at BEFORE UPDATE ON public.sales FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.item_tracking ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

-- Users policies
CREATE POLICY "Users can view all profiles" ON public.users FOR SELECT USING (true);
CREATE POLICY "Users can update own profile" ON public.users FOR UPDATE USING (auth.uid() = auth_id);
CREATE POLICY "Users can insert own profile" ON public.users FOR INSERT WITH CHECK (auth.uid() = auth_id);

-- Sales policies
CREATE POLICY "Anyone can view active sales" ON public.sales FOR SELECT USING (status IN ('active', 'featured'));
CREATE POLICY "Hosts can manage own sales" ON public.sales FOR ALL USING (host_id IN (SELECT id FROM public.users WHERE auth_id = auth.uid()));

-- Products policies
CREATE POLICY "Anyone can view products" ON public.products FOR SELECT USING (true);
CREATE POLICY "Sellers can manage own products" ON public.products FOR ALL USING (seller_id IN (SELECT id FROM public.users WHERE auth_id = auth.uid()));

-- Reservations policies
CREATE POLICY "Users can view own reservations" ON public.reservations FOR SELECT USING (
  buyer_id IN (SELECT id FROM public.users WHERE auth_id = auth.uid()) OR
  seller_id IN (SELECT id FROM public.users WHERE auth_id = auth.uid())
);
CREATE POLICY "Verified users can create reservations" ON public.reservations FOR INSERT WITH CHECK (
  buyer_id IN (SELECT id FROM public.users WHERE auth_id = auth.uid() AND membership_tier != 'free')
);

-- Messages policies
CREATE POLICY "Users can view own messages" ON public.messages FOR SELECT USING (
  sender_id IN (SELECT id FROM public.users WHERE auth_id = auth.uid()) OR
  receiver_id IN (SELECT id FROM public.users WHERE auth_id = auth.uid())
);
CREATE POLICY "Users can send messages" ON public.messages FOR INSERT WITH CHECK (
  sender_id IN (SELECT id FROM public.users WHERE auth_id = auth.uid())
);

-- Saved sales
CREATE POLICY "Users manage own saved sales" ON public.saved_sales FOR ALL USING (
  user_id IN (SELECT id FROM public.users WHERE auth_id = auth.uid())
);

-- Notifications
CREATE POLICY "Users view own notifications" ON public.notifications FOR SELECT USING (
  user_id IN (SELECT id FROM public.users WHERE auth_id = auth.uid())
);
CREATE POLICY "Users update own notifications" ON public.notifications FOR UPDATE USING (
  user_id IN (SELECT id FROM public.users WHERE auth_id = auth.uid())
);

-- Item tracking
CREATE POLICY "Users manage own tracking" ON public.item_tracking FOR ALL USING (
  user_id IN (SELECT id FROM public.users WHERE auth_id = auth.uid())
);

-- Payments
CREATE POLICY "Users view own payments" ON public.payments FOR SELECT USING (
  user_id IN (SELECT id FROM public.users WHERE auth_id = auth.uid())
);

-- ============================================
-- REALTIME
-- ============================================
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.reservations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.sales;
