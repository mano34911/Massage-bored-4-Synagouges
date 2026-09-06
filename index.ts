import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "Unauthorized" }, 401);

    const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
    if (userErr || !userData.user) return json({ error: "Unauthorized" }, 401);
    const caller = userData.user;

    const { data: profile, error: profileErr } = await admin
      .from("profiles")
      .select("role")
      .eq("user_id", caller.id)
      .single();

    if (profileErr || !profile) return json({ error: "Profile not found" }, 403);

    const body = await req.json();
    const action = String(body.action || "");
    let synagogueId = body.synagogue_id ? String(body.synagogue_id) : "";

    const isMaster = profile.role === "master";

    if (!isMaster) {
      const { data: syn, error: synErr } = await admin
        .from("synagogues")
        .select("id")
        .eq("owner_user_id", caller.id)
        .single();

      if (synErr || !syn) return json({ error: "You do not own a synagogue account" }, 403);
      synagogueId = syn.id;
    } else if (!synagogueId) {
      return json({ error: "synagogue_id is required for master admin" }, 400);
    }

    const getMember = async (id: string) => {
      const { data, error } = await admin
        .from("synagogue_members")
        .select("*")
        .eq("id", id)
        .eq("synagogue_id", synagogueId)
        .single();
      if (error || !data) throw new Error("Member not found in this synagogue");
      return data;
    };

    if (action === "list") {
      const { data, error } = await admin
        .from("synagogue_members")
        .select("*")
        .eq("synagogue_id", synagogueId)
        .order("member_number", { ascending: true });
      if (error) throw error;
      return json({ members: data || [] });
    }

    if (action === "create") {
      const m = body.member || {};
      const email = String(m.login_email || "").trim().toLowerCase();
      const password = String(m.temporary_password || "");
      const name = String(m.full_name || "").trim();

      if (!email || !name || password.length < 6) {
        return json({ error: "Name, email and a temporary password of at least 6 characters are required" }, 400);
      }

      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { full_name: name, account_type: "synagogue_member", synagogue_id: synagogueId },
      });
      if (createErr || !created.user) throw createErr || new Error("Could not create login");

      const row = {
        synagogue_id: synagogueId,
        auth_user_id: created.user.id,
        full_name: name,
        login_email: email,
        phone: String(m.phone || "").trim(),
        address_line1: String(m.address_line1 || "").trim(),
        address_line2: String(m.address_line2 || "").trim(),
        city: String(m.city || "").trim(),
        state: String(m.state || "").trim(),
        postal_code: String(m.postal_code || "").trim(),
        notes: String(m.notes || "").trim(),
        status: "approved",
      };

      const { data, error } = await admin.from("synagogue_members").insert(row).select("*").single();
      if (error) {
        await admin.auth.admin.deleteUser(created.user.id);
        throw error;
      }
      return json({ member: data });
    }

    const memberId = String(body.member_id || "");
    if (!memberId) return json({ error: "member_id is required" }, 400);
    const member = await getMember(memberId);

    if (action === "approve") {
      if (member.auth_user_id) {
        const { error } = await admin.auth.admin.updateUserById(member.auth_user_id, { ban_duration: "none" });
        if (error) throw error;
      }
      const { data, error } = await admin
        .from("synagogue_members")
        .update({ status: "approved" })
        .eq("id", member.id)
        .eq("synagogue_id", synagogueId)
        .select("*").single();
      if (error) throw error;
      return json({ member: data });
    }

    if (action === "suspend") {
      if (member.auth_user_id) {
        const { error } = await admin.auth.admin.updateUserById(member.auth_user_id, { ban_duration: "876000h" });
        if (error) throw error;
      }
      const { data, error } = await admin
        .from("synagogue_members")
        .update({ status: "suspended" })
        .eq("id", member.id)
        .eq("synagogue_id", synagogueId)
        .select("*").single();
      if (error) throw error;
      return json({ member: data });
    }

    if (action === "set_password") {
      const password = String(body.new_password || "");
      if (password.length < 6) return json({ error: "Password must be at least 6 characters" }, 400);
      if (!member.auth_user_id) return json({ error: "This member does not have an Auth login" }, 400);
      const { error } = await admin.auth.admin.updateUserById(member.auth_user_id, { password });
      if (error) throw error;
      return json({ ok: true });
    }

    if (action === "edit") {
      const m = body.member || {};
      const newEmail = String(m.login_email ?? member.login_email).trim().toLowerCase();
      const patch = {
        full_name: String(m.full_name ?? member.full_name).trim(),
        login_email: newEmail,
        phone: String(m.phone ?? member.phone ?? "").trim(),
        address_line1: String(m.address_line1 ?? member.address_line1 ?? "").trim(),
        address_line2: String(m.address_line2 ?? member.address_line2 ?? "").trim(),
        city: String(m.city ?? member.city ?? "").trim(),
        state: String(m.state ?? member.state ?? "").trim(),
        postal_code: String(m.postal_code ?? member.postal_code ?? "").trim(),
        notes: String(m.notes ?? member.notes ?? "").trim(),
      };

      if (!patch.full_name || !patch.login_email) return json({ error: "Name and email are required" }, 400);

      if (member.auth_user_id && newEmail !== String(member.login_email || "").toLowerCase()) {
        const { error } = await admin.auth.admin.updateUserById(member.auth_user_id, {
          email: newEmail,
          email_confirm: true,
          user_metadata: { full_name: patch.full_name, account_type: "synagogue_member", synagogue_id: synagogueId },
        });
        if (error) throw error;
      } else if (member.auth_user_id) {
        const { error } = await admin.auth.admin.updateUserById(member.auth_user_id, {
          user_metadata: { full_name: patch.full_name, account_type: "synagogue_member", synagogue_id: synagogueId },
        });
        if (error) throw error;
      }

      const { data, error } = await admin
        .from("synagogue_members")
        .update(patch)
        .eq("id", member.id)
        .eq("synagogue_id", synagogueId)
        .select("*").single();
      if (error) throw error;
      return json({ member: data });
    }

    if (action === "delete") {
      if (member.auth_user_id) {
        const { error } = await admin.auth.admin.deleteUser(member.auth_user_id);
        if (error) throw error;
        // auth FK ON DELETE CASCADE normally removes the public row.
      }
      const { error } = await admin
        .from("synagogue_members")
        .delete()
        .eq("id", member.id)
        .eq("synagogue_id", synagogueId);
      if (error) throw error;
      return json({ ok: true });
    }

    return json({ error: "Unknown action" }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
