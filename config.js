/* Configuração do app RAS Multitanques.
   Deixe em branco para o modo demonstração (usuários e senhas só neste aparelho).
   Para login de verdade, cole aqui o endereço e a chave pública (anon) do seu projeto Supabase:
   Supabase > Project Settings > API > Project URL e anon public key. */
window.RAS_CONFIG = {
  supabaseUrl: "https://esoxotcseujyomsqefiv.supabase.co",
  supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVzb3hvdGNzZXVqeW9tc3FlZml2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI1Mzk3MDAsImV4cCI6MjEwODExNTcwMH0.1FEfxg8HMtzlYKs9xhs4R3FhnteG1gyXEOikTc9vfno",
  /* Versão básica no celular: false = só login de usuário; a administração aparece como "versão avançada" bloqueada.
     Para liberar a administração também no celular, troque para true. */
  adminNoCelular: false
};
