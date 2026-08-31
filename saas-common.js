(function(){
  function configured(){
    const c=window.APP_CONFIG||{};
    return c.SUPABASE_URL && c.SUPABASE_PUBLISHABLE_KEY &&
      !c.SUPABASE_URL.includes("PASTE_") && !c.SUPABASE_PUBLISHABLE_KEY.includes("PASTE_");
  }
  window.appConfigured=configured;
  window.getSupabase=function(){
    if(!configured()) throw new Error("Supabase is not configured yet. Open supabase-config.js and add your Project URL and publishable key.");
    if(!window.supabase || typeof window.supabase.createClient!=="function"){
      throw new Error("The Supabase library did not load. Check your internet connection and reload the page.");
    }
    if(!window.__sb){
      window.__sb = window.supabase.createClient(
        window.APP_CONFIG.SUPABASE_URL,
        window.APP_CONFIG.SUPABASE_PUBLISHABLE_KEY,
        { auth:{persistSession:true, autoRefreshToken:true,detectSessionInUrl:true} }
      );
    }
    return window.__sb;
  };
  window.money=function(cents){ return new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format((Number(cents)||0)/100); };
  window.daysLeft=function(iso){
    if(!iso) return null;
    return Math.max(0, Math.ceil((new Date(iso).getTime()-Date.now())/86400000));
  };
  window.memberAccessState=function(s){
    if(!s) return {allowed:false,label:"No account"};
    if(s.status==="active") return {allowed:true,label:"Active"};
    if(s.status==="trial"){
      const left=daysLeft(s.trial_ends_at);
      return {allowed:left>0,label:left>0?`Free trial — ${left} day${left===1?"":"s"} left`:"Trial expired"};
    }
    return {allowed:false,label:s.status||"Inactive"};
  };
  window.logoutApp=async function(){
    try{ await getSupabase().auth.signOut(); }catch(e){}
    location.href="login.html";
  };
})();
